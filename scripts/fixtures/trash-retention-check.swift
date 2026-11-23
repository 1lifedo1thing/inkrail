import Foundation

private final class FailingRemoval: FileManager, @unchecked Sendable {
    var blocked: URL?
    override func removeItem(at url: URL) throws {
        if url == blocked { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}

private final class FailingMove: FileManager, @unchecked Sendable {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.pathExtension == "json" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: source, to: destination)
    }
}

private final class StorageFailure: FileManager, @unchecked Sendable {
    var unreadable: URL?
    var blockedMove: URL?
    var failInstallationOf: URL?

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if let unreadable, URL(fileURLWithPath: path).resolvingSymlinksInPath().path == unreadable.resolvingSymlinksInPath().path {
            throw CocoaError(.fileReadNoPermission)
        }
        if path == failInstallationOf?.path, let folder = failInstallationOf?.deletingLastPathComponent(),
           try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasSuffix(".pending") }) {
            throw CocoaError(.fileWriteNoPermission)
        }
        return try super.attributesOfItem(atPath: path)
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        if source == blockedMove { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: source, to: destination)
    }
}

@main enum TrashRetentionCheck {
    static let fm = FileManager.default
    static let now = Date(timeIntervalSince1970: 1_800_000_000.375)
    static let duration: TimeInterval = 30 * 24 * 60 * 60
    static var checks = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
        checks += 1
        guard try condition() else { fatalError("FAIL: \(description)") }
    }
    static func rejects(_ description: String, _ body: () throws -> Void) throws {
        do { try body() }
        catch { checks += 1; return }
        fatalError("FAIL: \(description)")
    }
    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
    static func receipt(_ repo: PageRepository, _ id: UUID) -> URL {
        repo.trashURL.appendingPathComponent(id.uuidString + ".trashinfo")
    }
    static func writeReceipt(_ repo: PageRepository, _ id: UUID, at date: Date, version: Int = 1) throws {
        let bytes = try JSONSerialization.data(withJSONObject: ["version": version, "id": id.uuidString,
                                                                 "deletedAt": date.timeIntervalSince1970])
        try bytes.write(to: receipt(repo, id))
    }
    static func makeLetter(_ repo: PageRepository, text: String = "A letter") throws -> Page {
        var letter = Page(createdAt: Date(timeIntervalSince1970: 100), text: text)
        try repo.save(letter)
        letter.text += "\nCurrent version — नमस्ते 世界"
        try repo.save(letter)
        return letter
    }
    static func main() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("inkrail-retention-" + UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: base) }
        try check(PageRepository.trashRetentionInterval == duration, "policy is 30 elapsed days")
        try expiryAndScope(base.appendingPathComponent("Boundary"))
        try restoreAndDeleteAgain(base.appendingPathComponent("Restore"))
        try legacyAndBadDates(base.appendingPathComponent("Legacy"))
        try unsafeEntries(base.appendingPathComponent("Unsafe"))
        try failedRemovalAndRetry(base.appendingPathComponent("Retry"))
        try failedTimestamp(base.appendingPathComponent("Timestamp"))
        try revisionsAndRecovery(base.appendingPathComponent("Revisions"))
        try pairedTransfers(base.appendingPathComponent("Transfer"))
        try interruptedTransfers(base.appendingPathComponent("Restart"))
        try legacySplits(base.appendingPathComponent("Upgraded library"))
        try copiedLibrary(base.appendingPathComponent("Copy"))
        print("PASS: \(checks)/\(checks) Foundation trash-retention checks. Disposable libraries and fixed times only; no user files or real clock waiting.")
    }

    static func expiryAndScope(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let expired = try makeLetter(repo)
        let active = try makeLetter(repo, text: "Active letter")
        let original = try Data(contentsOf: repo.fileURL(for: expired.id))
        let activeBytes = try Data(contentsOf: repo.fileURL(for: active.id))
        let activeBackup = try Data(contentsOf: repo.fileURL(for: active.id).appendingPathExtension("bak"))
        let recovery = root.appendingPathComponent("Recovery")
        try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
        let preserved = recovery.appendingPathComponent("old.damaged")
        try Data("preserve recovery".utf8).write(to: preserved)
        try repo.moveToTrash(expired.id, at: now)
        let trashed = repo.fileURL(for: expired.id, inTrash: true)
        try check(try Data(contentsOf: trashed) == original, "delete preserves original JSON and edit date")
        try check(exists(receipt(repo, expired.id)), "deletion persists a separate retention date")
        let early = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration - 0.001))
        try check(early.removedIDs.isEmpty, "fractional-second boundary keeps letter before 30 days")
        try check(exists(trashed), "old modified date cannot shorten retention")
        let reopened = try PageRepository(rootURL: root)
        let expiredReport = try reopened.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(expiredReport.removedIDs == [expired.id], "exact 30-day boundary removes expired letter after restart")
        try check(expiredReport.warnings.isEmpty, "successful cleanup has no warnings")
        try check(!exists(trashed), "expired primary is removed")
        try check(!exists(trashed.appendingPathExtension("bak")), "matching deleted backup is removed")
        try check(!exists(receipt(repo, expired.id)), "completed cleanup removes retention receipt")
        try check(try Data(contentsOf: repo.fileURL(for: active.id)) == activeBytes, "active letter is unchanged")
        try check(try Data(contentsOf: repo.fileURL(for: active.id).appendingPathExtension("bak")) == activeBackup, "active backup is unchanged")
        try check(try String(contentsOf: preserved) == "preserve recovery", "recovery file is unchanged")
        try check(try reopened.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration * 2)).removedIDs.isEmpty,
                  "repeated cleanup is idempotent")
    }

    static func restoreAndDeleteAgain(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let letter = try makeLetter(repo)
        let original = try Data(contentsOf: repo.fileURL(for: letter.id))
        try repo.moveToTrash(letter.id, at: now)
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration - 1))
        try repo.restore(letter.id)
        try check(!exists(receipt(repo, letter.id)), "restore clears deletion receipt")
        try check(try Data(contentsOf: repo.fileURL(for: letter.id)) == original, "restore preserves original letter bytes")
        try check(exists(repo.fileURL(for: letter.id).appendingPathExtension("bak")), "restore returns backup to active letters")
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration * 3)).removedIDs.isEmpty,
                  "restored letter survives former expiry")
        let deletedAgain = now.addingTimeInterval(duration - 1)
        try repo.moveToTrash(letter.id, at: deletedAgain)
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration)).removedIDs.isEmpty,
                  "second deletion receives a fresh 30-day window")
        try check(try repo.cleanupRecentlyDeleted(now: deletedAgain.addingTimeInterval(duration)).removedIDs == [letter.id],
                  "second deletion expires from its new date")

        let collision = try makeLetter(repo, text: "Collision")
        try repo.moveToTrash(collision.id, at: now)
        try repo.save(collision)
        let savedReceipt = try Data(contentsOf: receipt(repo, collision.id))
        try rejects("restore collision cannot pretend success") { try repo.restore(collision.id) }
        try check(try Data(contentsOf: receipt(repo, collision.id)) == savedReceipt, "failed restore keeps retention date")
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(exists(repo.fileURL(for: collision.id)), "expired duplicate in trash never deletes active copy")
    }

    static func legacyAndBadDates(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let id = UUID(uuidString: "61C185EF-68BB-45BB-99DB-81DE5C7AA0FE")!
        // Literal pre-retention record, independent of the current encoder.
        let legacy = Data("""
        {"id":"61C185EF-68BB-45BB-99DB-81DE5C7AA0FE","createdAt":"2001-01-01T00:00:00Z","modifiedAt":"2001-01-02T00:00:00Z","text":"Legacy deleted letter"}
        """.utf8)
        let oldFile = repo.fileURL(for: id, inTrash: true)
        try legacy.write(to: oldFile)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: oldFile.path)
        let migration = try repo.cleanupRecentlyDeleted(now: now)
        try check(migration.removedIDs.isEmpty, "legacy letter is not immediately purged")
        try check(try Data(contentsOf: oldFile) == legacy, "legacy JSON is not rewritten")
        try check(exists(receipt(repo, id)), "legacy letter receives a deletion receipt")
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration - 1)).removedIDs.isEmpty,
                  "legacy grace lasts a complete 30 days")
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration)).removedIDs == [id],
                  "legacy grace eventually expires")

        let bad = try makeLetter(repo, text: "Malformed receipt")
        try repo.moveToTrash(bad.id, at: now.addingTimeInterval(-duration * 3))
        try Data("bad receipt".utf8).write(to: receipt(repo, bad.id))
        let repaired = try repo.cleanupRecentlyDeleted(now: now)
        try check(repaired.removedIDs.isEmpty, "malformed date cannot cause immediate deletion")
        try check(!repaired.warnings.isEmpty, "malformed date recovery is reported")
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration)).removedIDs == [bad.id],
                  "malformed date receives a full grace period")

        let future = try makeLetter(repo, text: "Future date")
        try repo.moveToTrash(future.id, at: now.addingTimeInterval(duration))
        try check(try repo.cleanupRecentlyDeleted(now: now).removedIDs.isEmpty, "future date or backward clock cannot purge early")
        let unknown = try makeLetter(repo, text: "Future metadata version")
        try repo.moveToTrash(unknown.id, at: now)
        try writeReceipt(repo, unknown.id, at: now.addingTimeInterval(-duration * 3), version: 99)
        let unknownBytes = try Data(contentsOf: receipt(repo, unknown.id))
        let unknownReport = try repo.cleanupRecentlyDeleted(now: now)
        try check(unknownReport.removedIDs.isEmpty, "unknown receipt version is not treated as expired")
        try check(try Data(contentsOf: receipt(repo, unknown.id)) == unknownBytes, "unknown receipt version is preserved")
        try check(!unknownReport.warnings.isEmpty, "unknown receipt version is reported")
    }

    static func unsafeEntries(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let active = try makeLetter(repo)
        let activeBytes = try Data(contentsOf: repo.fileURL(for: active.id))
        let linkedID = UUID()
        let linked = repo.fileURL(for: linkedID, inTrash: true)
        try fm.createSymbolicLink(at: linked, withDestinationURL: repo.fileURL(for: active.id))
        try writeReceipt(repo, linkedID, at: now.addingTimeInterval(-duration))
        let directoryID = UUID()
        let directory = repo.fileURL(for: directoryID, inTrash: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("keep nested data".utf8).write(to: directory.appendingPathComponent("keep.txt"))
        try writeReceipt(repo, directoryID, at: now.addingTimeInterval(-duration))
        let mismatch = UUID()
        let mismatchFile = repo.fileURL(for: mismatch, inTrash: true)
        try activeBytes.write(to: mismatchFile)
        try writeReceipt(repo, mismatch, at: now.addingTimeInterval(-duration))
        let unknown = repo.trashURL.appendingPathComponent("notes.json")
        try Data("unknown document".utf8).write(to: unknown)
        let report = try repo.cleanupRecentlyDeleted(now: now)
        try check(report.removedIDs.isEmpty, "unknown and unsafe entries are not removed")
        try check(!report.warnings.isEmpty, "unsafe entries are reported")
        try check(try Data(contentsOf: repo.fileURL(for: active.id)) == activeBytes, "symlink target is untouched")
        try check(try fm.destinationOfSymbolicLink(atPath: linked.path) == repo.fileURL(for: active.id).path, "symlink remains intact")
        try check(try String(contentsOf: directory.appendingPathComponent("keep.txt")) == "keep nested data", "directory contents are untouched")
        try check(try Data(contentsOf: mismatchFile) == activeBytes, "mismatched identity is untouched")
        try check(try String(contentsOf: unknown) == "unknown document", "unknown file is untouched")

        let linkedReceiptLetter = try makeLetter(repo, text: "Linked receipt")
        try repo.moveToTrash(linkedReceiptLetter.id, at: now.addingTimeInterval(-duration))
        let receiptLink = receipt(repo, linkedReceiptLetter.id)
        try fm.removeItem(at: receiptLink)
        try fm.createSymbolicLink(at: receiptLink, withDestinationURL: repo.fileURL(for: active.id))
        _ = try repo.cleanupRecentlyDeleted(now: now)
        try check(exists(repo.fileURL(for: linkedReceiptLetter.id, inTrash: true)), "linked receipt cannot authorize deletion")
        try check(try Data(contentsOf: repo.fileURL(for: active.id)) == activeBytes, "linked receipt target cannot be rewritten")

        let unidentified = try makeLetter(repo, text: "Unidentifiable pair")
        try repo.moveToTrash(unidentified.id, at: now.addingTimeInterval(-duration))
        let unidentifiedFile = repo.fileURL(for: unidentified.id, inTrash: true)
        try Data("damaged primary".utf8).write(to: unidentifiedFile)
        try Data("damaged backup".utf8).write(to: unidentifiedFile.appendingPathExtension("bak"))
        _ = try repo.cleanupRecentlyDeleted(now: now)
        try check(try String(contentsOf: unidentifiedFile) == "damaged primary", "unidentifiable primary is retained for recovery")
        try check(try String(contentsOf: unidentifiedFile.appendingPathExtension("bak")) == "damaged backup", "unidentifiable backup is retained for recovery")

        let linkRoot = root.appendingPathComponent("Linked trash library")
        let linkedRepo = try PageRepository(rootURL: linkRoot)
        let protected = try makeLetter(linkedRepo)
        try fm.removeItem(at: linkedRepo.trashURL)
        try fm.createSymbolicLink(at: linkedRepo.trashURL, withDestinationURL: linkedRepo.pagesURL)
        try rejects("a linked trash directory cannot target active letters") { _ = try linkedRepo.cleanupRecentlyDeleted(now: now) }
        try check(exists(linkedRepo.fileURL(for: protected.id)), "active letter survives linked trash folder")
    }

    static func failedRemovalAndRetry(_ root: URL) throws {
        let failing = FailingRemoval()
        let repo = try PageRepository(rootURL: root, fileManager: failing)
        let blocked = try makeLetter(repo)
        let other = try makeLetter(repo, text: "Independent expired letter")
        try repo.moveToTrash(blocked.id, at: now)
        try repo.moveToTrash(other.id, at: now)
        failing.blocked = repo.fileURL(for: blocked.id, inTrash: true)
        let report = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(report.removedIDs.contains(other.id), "one failed purge does not block unrelated expired letters")
        try check(!report.removedIDs.contains(blocked.id), "failed purge is not reported as successful")
        try check(!report.warnings.isEmpty, "removal failure is reported")
        try check(exists(receipt(repo, blocked.id)), "failed removal retains original date for retry")
        try check(exists(repo.fileURL(for: blocked.id, inTrash: true)), "failed primary removal retains letter")
        failing.blocked = nil
        try check(try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration + 1)).removedIDs.contains(blocked.id),
                  "next cleanup retries failed removal without another grace period")

        let orphan = try makeLetter(repo, text: "Interrupted after primary removal")
        try repo.moveToTrash(orphan.id, at: now)
        let orphanFile = repo.fileURL(for: orphan.id, inTrash: true)
        try fm.removeItem(at: orphanFile)
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(!exists(orphanFile.appendingPathExtension("bak")), "retry cleans matching backup after interrupted primary removal")
        try check(!exists(receipt(repo, orphan.id)), "retry completes orphan receipt cleanup")

        let blockedBackup = try makeLetter(repo, text: "Backup removal failure")
        try repo.moveToTrash(blockedBackup.id, at: now)
        let blockedBackupFile = repo.fileURL(for: blockedBackup.id, inTrash: true)
        failing.blocked = blockedBackupFile.appendingPathExtension("bak")
        let backupFailure = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(!backupFailure.removedIDs.contains(blockedBackup.id), "backup failure is not reported as completed deletion")
        try check(exists(blockedBackupFile), "backup failure leaves primary restorable")
        try check(exists(receipt(repo, blockedBackup.id)), "backup failure retains deletion date")
        failing.blocked = nil
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration + 1))
        try check(!exists(blockedBackupFile), "backup failure is retried")

        let metadataFailure = try makeLetter(repo, text: "Receipt removal failure")
        try repo.moveToTrash(metadataFailure.id, at: now)
        failing.blocked = receipt(repo, metadataFailure.id)
        let receiptFailure = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(receiptFailure.removedIDs.contains(metadataFailure.id), "completed data removal is reported despite metadata cleanup failure")
        try check(!receiptFailure.warnings.isEmpty, "receipt cleanup failure is reported")
        try check(exists(receipt(repo, metadataFailure.id)), "receipt remains available for retry")
        failing.blocked = nil
        let finalRetry = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration + 1))
        try check(!exists(receipt(repo, metadataFailure.id)), "metadata-only retry finishes cleanup")
        try check(finalRetry.removedIDs.isEmpty, "metadata-only retry does not report another letter deletion")

        let damagedPrimary = try makeLetter(repo, text: "Readable backup identifies damaged primary")
        try repo.moveToTrash(damagedPrimary.id, at: now)
        let damagedFile = repo.fileURL(for: damagedPrimary.id, inTrash: true)
        try Data("damaged current file".utf8).write(to: damagedFile)
        failing.blocked = damagedFile
        let damagedFailure = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(!damagedFailure.removedIDs.contains(damagedPrimary.id), "failed damaged-primary purge is not reported as complete")
        try check(exists(damagedFile.appendingPathExtension("bak")), "failed damaged-primary removal keeps the identifying valid backup")
        try check(exists(receipt(repo, damagedPrimary.id)), "damaged-primary failure retains original deadline")
        failing.blocked = nil
        let damagedRetry = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration + 1))
        try check(damagedRetry.removedIDs.contains(damagedPrimary.id), "damaged-primary cleanup can retry without losing identity")
        try check(!exists(damagedFile.appendingPathExtension("bak")), "successful damaged-primary retry removes matching backup")

        let delayedBackup = try makeLetter(repo, text: "Backup fails after damaged primary removal")
        try repo.moveToTrash(delayedBackup.id, at: now)
        let delayedFile = repo.fileURL(for: delayedBackup.id, inTrash: true)
        try Data("damaged current file".utf8).write(to: delayedFile)
        failing.blocked = delayedFile.appendingPathExtension("bak")
        let delayedReport = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(delayedReport.removedIDs.contains(delayedBackup.id), "primary removal is reported when later backup removal fails")
        try check(!exists(delayedFile), "damaged primary was removed before readable backup")
        try check(exists(delayedFile.appendingPathExtension("bak")), "failed backup removal preserves identifiable retry data")
        try check(exists(receipt(repo, delayedBackup.id)), "failed backup removal preserves deadline after primary removal")
        failing.blocked = nil
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration + 1))
        try check(!exists(delayedFile.appendingPathExtension("bak")) && !exists(receipt(repo, delayedBackup.id)),
                  "backup-only retry completes after damaged primary removal")
    }

    static func failedTimestamp(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let letter = try makeLetter(repo)
        let bytes = try Data(contentsOf: repo.fileURL(for: letter.id))
        try fm.createDirectory(at: receipt(repo, letter.id), withIntermediateDirectories: false)
        try rejects("timestamp failure must prevent delete") { try repo.moveToTrash(letter.id, at: now) }
        try check(try Data(contentsOf: repo.fileURL(for: letter.id)) == bytes, "timestamp failure keeps active letter")
        try check(!exists(repo.fileURL(for: letter.id, inTrash: true)), "timestamp failure does not partially move primary")

        let failedMoveRepo = try PageRepository(rootURL: root.appendingPathComponent("Move failure"), fileManager: FailingMove())
        let failedMove = try makeLetter(failedMoveRepo)
        let before = try Data(contentsOf: failedMoveRepo.fileURL(for: failedMove.id))
        try rejects("failed primary move does not report successful delete") { try failedMoveRepo.moveToTrash(failedMove.id, at: now) }
        _ = try failedMoveRepo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(try Data(contentsOf: failedMoveRepo.fileURL(for: failedMove.id)) == before, "stale receipt from failed move cannot remove active letter")
        try check(exists(failedMoveRepo.fileURL(for: failedMove.id).appendingPathExtension("bak")), "failed-move receipt cannot remove active backup")
    }

    static func revisionsAndRecovery(_ root: URL) throws {
        let failure = StorageFailure()
        let repo = try PageRepository(rootURL: root, fileManager: failure)
        var stale = try makeLetter(repo)
        let path = repo.fileURL(for: stale.id)
        let other = try PageRepository(rootURL: root)
        var external = try other.load().pages[0]
        external.text = "Restored externally"
        try other.save(external)
        stale.text = "Pending local edits"
        let primaryBytes = try Data(contentsOf: path)
        let backup = path.appendingPathExtension("bak")
        let backupBytes = try Data(contentsOf: backup)
        for _ in 0..<2 { try rejects("stale saves reject the cached edit") { try repo.save(stale) } }
        try check(try Data(contentsOf: path) == primaryBytes, "external primary survives all retries")
        try check(try Data(contentsOf: backup) == backupBytes, "conflict does not rotate the backup")
        let relocated = try repo.copyLibrary(to: root.deletingLastPathComponent().appendingPathComponent("Revision copy"))
        try rejects("relocation retains the user's observed revision") { try relocated.save(stale) }

        failure.unreadable = path
        var fallback = try repo.load().pages[0]
        try check(fallback.text != external.text, "temporarily unreadable primary offers the earlier backup")
        failure.unreadable = nil
        fallback.text += "edited"
        try rejects("regained read permission must not overwrite a newer saved revision") { try repo.save(fallback) }
        try check(try Data(contentsOf: path) == primaryBytes, "newer primary remains after transient read failure")

        let damaged = Data("damaged before saving".utf8)
        try damaged.write(to: path)
        var recovered = try repo.load().pages[0]
        recovered.text += " recover"
        failure.failInstallationOf = path
        for _ in 0..<3 {
            try rejects("an interrupted save retains pending writing") { try repo.save(recovered) }
        }
        try check(try Data(contentsOf: path) == damaged, "failed saves preserve the original damaged primary")
        failure.failInstallationOf = nil
        try repo.save(recovered)
        let recovery = root.appendingPathComponent("Recovery")
        let copies = try fm.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        try check(copies.count == 1, "recovery saves deduplicate the same damaged bytes")
        try check(try Data(contentsOf: copies[0]) == damaged, "recovery retains the exact damaged bytes")
        try fm.removeItem(at: repo.trashURL)
        recovered.text += " after trash was removed"
        try repo.save(recovered)
        try check(try repo.load().pages.first?.text == recovered.text, "missing trash alone cannot prevent saving active writing")
        try check(exists(repo.trashURL), "saving repairs a missing trash folder in a writable library")
    }

    static func pairedTransfers(_ root: URL) throws {
        let failure = StorageFailure()
        let repo = try PageRepository(rootURL: root, fileManager: failure)
        let page = try makeLetter(repo)
        let active = repo.fileURL(for: page.id)
        let trash = repo.fileURL(for: page.id, inTrash: true)
        let previous = try Data(contentsOf: active.appendingPathExtension("bak"))
        failure.blockedMove = active.appendingPathExtension("bak")
        try rejects("backup move failure aborts deletion") { try repo.moveToTrash(page.id, at: now) }
        try check(exists(active) && !exists(trash), "failed deletion leaves the primary active")
        try check(exists(active.appendingPathExtension("bak")), "failed deletion retains the active backup")
        failure.blockedMove = nil
        try repo.moveToTrash(page.id, at: now)
        try Data("damaged deleted current".utf8).write(to: trash)
        let backup = trash.appendingPathExtension("bak")
        failure.blockedMove = backup
        try rejects("failed restore preserves the recoverable letter for another attempt") { try repo.restore(page.id) }
        try check(!exists(active) && exists(trash) && exists(backup), "failed restore keeps the complete pair in trash")
        try check(exists(receipt(repo, page.id)), "failed restore keeps the deadline")
        failure.blockedMove = nil
        let restored = try repo.restore(page.id)
        try check(try Data(contentsOf: active) == previous, "restore publishes a readable primary from its good backup")
        try check(restored.id == page.id && !exists(backup), "restore returns the readable letter")
        try fm.removeItem(at: active)
        try check(try repo.load().pages.first?.id == page.id, "active backup-only letter can be opened")
        try repo.moveToTrash(page.id, at: now)
        try fm.removeItem(at: trash)
        try check(try repo.load(inTrash: true).pages.first?.id == page.id, "deleted backup-only letter can be opened")
        try repo.restore(page.id)
        try check(try Data(contentsOf: active) == previous, "deleted backup-only letter restores normally")
    }

    static func interruptedTransfers(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let letter = try makeLetter(repo)
        let active = repo.fileURL(for: letter.id)
        let trash = repo.fileURL(for: letter.id, inTrash: true)
        let marker = repo.trashURL.appendingPathComponent(letter.id.uuidString + ".transfer")
        try writeReceipt(repo, letter.id, at: now)
        try Data("trash-v1".utf8).write(to: marker)
        try fm.moveItem(at: active.appendingPathExtension("bak"), to: trash.appendingPathExtension("bak"))
        let reopened = try PageRepository(rootURL: root)
        _ = try reopened.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(exists(active.appendingPathExtension("bak")) && !exists(marker), "cleanup rolls back an interrupted deletion before the deadline can purge the backup")
        try reopened.moveToTrash(letter.id, at: now)
        try Data("restore-v1".utf8).write(to: marker)
        try fm.moveItem(at: trash.appendingPathExtension("bak"), to: active.appendingPathExtension("bak"))
        try check(try reopened.load().pages.isEmpty, "an interrupted restore never exposes a partly moved earlier version as an active letter")
        try check(exists(trash.appendingPathExtension("bak")) && !exists(marker), "reopening rolls back the incomplete restore")
    }

    static func legacySplits(_ root: URL) throws {
        let repo = try PageRepository(rootURL: root)
        let letter = try makeLetter(repo)
        let active = repo.fileURL(for: letter.id)
        let backup = active.appendingPathExtension("bak")
        let trash = repo.fileURL(for: letter.id, inTrash: true)
        let deletedBackup = trash.appendingPathExtension("bak")
        try repo.moveToTrash(letter.id, at: now)
        try fm.moveItem(at: deletedBackup, to: backup)
        try check(try repo.load().pages.isEmpty, "legacy deletion does not resurrect its stranded active backup")
        try check(!exists(backup) && exists(deletedBackup), "a matching older backup rejoins its deleted letter")
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(!exists(deletedBackup) && !exists(trash), "legacy deleted pair expires together")

        let damaged = try makeLetter(repo)
        let activeDamaged = repo.fileURL(for: damaged.id)
        let trashedDamaged = repo.fileURL(for: damaged.id, inTrash: true)
        try repo.moveToTrash(damaged.id, at: now)
        try Data("broken".utf8).write(to: trashedDamaged)
        try fm.moveItem(at: trashedDamaged, to: activeDamaged)
        _ = try repo.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration))
        try check(try repo.load().pages.first?.id == damaged.id, "expiry protects the only readable copy left by an old failed restore")
        try check(exists(activeDamaged.appendingPathExtension("bak")), "recovered backup belongs to the active library")
    }

    static func copiedLibrary(_ root: URL) throws {
        let original = try PageRepository(rootURL: root.appendingPathComponent("Original"))
        let letter = try makeLetter(original)
        try original.moveToTrash(letter.id, at: now)
        let copied = try LibraryLocation.copyLibrary(from: original.rootURL, to: root.appendingPathComponent("Custom"))
        try check(try Data(contentsOf: receipt(copied, letter.id)) == Data(contentsOf: receipt(original, letter.id)),
                  "custom-location copy preserves deletion date")
        try check(try copied.cleanupRecentlyDeleted(now: now.addingTimeInterval(duration)).removedIDs == [letter.id],
                  "custom location uses original expiry rather than resetting it")
        try check(exists(original.fileURL(for: letter.id, inTrash: true)), "cleanup affects only the current repository")
        try check(exists(receipt(original, letter.id)), "original safety copy remains intact")
    }
}
