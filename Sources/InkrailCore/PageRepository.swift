import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
    case changedOnDisk
    case concurrentRevision(URL)
    case libraryBusy
    case interruptedTransfer(String)
    case alreadyExists
    case unsafeTrashEntry(String)
    case unreadableTrashLetter(String)
    public var errorDescription: String? {
        switch self {
        case .identityMismatch(let file): return "The identity inside \(file) does not match its filename."
        case .changedOnDisk: return "The saved copy changed since this letter was opened. Export your edits, then reopen the library to read the current copy."
        case .concurrentRevision(let copy): return "The file changed during the save. Inkrail preserved the displaced version at \(copy.path)."
        case .libraryBusy: return "Another library operation is in progress. Try again when it finishes."
        case .interruptedTransfer(let path): return "An interrupted letter transfer needs attention at \(path). Its files have been kept."
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

    private enum PrimaryRevision: Equatable {
        case missing, unreadable
        case bytes(Data)
    }

    private struct Revision {
        let primary: PrimaryRevision
        // Only a recovered page depends on a particular backup.
        var backup: Data?
    }
    private var revisions: [UUID: Revision] = [:]

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
        try withLibraryLock {
            let folder = inTrash ? trashURL : pagesURL
            var result = LoadReport()
            var unresolved = Set<UUID>()
            // The primary rename commits a transfer. Roll its backup back if the
            // app stopped first, before interpreting a lone .bak as a letter.
            let trashEntries: [URL]
            do {
                try requireTrashDirectory()
                trashEntries = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
            } catch {
                if inTrash { throw error }
                trashEntries = []
                result.warnings.append("Could not inspect Recently Deleted for interrupted transfers.\n\(error.localizedDescription)")
            }
            for id in Set(trashEntries.compactMap { trashID(from: $0.lastPathComponent) }) {
                do { try reconcileTransfers(id) }
                catch {
                    unresolved.insert(id)
                    result.warnings.append(error.localizedDescription)
                }
            }
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let primaries = Set(files.compactMap { url -> URL? in
                if url.pathExtension == "json" { return url }
                guard url.lastPathComponent.hasSuffix(".json.bak") else { return nil }
                return url.deletingPathExtension()
            })
            for url in primaries {
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                // While rollback is blocked, keep the original primary visible,
                // but don't offer its partly moved backup as a second letter.
                if let id, unresolved.contains(id), !fm.fileExists(atPath: url.path) { continue }
                do {
                    let (page, revision) = try readLetter(at: url)
                    if !inTrash { revisions[page.id] = revision }
                    result.pages.append(page)
                    if revision.backup != nil {
                        result.warnings.append("Recovered \(page.title) from its previous saved copy at \(url.appendingPathExtension("bak").path).")
                    }
                } catch {
                    result.warnings.append("Could not read \(url.lastPathComponent). Its files were kept in \(folder.path).\n\(error.localizedDescription)")
                }
            }
            result.pages.sort {
                $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt
            }
            return result
        }
    }

    private func decode(_ data: Data, expectedURL: URL) throws -> Page {
        let page = try decoder.decode(Page.self, from: data)
        guard expectedURL.deletingPathExtension().lastPathComponent == page.id.uuidString else {
            throw RepositoryError.identityMismatch(expectedURL.lastPathComponent)
        }
        return page
    }

    private func fingerprint(_ bytes: Data) -> Data {
        #if canImport(CryptoKit)
        return Data(SHA256.hash(data: bytes))
        #else
        // The portable core has no crypto dependency. Full bytes keep the same
        // comparison semantics on systems without Apple's SHA-256 implementation.
        return bytes
        #endif
    }

    private func regularData(at url: URL) throws -> Data? {
        guard let type = try fileType(at: url) else { return nil }
        guard type == .typeRegular else { throw RepositoryError.unsafeTrashEntry(url.path) }
        return try Data(contentsOf: url)
    }

    private func readLetter(at url: URL) throws -> (Page, Revision) {
        var primary: PrimaryRevision = .unreadable
        do {
            if let data = try regularData(at: url) {
                primary = .bytes(fingerprint(data))
                return (try decode(data, expectedURL: url), Revision(primary: primary))
            }
            primary = .missing
        } catch {
            // Keep the observed bytes for damaged JSON. An I/O error leaves
            // the primary unknown, and edits cannot overwrite it on retry.
        }
        guard let backup = try regularData(at: url.appendingPathExtension("bak")) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (try decode(backup, expectedURL: url), Revision(primary: primary, backup: fingerprint(backup)))
    }

    private func verifyRevision(_ id: UUID, at url: URL, previous: Data?) throws {
        let known = revisions[id]
        let current = previous.map { PrimaryRevision.bytes(fingerprint($0)) } ?? .missing
        guard current == (known?.primary ?? .missing) else { throw RepositoryError.changedOnDisk }
        if let expected = known?.backup {
            guard let backup = try regularData(at: url.appendingPathExtension("bak")),
                  expected == fingerprint(backup) else { throw RepositoryError.changedOnDisk }
        } else if known == nil, try fileType(at: url.appendingPathExtension("bak")) != nil {
            throw RepositoryError.changedOnDisk
        }
    }

    // The root directory itself is a stable lock across atomic file renames.
    // A separate open per operation also serializes independent handles in the
    // same process. No lock files are added to users' existing libraries.
    private func withLibraryLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = close(fd) }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno == EWOULDBLOCK { throw RepositoryError.libraryBusy }
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try body()
    }

    public func copyLibrary(to destination: URL) throws -> PageRepository {
        try withLibraryLock {
            let copy = try LibraryLocation.copyLibrary(from: rootURL, to: destination, fileManager: fm)
            copy.revisions = revisions
            return copy
        }
    }

    public func save(_ page: Page) throws {
        try withLibraryLock {
            if try fileType(at: trashURL) == nil {
                // The root is open and locked. Repair this single missing
                // subfolder when possible, while allowing intact letters to save.
                try? fm.createDirectory(at: trashURL, withIntermediateDirectories: false)
            } else {
                try requireTrashDirectory()
                try finishInterruptedTransfer(page.id)
            }
            let url = fileURL(for: page.id)
            let previous = try regularData(at: url)
            try verifyRevision(page.id, at: url, previous: previous)
            let newData = try encoder.encode(page)
            if let previous {
                if (try? decode(previous, expectedURL: url)) != nil {
                    try previous.write(to: url.appendingPathExtension("bak"), options: .atomic)
                } else {
                    try preserveDamaged(previous, id: page.id)
                }
            }
            try install(newData, at: url, replacing: previous, id: page.id)
            revisions[page.id] = Revision(primary: .bytes(fingerprint(newData)))
        }
    }

    private func install(_ bytes: Data, at url: URL, replacing previous: Data?, id: UUID) throws {
        // Stage on the same volume. Even a writer that ignores Inkrail's lock
        // cannot race a full file write between the final check and the rename.
        let staged = pagesURL.appendingPathComponent("\(id.uuidString)-\(UUID()).pending")
        let mode: mode_t
        if previous != nil, let permissions = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber {
            mode = mode_t(permissions.uint16Value & 0o777)
        } else {
            mode = 0o666
        }
        let fd = open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var removeStaging = true
        defer { if removeStaging { try? fm.removeItem(at: staged) } }
        try file.write(contentsOf: bytes)
        try file.synchronize()
        try file.close()
        try verifyRevision(id, at: url, previous: regularData(at: url))
        guard previous != nil else {
            try fm.moveItem(at: staged, to: url)  // refuses an existing destination
            return
        }
        #if canImport(Darwin)
        if renamex_np(staged.path, url.path, UInt32(RENAME_SWAP)) == 0 {
            // On volumes supporting atomic exchange, verify the exact displaced
            // file too. Save a racing external revision for the writer to inspect.
            removeStaging = false
            if (try? regularData(at: staged)) == previous {
                removeStaging = true
                return
            }
            revisions[id] = Revision(primary: .bytes(fingerprint(bytes)))
            let recovery = rootURL.appendingPathComponent("Recovery", isDirectory: true)
            let retained = recovery.appendingPathComponent(staged.deletingPathExtension().lastPathComponent + ".conflict")
            do {
                try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
                try fm.moveItem(at: staged, to: retained)
            } catch { throw RepositoryError.concurrentRevision(staged) }
            throw RepositoryError.concurrentRevision(retained)
        }
        guard errno == ENOTSUP || errno == ENOSYS || errno == EINVAL else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #endif
        // Some external volumes only support ordinary POSIX replacement.
        guard rename(staged.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func preserveDamaged(_ bytes: Data, id: UUID) throws {
        let recovery = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        var version = 0
        while true {
            let suffix = version == 0 ? "" : "-\(version)"
            let url = recovery.appendingPathComponent("\(id.uuidString)\(suffix).damaged")
            if let existing = try regularData(at: url) {
                if existing == bytes { return }
                version += 1
            } else {
                try bytes.write(to: url, options: .atomic)
                return
            }
        }
    }

    public func moveToTrash(_ id: UUID, at now: Date = Date()) throws {
        try withLibraryLock {
            _ = try transfer(id, deletedAt: now)
            revisions[id] = nil
        }
    }

    @discardableResult
    public func restore(_ id: UUID) throws -> Page {
        try withLibraryLock { try transfer(id, deletedAt: nil) }
    }

    private func transfer(_ id: UUID, deletedAt: Date?) throws -> Page {
        try requireTrashDirectory()
        try reconcileTransfers(id)
        let deleting = deletedAt != nil
        let source = fileURL(for: id, inTrash: !deleting)
        let destination = fileURL(for: id, inTrash: deleting)
        let backup = source.appendingPathExtension("bak")
        let otherBackup = destination.appendingPathExtension("bak")
        guard try fileType(at: destination) == nil, try fileType(at: otherBackup) == nil
        else { throw RepositoryError.alreadyExists }

        let previous = try regularData(at: source)
        if deleting, revisions[id] != nil { try verifyRevision(id, at: source, previous: previous) }
        let page: Page
        let primary: Data
        if let previous, let decoded = try? decode(previous, expectedURL: source) {
            page = decoded
            primary = previous
        } else {
            guard let saved = try regularData(at: backup) else { throw CocoaError(.fileReadCorruptFile) }
            page = try decode(saved, expectedURL: source)
            if let previous { try preserveDamaged(previous, id: id) }
            // Either side of the commit must have a self-contained, readable primary.
            try saved.write(to: source, options: .atomic)
            primary = saved
            if deleting { revisions[id] = Revision(primary: .bytes(fingerprint(saved))) }
        }
        try requireRegularIfPresent(backup)
        if let deletedAt { try writeReceipt(for: id, at: deletedAt) }
        let marker = transferURL(for: id)
        let hasBackup = try fileType(at: backup) != nil
        if hasBackup {
            try Data((deleting ? "trash-v1" : "restore-v1").utf8).write(to: marker, options: .atomic)
        }
        do {
            if hasBackup { try fm.moveItem(at: backup, to: otherBackup) }
            try fm.moveItem(at: source, to: destination)
        } catch {
            // Keep the journal if rollback itself fails. Launch, listing, saves
            // and retention all reconcile it before using the split files.
            try finishInterruptedTransfer(id)
            throw error
        }
        if !deleting {
            revisions[id] = Revision(primary: .bytes(fingerprint(primary)))
            let receipt = receiptURL(for: id)
            if (try? fileType(at: receipt)) == .typeRegular { try? fm.removeItem(at: receipt) }
        }
        // A leftover marker is an already committed operation: both files are
        // in their final locations, and the next operation can clear it.
        if hasBackup { try? fm.removeItem(at: marker) }
        return page
    }

    // Older versions moved the primary first and ignored backup-move errors.
    // Reunite identifiable split pairs before orphan backups are listed or expired.
    private func reconcileTransfers(_ id: UUID) throws {
        try finishInterruptedTransfer(id)
        let active = fileURL(for: id)
        let trash = fileURL(for: id, inTrash: true)
        let activeBackup = active.appendingPathExtension("bak")
        let trashBackup = trash.appendingPathExtension("bak")
        let activeType = try fileType(at: active)
        let trashType = try fileType(at: trash)
        if activeType == nil, trashType == .typeRegular, try fileType(at: activeBackup) != nil {
            let quarantined = RepositoryError.interruptedTransfer(activeBackup.path)
            try requireRegularIfPresent(receiptURL(for: id))
            guard let receipt = try readReceipt(for: id), receipt.version == 1, receipt.id == id,
                  let prior = try regularData(at: activeBackup),
                  let page = try? decode(prior, expectedURL: active),
                  let trashed = try regularData(at: trash),
                  let current = try? decode(trashed, expectedURL: trash),
                  current.createdAt == page.createdAt, current.modifiedAt >= page.modifiedAt,
                  receipt.deletedAt >= page.modifiedAt,
                  try fileType(at: trashBackup) == nil else { throw quarantined }
            try fm.moveItem(at: activeBackup, to: trashBackup)
        } else if activeType == .typeRegular, trashType == nil, try fileType(at: trashBackup) != nil {
            // An old restore may have installed a damaged primary and stranded its
            // only readable copy in trash. Protect it even if cleanup already
            // assigned the stray backup a deletion date.
            let current = try regularData(at: active)
            if let current, (try? decode(current, expectedURL: active)) != nil { return }
            guard let backup = try regularData(at: trashBackup) else { return }
            _ = try decode(backup, expectedURL: active)
            if let other = try regularData(at: activeBackup) {
                if (try? decode(other, expectedURL: active)) != nil {
                    guard other == backup else { throw RepositoryError.interruptedTransfer(trashBackup.path) }
                    return
                }
                try preserveDamaged(other, id: id)
            }
            // Keep the trash copy until the recovered active backup is durable.
            try backup.write(to: activeBackup, options: .atomic)
            try fm.removeItem(at: trashBackup)
        }
    }

    private func transferURL(for id: UUID) -> URL {
        trashURL.appendingPathComponent(id.uuidString + ".transfer")
    }

    private func finishInterruptedTransfer(_ id: UUID) throws {
        let marker = transferURL(for: id)
        guard let bytes = try regularData(at: marker) else { return }
        let deleting: Bool
        switch String(decoding: bytes, as: UTF8.self) {
        case "trash-v1": deleting = true
        case "restore-v1": deleting = false
        default: throw RepositoryError.interruptedTransfer(marker.path)
        }
        let source = fileURL(for: id, inTrash: !deleting)
        let destination = fileURL(for: id, inTrash: deleting)
        let sourceType = try fileType(at: source)
        let destinationType = try fileType(at: destination)
        if sourceType == .typeRegular, destinationType == nil {
            let backup = source.appendingPathExtension("bak")
            let moved = destination.appendingPathExtension("bak")
            if try fileType(at: moved) != nil {
                try requireRegularIfPresent(moved)
                guard try fileType(at: backup) == nil else { throw RepositoryError.interruptedTransfer(marker.path) }
                try fm.moveItem(at: moved, to: backup)
            }
        } else if sourceType != nil || destinationType != .typeRegular {
            throw RepositoryError.interruptedTransfer(marker.path)
        }
        try fm.removeItem(at: marker)
    }

    /// Permanently removes only identified letters in this repository's trash.
    /// Legacy letters get a full grace period from their first cleanup pass;
    /// their editing date and filesystem timestamps are never used as deletion dates.
    public func cleanupRecentlyDeleted(now: Date = Date()) throws -> TrashCleanupReport {
        try withLibraryLock { try cleanup(now: now) }
    }

    private func cleanup(now: Date) throws -> TrashCleanupReport {
        try requireTrashDirectory()
        let files = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        let ids = Set(files.compactMap { trashID(from: $0.lastPathComponent) })
        var report = TrashCleanupReport()
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let primary = fileURL(for: id, inTrash: true)
            let backup = primary.appendingPathExtension("bak")
            let receipt = receiptURL(for: id)
            do {
                try reconcileTransfers(id)
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
                    // Refresh the row if it now depends on the backup, even if
                    // a later backup or receipt removal has to retry.
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
        for suffix in [".json.bak", ".json", ".trashinfo", ".transfer"] where name.hasSuffix(suffix) {
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
