import Foundation

public struct LoadReport: Sendable {
    public var pages: [Page]
    public var warnings: [String]
    public init(pages: [Page] = [], warnings: [String] = []) {
        self.pages = pages
        self.warnings = warnings
    }
}

public struct TrashCleanupReport: Sendable {
    public var removedIDs: [UUID] = []
    public var warnings: [String] = []
    public init() {}
}

public enum RepositoryError: LocalizedError {
    case identityMismatch(String)
    case alreadyExists
    case unsafeTrashEntry(String)
    case unreadableTrashLetter(String)
    public var errorDescription: String? {
        switch self {
        case .identityMismatch(let file): return "The identity inside \(file) does not match its filename."
        case .alreadyExists: return "A letter with this identity already exists. Neither copy was overwritten."
        case .unsafeTrashEntry(let path): return "The unexpected item at \(path) was left untouched. Recently Deleted cleanup only handles regular letter files."
        case .unreadableTrashLetter(let name): return "Could not identify \(name) as a saved letter. It was left untouched in Recently Deleted."
        }
    }
}

/// Deliberately synchronous: callers serialize short, debounced writes.
/// One JSON file per letter; atomic replacement and a last-valid backup.
public final class PageRepository {
    public static let trashRetentionInterval: TimeInterval = 30 * 24 * 60 * 60
    public let rootURL: URL
    public var pagesURL: URL { rootURL.appendingPathComponent("Letters", isDirectory: true) }
    public var trashURL: URL { rootURL.appendingPathComponent("Recently Deleted", isDirectory: true) }
    private let fm: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private struct TrashReceipt: Codable {
        var version = 1
        let id: UUID
        let deletedAt: Date
    }

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        self.fm = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try fm.createDirectory(at: pagesURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
    }

    public func fileURL(for id: UUID, inTrash: Bool = false) -> URL {
        (inTrash ? trashURL : pagesURL).appendingPathComponent(id.uuidString + ".json")
    }

    public func load(inTrash: Bool = false) throws -> LoadReport {
        let folder = inTrash ? trashURL : pagesURL
        let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var result = LoadReport()
        for url in files {
            do {
                result.pages.append(try decode(Data(contentsOf: url), expectedURL: url))
            } catch {
                let backup = url.appendingPathExtension("bak")
                if let bytes = try? Data(contentsOf: backup),
                   let page = try? decode(bytes, expectedURL: url) {
                    result.pages.append(page)
                    result.warnings.append("Recovered \(page.title) from its previous saved copy. The damaged file is preserved until the next successful save.")
                } else {
                    result.warnings.append("Could not read \(url.lastPathComponent). It was left untouched in \(folder.path).")
                }
            }
        }
        result.pages.sort {
            $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt
        }
        return result
    }

    private func decode(_ data: Data, expectedURL: URL) throws -> Page {
        let page = try decoder.decode(Page.self, from: data)
        guard expectedURL.deletingPathExtension().lastPathComponent == page.id.uuidString else {
            throw RepositoryError.identityMismatch(expectedURL.lastPathComponent)
        }
        return page
    }

