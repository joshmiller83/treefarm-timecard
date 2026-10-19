import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The time card as a PDF file for the share sheet. It's printed when someone actually
/// shares it, not on every redraw of the Report tab.
struct TimeCardPDFFile: Transferable {
    var card: PaperTimeCard

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try file.write())
        }
    }

    /// Writes the PDF to a temporary file named after the card.
    func write() throws -> URL {
        let url = try ExportFolder.url(for: card.fileName, extension: "pdf")
        try ReportPDF.render(card).write(to: url, options: .atomic)
        return url
    }
}

/// The time card as a CSV file for the share sheet.
struct TimeCardCSVFile: Transferable {
    var csv: String
    var fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(try file.write())
        }
    }

    func write() throws -> URL {
        let url = try ExportFolder.url(for: fileName, extension: "csv")
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }
}

/// A fresh temporary folder per export, so two exports never share a file.
enum ExportFolder {
    static func url(for name: String, extension ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeCardExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name).appendingPathExtension(ext)
    }
}
