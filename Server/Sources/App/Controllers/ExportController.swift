import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// `GET export.csv?from=<ms>&to=<ms>&userId=<id>`: shifts that clock in within
/// [from, to), in the farm's time zone. Workers get their own; admins anyone's.
struct ExportController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.farmRoutes().get("export.csv", use: export)
    }

    func export(req: Request) async throws -> Response {
        let ctx = try req.requireFarm()
        let now = req.now
        let from = try req.queryInt64("from").map(Date.init(millis:))
        let to = try req.queryInt64("to").map(Date.init(millis:))
        var userId: UUID?
        if let raw = req.query[String.self, at: "userId"], !raw.isEmpty {
            guard let id = UUID(uuidString: raw) else { throw Abort(.badRequest, reason: "userId has to be an id.") }
            userId = id
        }
        if !ctx.isAdmin {
            if let userId, userId != ctx.member.userId {
                throw Abort(.forbidden, reason: "You can only export your own hours.")
            }
            userId = ctx.member.userId
        }

        let store = RecordStore(db: req.db)
        guard let farm = try await store.farm(ctx.farmId) else { throw Abort(.notFound, reason: "That farm doesn’t exist.") }
        let shifts = try await store.all(.shift, farm: ctx.farmId) { q in
            q.filter(\.$deletedAt == nil)
            if let userId { q.filter(\.$ownerUserId == userId) }
            if let from { q.filter(\.$startsAt >= from) }
            if let to { q.filter(\.$startsAt < to) }
        }
        .compactMap { if case .shift(let s) = $0.record { return s }; return nil }

        var names: [UUID: String] = [:]
        for m in try await store.members(farm: ctx.farmId) { names[m.userId] = m.displayName }
        let calendar = FarmCalendar(farm: farm)

        let rows = shifts
            .map { (shift: $0, name: names[$0.userId] ?? "Unknown") }
            .sorted { ($0.shift.start, $0.name) < ($1.shift.start, $1.name) }
        var csv = CSV.row(["Name", "Date", "In", "Out", "Breaks", "Hours", "Notes"])
        for (shift, name) in rows {
            let day = calendar.dayKey(shift.start)
            csv += CSV.row([
                name,
                "\(day.year)-\(pad2(day.month))-\(pad2(day.day))",
                Fmt.time(shift.start, calendar),
                shift.end.map { Fmt.time($0, calendar) } ?? "",
                String(Int((shift.breakTime(at: now) / 60).rounded())),
                Fmt.decimalHours(shift.workedTime(at: now)),
                shift.notes,
            ])
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "text/csv; charset=utf-8")
        headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"time-card.csv\"")
        return Response(status: .ok, headers: headers, body: .init(string: csv))
    }

    private func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
