import XCTest
@testable import InkrailCore

final class LibraryLocationTests: XCTestCase {
    private var base: URL!
    private var original: PageRepository!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("Inkrail-location-tests-\(UUID())")
        original = try PageRepository(rootURL: base.appendingPathComponent("Original"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testCopiesWholeLibraryAndLeavesOriginalAfterEditing() throws {
        var letter = Page(text: "Previous draft")
        try original.save(letter)
        letter.text = "Current draft"
        try original.save(letter)
        let deleted = Page(text: "Deleted letter")
        try original.save(deleted)
        try original.moveToTrash(deleted.id)
        let recovery = original.rootURL.appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: false)
        let damaged = Data([0, 255, 128])
        try damaged.write(to: recovery.appendingPathComponent("old.damaged"))

        let copied = try LibraryLocation.copyLibrary(from: original.rootURL, to: base.appendingPathComponent("Custom"))
        XCTAssertEqual(try copied.load().pages.first?.text, "Current draft")
        XCTAssertEqual(try copied.load(inTrash: true).pages.first?.id, deleted.id)
        XCTAssertEqual(try Data(contentsOf: copied.fileURL(for: letter.id).appendingPathExtension("bak")),
                       try Data(contentsOf: original.fileURL(for: letter.id).appendingPathExtension("bak")))
        XCTAssertEqual(try Data(contentsOf: copied.rootURL.appendingPathComponent("Recovery/old.damaged")), damaged)
        letter.text = "New location draft"
        try copied.save(letter)
        try copied.restore(deleted.id)
        XCTAssertEqual(try original.load().pages.first?.text, "Current draft")
        XCTAssertEqual(try original.load(inTrash: true).pages.first?.id, deleted.id)
        XCTAssertEqual(try copied.load(inTrash: true).pages.count, 0)
    }

    func testRefusesOccupiedDestinationWithoutOverwriting() throws {
        let target = base.appendingPathComponent("Occupied")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let file = target.appendingPathComponent(".hidden")
        try Data("Keep this".utf8).write(to: file)
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: target))
        XCTAssertEqual(try String(contentsOf: file), "Keep this")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [".hidden"])
    }

    func testRefusesOverlappingAndAliasedLocations() throws {
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: original.rootURL))
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: original.rootURL.appendingPathComponent("Nested")))
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: base))
        let alias = base.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original.rootURL)
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: alias))
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: alias.appendingPathComponent("Not created yet")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.rootURL.appendingPathComponent("Not created yet").path))
    }

    func testMissingCustomLocationIsNeverInitialized() throws {
        let missing = base.appendingPathComponent("Disconnected/Library")
        XCTAssertThrowsError(try LibraryLocation.validateExistingLibrary(at: missing))
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: missing, to: base.appendingPathComponent("Destination")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("Destination").path))
    }

    func testInternalLinksCannotKeepNewLibraryWritingIntoOldFiles() throws {
        let linked = original.pagesURL.appendingPathComponent("linked-folder")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: original.trashURL)
        let target = base.appendingPathComponent("Unsafe destination")
        XCTAssertThrowsError(try LibraryLocation.copyLibrary(from: original.rootURL, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path), original.trashURL.path)
    }
}
