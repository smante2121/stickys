import AppKit
import OSLog

/// Reads and writes notes on disk:
///
///     ~/Library/Application Support/Stickys/
///       notes.json            ← positions, sizes, styles of every note
///       Notes/<id>.rtfd      ← each note's rich text (opens in TextEdit too)
final class NoteStore {
    let directory: URL
    private let log = Logger(subsystem: "app.stickys.Stickys", category: "store")

    private var indexURL: URL { directory.appending(path: "notes.json") }
    private var notesDirectory: URL { directory.appending(path: "Notes", directoryHint: .isDirectory) }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "Stickys", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        } catch {
            log.error("Couldn't create storage folder: \(error.localizedDescription)")
        }
    }

    // MARK: - Index

    private struct Index: Codable {
        var version = 1
        var notes: [Note]
    }

    func loadNotes() -> [Note] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Index.self, from: data).notes
        } catch {
            // Never silently overwrite a file we couldn't read — keep a copy.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appending(path: "notes.unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
            log.error("notes.json unreadable (\(error.localizedDescription)); backed up to \(backup.path)")
            return []
        }
    }

    func saveNotes(_ notes: [Note]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Index(notes: notes))
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Couldn't save notes.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Note text

    private func contentURL(for id: UUID) -> URL {
        notesDirectory.appending(path: "\(id.uuidString).rtfd", directoryHint: .isDirectory)
    }

    func loadContent(for id: UUID) -> NSAttributedString? {
        let url = contentURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
        } catch {
            log.error("Couldn't read note \(id): \(error.localizedDescription)")
            return nil
        }
    }

    func saveContent(_ text: NSAttributedString, for id: UUID) {
        do {
            let wrapper = try text.fileWrapper(
                from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            try wrapper.write(to: contentURL(for: id), options: .atomic, originalContentsURL: nil)
        } catch {
            log.error("Couldn't save note \(id): \(error.localizedDescription)")
        }
    }

    /// Deleted notes go to the Trash, so they can still be recovered.
    func trashContent(for id: UUID) {
        let url = contentURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            log.error("Couldn't trash note \(id): \(error.localizedDescription)")
        }
    }
}