    public func save(_ page: Page) throws {
        let url = fileURL(for: page.id)
        let newData = try encoder.encode(page)
        if fm.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            if (try? decode(previous, expectedURL: url)) != nil {
                // Never put a known-bad file into the last-valid backup.
                try previous.write(to: url.appendingPathExtension("bak"), options: .atomic)
            } else {
                let recovery = rootURL.appendingPathComponent("Recovery", isDirectory: true)
                try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
                try previous.write(to: recovery.appendingPathComponent("\(page.id)-\(UUID()).damaged"), options: .atomic)
            }
        }
        try newData.write(to: url, options: .atomic)
    }

    public func moveToTrash(_ id: UUID, at now: Date = Date()) throws {
        let source = fileURL(for: id)
        let destination = fileURL(for: id, inTrash: true)
        try requireTrashDirectory()
        guard try fileType(at: destination) == nil else { throw RepositoryError.alreadyExists }
        guard try fileType(at: source) == .typeRegular else {
            throw RepositoryError.unsafeTrashEntry(source.path)
        }
        // Save the deletion date before moving the letter. A failed receipt write
        // leaves the active letter in place; a failed move only leaves a harmless
        // receipt that is overwritten with a fresh date on the next deletion.
        try writeReceipt(for: id, at: now)
        try fm.moveItem(at: source, to: destination)
        // A backup is best effort only after the primary move succeeds.
        let backup = source.appendingPathExtension("bak")
        if fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: destination.appendingPathExtension("bak"))
        }
    }

    public func restore(_ id: UUID) throws {
        let source = fileURL(for: id, inTrash: true)
        let destination = fileURL(for: id)
        guard !fm.fileExists(atPath: destination.path) else { throw RepositoryError.alreadyExists }
        try fm.moveItem(at: source, to: destination)
        let backup = source.appendingPathExtension("bak")
        if fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: destination.appendingPathExtension("bak"))
        }
        // Clearing metadata is best effort only after the letter is safely back.
        // A leftover receipt can never cause cleanup to delete an active letter.
        let receipt = receiptURL(for: id)
        if (try? fileType(at: receipt)) == .typeRegular { try? fm.removeItem(at: receipt) }
    }

    /// Permanently removes only identified letters in this repository's trash.
    /// Legacy letters get a full grace period from their first cleanup pass;
    /// their editing date and filesystem timestamps are never used as deletion dates.
    public func cleanupRecentlyDeleted(now: Date = Date()) throws -> TrashCleanupReport {
        try requireTrashDirectory()
        let files = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        let ids = Set(files.compactMap { trashID(from: $0.lastPathComponent) })
        var report = TrashCleanupReport()
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let primary = fileURL(for: id, inTrash: true)
            let backup = primary.appendingPathExtension("bak")
            let receipt = receiptURL(for: id)
            do {
                for url in [primary, backup, receipt] { try requireRegularIfPresent(url) }
                let letterFiles = try [primary, backup].filter { try fileType(at: $0) != nil }
                let identifiedFiles = try letterFiles.isEmpty ? Set<URL>()
                    : identifyTrashLetter(id, files: letterFiles, expectedURL: primary)

                let hadReceipt = try fileType(at: receipt) != nil
                let storedReceipt = try readReceipt(for: id)
                if let storedReceipt, storedReceipt.version != 1 {
                    report.warnings.append("The deletion record for \(id.uuidString) uses an unrecognized format. Its files were left untouched.")
                    continue
                }
                guard let storedReceipt, storedReceipt.id == id,
                      storedReceipt.deletedAt.timeIntervalSince1970.isFinite else {
                    // Do not invent a date for a metadata-only entry. There is no
                    // identifiable letter here to migrate or permanently remove.
                    guard !letterFiles.isEmpty else { continue }
                    try writeReceipt(for: id, at: now)
                    if hadReceipt {
                        report.warnings.append("The deletion date for \(id.uuidString) could not be verified. Its letter was kept and given a fresh 30-day restore period.")
                    }
                    continue
                }
                guard now.timeIntervalSince(storedReceipt.deletedAt) >= Self.trashRetentionInterval else { continue }

                // Keep the receipt until both data files have been removed. If a
                // removal fails, the next pass can finish with the same deadline.
                // Keep an identifiable copy until last, so failed removal always
                // leaves enough information to verify the pair on the next pass.
                // Normally that is the primary; for a damaged primary recovered
                // by load(), it is the previous valid backup instead.
                let preferredOrder = [backup, primary].filter { letterFiles.contains($0) }
                let removalOrder = preferredOrder.filter { !identifiedFiles.contains($0) }
                    + preferredOrder.filter { identifiedFiles.contains($0) }
                for url in removalOrder where try fileType(at: url) != nil {
                    try requireRegularIfPresent(url)
                    try fm.removeItem(at: url)
                    // load(inTrash:) lists primary files, so refresh its cached
                    // rows even if a later backup/receipt removal has to retry.
                    if url == primary { report.removedIDs.append(id) }
                }
                if !letterFiles.isEmpty, !report.removedIDs.contains(id) { report.removedIDs.append(id) }
                try fm.removeItem(at: receipt)
            } catch {
                report.warnings.append("Could not finish Recently Deleted cleanup for \(id.uuidString). Remaining files were kept for another attempt.\n\(error.localizedDescription)")
            }
        }
        return report
    }

    private func receiptURL(for id: UUID) -> URL {
        trashURL.appendingPathComponent(id.uuidString + ".trashinfo")
    }

    private func readReceipt(for id: UUID) throws -> TrashReceipt? {
        let url = receiptURL(for: id)
        guard try fileType(at: url) != nil else { return nil }
        let bytes = try Data(contentsOf: url)
        let receiptDecoder = JSONDecoder()
        receiptDecoder.dateDecodingStrategy = .secondsSince1970
        return try? receiptDecoder.decode(TrashReceipt.self, from: bytes)
    }

    private func writeReceipt(for id: UUID, at date: Date) throws {
        let url = receiptURL(for: id)
        try requireRegularIfPresent(url)
        let receiptEncoder = JSONEncoder()
        receiptEncoder.dateEncodingStrategy = .secondsSince1970
        receiptEncoder.outputFormatting = [.sortedKeys]
        try receiptEncoder.encode(TrashReceipt(id: id, deletedAt: date)).write(to: url, options: .atomic)
    }

    private func trashID(from name: String) -> UUID? {
        for suffix in [".json.bak", ".json", ".trashinfo"] where name.hasSuffix(suffix) {
            let value = String(name.dropLast(suffix.count))
            if let id = UUID(uuidString: value), value == id.uuidString { return id }
        }
        return nil
    }

    private func identifyTrashLetter(_ id: UUID, files: [URL], expectedURL: URL) throws -> Set<URL> {
        var identified = Set<URL>()
        for url in files {
            let bytes = try Data(contentsOf: url)
            if let page = try? decoder.decode(Page.self, from: bytes) {
                guard page.id == id else { throw RepositoryError.identityMismatch(url.lastPathComponent) }
                identified.insert(url)
            }
        }
        // A readable primary or previous valid copy can identify the pair, just
        // as load() can recover a damaged primary from its matching backup.
        guard !identified.isEmpty else { throw RepositoryError.unreadableTrashLetter(expectedURL.lastPathComponent) }
        return identified
    }

    private func requireTrashDirectory() throws {
        guard try fileType(at: trashURL) == .typeDirectory else {
            throw RepositoryError.unsafeTrashEntry(trashURL.path)
        }
    }

    private func requireRegularIfPresent(_ url: URL) throws {
        if let type = try fileType(at: url), type != .typeRegular {
            throw RepositoryError.unsafeTrashEntry(url.path)
        }
    }

    private func fileType(at url: URL) throws -> FileAttributeType? {
        do { return try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
}
