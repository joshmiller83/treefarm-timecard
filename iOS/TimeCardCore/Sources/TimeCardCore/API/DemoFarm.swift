import Foundation

/// A made-up farm for UI-test runs, previews and trying the app with no server.
/// It's generic on purpose: no real farm or person is in it.
public enum DemoFarm {
    public static let email = "demo@example.com"
    public static let password = "demo-password"
    /// Sam Ortiz, the demo worker, signs in with `password` too.
    public static let workerEmail = "sam@example.com"
    /// An open worker invite on the demo farm, to try joining with.
    public static let inviteCode = "K7Q4-M2XP-9R"

    /// A stub server already holding the demo farm. With `signedIn`, the demo admin's
    /// session is live on it (as if they'd signed in before), next to one other device.
    public static func makeServer(signedIn: Bool = true, now: Date = Date()) -> (server: StubAPIClient, me: MeResponse) {
        let records = makeRecords(now: now)
        let ipad = SessionInfo(id: UUID(), deviceName: "Shop iPad", createdAt: now.addingTimeInterval(-20 * 86400),
                               lastUsedAt: now.addingTimeInterval(-2 * 86400), isCurrent: false)
        let invite = InviteInfo(id: UUID(), role: .worker, note: "New trimmer", createdAt: now.addingTimeInterval(-86400),
                                expiresAt: now.addingTimeInterval(6 * 86400), code: inviteCode)
        let server = StubAPIClient(seed: .init(farmId: records.farm.id, records: records.all,
                                              accounts: [.init(email: email, password: password, me: records.me),
                                                         .init(email: workerEmail, password: password, me: records.workerMe)],
                                              signedIn: signedIn ? records.me : nil,
                                              sessions: [ipad], invites: [invite]))
        return (server, records.me)
    }

    struct Records {
        var farm: Farm
        var me: MeResponse
        var workerMe: MeResponse
        var all: [SyncRecord]
    }

    static func makeRecords(now: Date) -> Records {
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: now) ?? now
        let farmId = UUID()
        let season = Season(farmId: farmId, name: "This season", startedAt: start, updatedAt: start)
        let farm = Farm(id: farmId, name: "Pine Hollow Tree Farm", timeZoneId: TimeZone.current.identifier, weekStart: .monday,
                        activeSeasonId: season.id, updatedAt: start)
        let admin = UserProfile(id: UUID(), email: email, displayName: "Alex Rivera")
        let adminMember = Member(userId: admin.id, farmId: farmId, displayName: admin.displayName, email: email, role: .admin,
                                 jobTitle: "Crew lead", rateCents: 2000, updatedAt: start)
        let workerProfile = UserProfile(id: UUID(), email: workerEmail, displayName: "Sam Ortiz")
        let worker = Member(userId: workerProfile.id, farmId: farmId, displayName: workerProfile.displayName, email: workerEmail, role: .worker,
                            jobTitle: "Trimmer", updatedAt: start)

        let north = Field(farmId: farmId, name: "North Field", sortOrder: 0, updatedAt: start)
        let creek = Field(farmId: farmId, name: "Creek Field", sortOrder: 1, updatedAt: start)
        var blocks: [Block] = []
        for (index, (row, column)) in [(0, 0), (0, 1), (1, 0), (1, 1)].enumerated() {
            blocks.append(Block(fieldId: north.id, name: "\(index + 1)", gridRow: row, gridColumn: column,
                                rowCount: 20, treesPerRow: 12, updatedAt: start))
        }
        blocks.append(Block(fieldId: creek.id, name: "1", gridRow: 0, gridColumn: 0, rowCount: 30, treesPerRow: 8, direction: .down, updatedAt: start))

        // Sam shaped the first four rows of North block 1 on an earlier shift.
        let samShift = Shift(userId: worker.userId, farmId: farmId, start: start.addingTimeInterval(8 * 3600),
                             end: start.addingTimeInterval(16 * 3600), rateCents: 0, updatedAt: start)
        var marks: [SyncRecord] = []
        for row in 0..<4 {
            for position in 0..<12 {
                let at = start.addingTimeInterval(9 * 3600 + Double(row * 12 + position) * 240)
                marks.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: blocks[0].id, row: row, position: position),
                                                shiftId: samShift.id, userId: worker.userId, markedAt: at)))
            }
        }

        let me = MeResponse(user: admin, farms: [farm], memberships: [adminMember])
        let workerMe = MeResponse(user: workerProfile, farms: [farm], memberships: [worker])
        let all: [SyncRecord] = [.farm(farm), .season(season), .member(adminMember), .member(worker), .field(north), .field(creek)]
            + blocks.map(SyncRecord.block) + [.shift(samShift)] + marks
        return Records(farm: farm, me: me, workerMe: workerMe, all: all)
    }
}
