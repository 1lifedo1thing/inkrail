import XCTest
@testable import InkrailCore

final class InkrailCoreTests: XCTestCase {
    var root: URL!
    var repository: PageRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Inkrail-tests-\(UUID())")
        repository = try PageRepository(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testBlankTitle() {
        XCTAssertEqual(Page(text: "\n  \n\t").title, "Untitled letter")
    }
    func testTitleAndUnicodeCounts() {
        let page = Page(text: "\n  नमस्ते दुनिया  \nHello 👨‍👩‍👧‍👦")
        XCTAssertEqual(page.title, "नमस्ते दुनिया")
        XCTAssertEqual(page.wordCount, 4)
        XCTAssertEqual(Page(text: "👨‍👩‍👧‍👦").characterCount, 1)
    }
    func testSafeExportName() {
        let name = Page(text: "../A/B:C?D*").exportName
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.hasPrefix("."))
    }
    func testRoundTrip() throws {
        let page = Page(createdAt: Date(timeIntervalSince1970: 100), text: "नमस्ते\nHello, café 👋")
        try repository.save(page)
        let report = try repository.load()
        XCTAssertEqual(report.pages, [page])
        XCTAssertTrue(report.warnings.isEmpty)
    }
    func testBackupContainsPreviousSave() throws {
        var page = Page(createdAt: Date(timeIntervalSince1970: 100), text: "first")
        try repository.save(page)
        page.text = "second"
        try repository.save(page)
        let backup = try String(contentsOf: repository.fileURL(for: page.id).appendingPathExtension("bak"))
        XCTAssertTrue(backup.contains("first"))
        XCTAssertFalse(backup.contains("second"))
    }
    func testCorruptionRecoversBackupWithoutOverwritingOriginal() throws {
        var page = Page(text: "safe copy")
        try repository.save(page)
        page.text = "new copy"
        try repository.save(page)
        let url = repository.fileURL(for: page.id)
        try Data("{broken".utf8).write(to: url)
        let report = try repository.load()
        XCTAssertEqual(report.pages.first?.text, "safe copy")
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertEqual(try String(contentsOf: url), "{broken")
        try repository.save(report.pages[0])
        XCTAssertEqual(try repository.load().pages.first?.text, "safe copy")
        let recovery = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path)
        XCTAssertEqual(recovery.count, 1)
    }
    func testOneBadFileDoesNotHideGoodLetters() throws {
        let page = Page(text: "readable")
        try repository.save(page)
        let bad = repository.pagesURL.appendingPathComponent("\(UUID()).json")
        try Data("bad".utf8).write(to: bad)
        let report = try repository.load()
        XCTAssertEqual(report.pages.count, 1)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }
    func testMismatchedIdentityIsNotLoaded() throws {
        let page = Page(text: "one")
        try repository.save(page)
        let other = repository.fileURL(for: UUID())
        try FileManager.default.moveItem(at: repository.fileURL(for: page.id), to: other)
        XCTAssertTrue(try repository.load().pages.isEmpty)
        XCTAssertEqual(try repository.load().warnings.count, 1)
    }
    func testTrashAndRestore() throws {
        let page = Page(text: "keep me")
        try repository.save(page)
        try repository.moveToTrash(page.id)
        XCTAssertTrue(try repository.load().pages.isEmpty)
        XCTAssertEqual(try repository.load(inTrash: true).pages.first?.text, "keep me")
        try repository.restore(page.id)
        XCTAssertEqual(try repository.load().pages.first?.text, "keep me")
        XCTAssertTrue(try repository.load(inTrash: true).pages.isEmpty)
    }
    func testRestoreCollisionNeverOverwrites() throws {
        var page = Page(text: "trashed")
        try repository.save(page)
        try repository.moveToTrash(page.id)
        page.text = "active"
        try repository.save(page)
        XCTAssertThrowsError(try repository.restore(page.id))
        XCTAssertEqual(try repository.load().pages.first?.text, "active")
        XCTAssertEqual(try repository.load(inTrash: true).pages.first?.text, "trashed")
    }
    func testNewestFirst() throws {
        let older = Page(createdAt: Date(timeIntervalSince1970: 1), text: "older")
        let newer = Page(createdAt: Date(timeIntervalSince1970: 2), text: "newer")
        try repository.save(older)
        try repository.save(newer)
        XCTAssertEqual(try repository.load().pages.map(\.text), ["newer", "older"])
    }
    func testPreferencesClamp() {
        var p = WritingPreferences()
        p.fontSize = 1000; p.soundVolume = -1; p.inkStrength = .nan; p.lampWarmth = .infinity
        p.clamp()
        XCTAssertEqual(p.fontSize, 28)
        XCTAssertEqual(p.soundVolume, 0)
        XCTAssertEqual(p.inkStrength, 0.88)
        XCTAssertEqual(p.lampWarmth, 0.55)
    }
    func testPreferencesRoundTrip() throws {
        var p = WritingPreferences(); p.capsule = .cobalt; p.nightMode = true
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(WritingPreferences.self, from: data), p)
    }
    func testLargeUnicodeLetterRoundTrip() throws {
        let page = Page(text: String(repeating: "A line. एक पंक्ति. 一行。 🙂\n", count: 5000))
        try repository.save(page)
        XCTAssertEqual(try repository.load().pages.first?.text, page.text)
    }
}
