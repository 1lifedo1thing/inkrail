import XCTest
@testable import InkrailCore

private final class TrashRemovalFailure: FileManager, @unchecked Sendable {
    var blocked: URL?
    override func removeItem(at url: URL) throws {
        if url == blocked { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}

final class TrashRetentionTests: XCTestCase {
    private var root: URL!
    private var repository: PageRepository!
    private let deletedAt = Date(timeIntervalSince1970: 1_800_000_000.375)
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Inkrail-retention-tests-\(UUID())")
        repository = try PageRepository(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func receipt(_ id: UUID) -> URL {
        repository.trashURL.appendingPathComponent(id.uuidString + ".trashinfo")
    }

    func testExpiresAtThirtyDaysFromDeletionIncludingFractionalSeconds() throws {
        let letter = Page(createdAt: Date(timeIntervalSince1970: 1), text: "Old writing")
        try repository.save(letter)
        try repository.moveToTrash(letter.id, at: deletedAt)
        XCTAssertTrue(try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention - 0.001)).removedIDs.isEmpty)
        let reopened = try PageRepository(rootURL: root)
        XCTAssertEqual(try reopened.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention)).removedIDs, [letter.id])
        XCTAssertTrue(try reopened.load(inTrash: true).pages.isEmpty)
    }

    func testLiteralLegacyLetterReceivesFullGracePeriodWithoutBeingRewritten() throws {
        let id = UUID(uuidString: "61C185EF-68BB-45BB-99DB-81DE5C7AA0FE")!
        let bytes = Data("""
        {"id":"61C185EF-68BB-45BB-99DB-81DE5C7AA0FE","createdAt":"2001-01-01T00:00:00Z","modifiedAt":"2001-01-02T00:00:00Z","text":"Legacy deleted letter"}
        """.utf8)
        let url = repository.fileURL(for: id, inTrash: true)
        try bytes.write(to: url)
        XCTAssertTrue(try repository.cleanupRecentlyDeleted(now: deletedAt).removedIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention - 1)).removedIDs.isEmpty)
        XCTAssertEqual(try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention)).removedIDs, [id])
    }

    func testRestoredLetterSurvivesAndSecondDeletionResetsDeadline() throws {
        let letter = Page(text: "Restore me")
        try repository.save(letter)
        try repository.moveToTrash(letter.id, at: deletedAt)
        try repository.restore(letter.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt(letter.id).path))
        XCTAssertTrue(try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention * 2)).removedIDs.isEmpty)
        let secondDate = deletedAt.addingTimeInterval(retention - 1)
        try repository.moveToTrash(letter.id, at: secondDate)
        XCTAssertTrue(try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention)).removedIDs.isEmpty)
        XCTAssertEqual(try repository.cleanupRecentlyDeleted(now: secondDate.addingTimeInterval(retention)).removedIDs, [letter.id])
    }

    func testTimestampWriteFailureLeavesActiveLetterUntouched() throws {
        let letter = Page(text: "Keep me")
        try repository.save(letter)
        let original = try Data(contentsOf: repository.fileURL(for: letter.id))
        try FileManager.default.createDirectory(at: receipt(letter.id), withIntermediateDirectories: false)
        XCTAssertThrowsError(try repository.moveToTrash(letter.id, at: deletedAt))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: letter.id)), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: letter.id, inTrash: true).path))
    }

    func testCleanupRemovesOnlyDeletedBackupAndKeepsActiveBackups() throws {
        var active = Page(text: "Active previous")
        try repository.save(active)
        active.text = "Active current"
        try repository.save(active)
        var deleted = Page(text: "Deleted previous")
        try repository.save(deleted)
        deleted.text = "Deleted current"
        try repository.save(deleted)
        try repository.moveToTrash(deleted.id, at: deletedAt)
        let activeBackup = repository.fileURL(for: active.id).appendingPathExtension("bak")
        let originalBackup = try Data(contentsOf: activeBackup)
        _ = try repository.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention))
        XCTAssertEqual(try Data(contentsOf: activeBackup), originalBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: deleted.id, inTrash: true).appendingPathExtension("bak").path))
        XCTAssertEqual(try repository.load().pages.map(\.id), [active.id])
    }

    func testDamagedPrimaryFailureKeepsReadableBackupSoCleanupCanRetry() throws {
        let failing = TrashRemovalFailure()
        let repo = try PageRepository(rootURL: root, fileManager: failing)
        var letter = Page(text: "Readable previous version")
        try repo.save(letter)
        letter.text = "Current version"
        try repo.save(letter)
        try repo.moveToTrash(letter.id, at: deletedAt)
        let primary = repo.fileURL(for: letter.id, inTrash: true)
        try Data("damaged primary".utf8).write(to: primary)
        failing.blocked = primary
        let report = try repo.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention))
        XCTAssertTrue(report.removedIDs.isEmpty)
        XCTAssertFalse(report.warnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.appendingPathExtension("bak").path))
        failing.blocked = nil
        XCTAssertEqual(try repo.cleanupRecentlyDeleted(now: deletedAt.addingTimeInterval(retention + 1)).removedIDs, [letter.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.appendingPathExtension("bak").path))
    }
}
