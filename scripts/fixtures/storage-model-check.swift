import AppKit
import InkrailCore

// AppModel's injected preferences exercise its real persistence keys without
// touching UserDefaults.standard or writing a test suite to the user's Library.
final class MemoryDefaults: UserDefaults {
    var values: [String: Any]
    init(values: [String: Any] = [:]) {
        self.values = values
        super.init(suiteName: "Inkrail.StorageModelCheck.\(UUID().uuidString)")!
    }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@MainActor final class SoundEngine {
    static let shared = SoundEngine()
    func stopAll() {}
}

@MainActor enum TextExport {
    static func save(_ page: Page, markdown: Bool) throws {
        fatalError("The storage fixture must not open an export panel")
    }
}

@MainActor final class StorageFixtureClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@main @MainActor struct StorageModelCheck {
    static var checks = 0
    static let fm = FileManager.default
    static let locationKey = "letter-storage-folder-v1"

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        let temporary = fm.temporaryDirectory.appendingPathComponent("Inkrail-storage-model-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        try formattingSurvivesRestart(in: temporary)
        try privateTitles(in: temporary)
        checkLetterPreviews()
        checkMarkdownExport()
        checkInlineMarkdownShortcuts()
        try checkMarkdownImport(in: temporary)
        try successfulCopyAndRestart(in: temporary)
        try missingLocation(in: temporary)
        try failedPendingSave(in: temporary)
        try retentionStartupAndLegacyGrace(in: temporary)
        try retentionMaintenanceSchedule(in: temporary)
        try retentionRestoreAndDeleteAgain(in: temporary)
        try retentionOpeningAndExpiredRestore(in: temporary)
        try retentionAfterLocationChange(in: temporary)
        print("PASS: \(checks)/\(checks) production AppModel storage checks. Disposable libraries and in-memory defaults only; no picker or live app interaction.")
    }

    static func checkLetterPreviews() {
        let longSentence = String(repeating: "a long letter ", count: 15) + "arrived."
        let samples: [(String, String)] = [
            ("Dear Mum,\r\nWe're home.\n\nit snowed. More later.", "Dear Mum, We're home. it snowed..."),
            ("Dr. Lee paid 3.14. “Really?” She nodded.", "Dr. Lee paid 3.14. “Really?”..."),
            ("春天来了。你听见了吗？第三句。", "春天来了。你听见了吗？..."),
            (longSentence + " Another followed. More later.", longSentence + " Another followed..."),
            ("Just one.", "Just one..."),
            ("One. Still writing", "One. Still writing..."),
            ("An unfinished thought", "An unfinished thought..."),
            (String(repeating: "x", count: 200), String(repeating: "x", count: 140) + "..."),
            (" \n\t ", "")
        ]
        for (body, expected) in samples {
            check(Page(text: body).preview == expected, "letter preview should read \(expected.debugDescription)")
        }
    }

    static func checkMarkdownExport() {
        let before = "# Journal\n\n[home](notes.md)\npre"
        let selected = "🖋_x*<&>  \r\n \r\nnext"
        let after = "fix and `raw_code`"
        let text = before + selected + after
        check(Page(text: text).markdownText.utf8.elementsEqual(text.utf8),
              "unformatted Markdown exports the exact handwritten source")
        let run = TextFormatRun(location: before.utf16.count, length: selected.utf16.count,
                                emphasis: [.bold, .italic, .underline])
        let page = Page(text: text, formatting: [run])
        let firstLine = "<strong><em><u>🖋\\_x\\*&lt;&amp;&gt;</u></em></strong>"
        let secondLine = "<strong><em><u>next</u></em></strong>"
        let expected = before + firstLine + "  \r\n \r\n" + secondLine + after
        check(page.markdownText.utf8.elementsEqual(expected.utf8),
              "Markdown retains intraword emphasis, Unicode, original paragraphs and literal styled punctuation")
        check(page.text.utf8.elementsEqual(text.utf8), "the plain-text export source keeps the original words")

        let simpleStyles: [(TextEmphasis, String)] = [(.bold, "**word**"), (.italic, "*word*"),
                                                       (.strikethrough, "~~word~~"), (.code, "`word`")]
        for (emphasis, expected) in simpleStyles {
            let styled = Page(text: "word", formatting: [TextFormatRun(location: 0, length: 4, emphasis: emphasis)])
            check(styled.markdownText == expected, "straightforward emphasis exports conventional Markdown markers")
        }
        let code = Page(text: "`x` &", formatting: [TextFormatRun(location: 0, length: 5, emphasis: .code)])
        check(code.markdownText == "`` `x` & ``", "inline code with literal backticks round trips with a longer fence")
        let blocks = "# title\n> - item\n```\n*literal*\n```"
        let styledBlocks = Page(text: blocks, formatting: [TextFormatRun(location: 0, length: blocks.utf16.count, emphasis: .bold)])
        check(styledBlocks.markdownText == "# **title**\n> - **item**\n```\n*literal*\n```",
              "whole-line styling preserves heading, nested quote/list markers and fenced examples")
    }

    static func checkInlineMarkdownShortcuts() {
        let prefix = "Earlier paragraph\n🖋 "
        let examples: [(String, TextEmphasis)] = [("*", .italic), ("_", .italic), ("**", .bold), ("__", .bold),
                                                 ("***", [.bold, .italic]), ("___", [.bold, .italic]),
                                                 ("~~", .strikethrough), ("`", .code)]
        for (marker, emphasis) in examples {
            let content = "नमस्ते🖋"
            let keys = marker + content + marker
            var text = prefix
            var matches: [MarkdownShortcut] = []
            for key in keys {
                text.append(key)
                if let match = MarkdownShortcut.match(in: text as NSString, at: text.utf16.count) { matches.append(match) }
            }
            check(matches.count == 1 && matches[0].emphasis == emphasis
                  && matches[0].range == NSRange(location: prefix.utf16.count, length: keys.utf16.count)
                  && matches[0].contentRange == NSRange(location: prefix.utf16.count + marker.count, length: content.utf16.count),
                  "\(marker) finishes once on the final closing keystroke with UTF-16 ranges")
        }
        for literal in [#"\*escaped*"#, #"**open\**"#, "snake_case_more_", "_ leading_",
                        "*trailing *", "*first\nsecond*", "`**literal**", "half***", "old **done** then**"] {
            check(MarkdownShortcut.match(in: literal as NSString, at: literal.utf16.count) == nil,
                  "literal input stays intact: \(literal.debugDescription)")
        }
        let inside = "use `a * b` here"
        let insertion = (inside as NSString).range(of: "` here").location + 1
        let match = MarkdownShortcut.match(in: inside as NSString, at: insertion)
        check(match?.emphasis == .code && match?.contentRange == NSRange(location: 5, length: 5),
              "inline code can be completed in the middle of a letter")
    }

    static func checkMarkdownImport(in temporary: URL) throws {
        let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: temporary.appendingPathComponent("Imports"),
                             schedulesAutosave: false)
        let example = "\n> - [**label**](https://example.com/a_(b))\r\n\n~~~swift\n*literal*\n~~~\n    **example**\n\\*escaped*"
        let source = "# **Heading**\nBold **one *two* end** and `a**b`." + example
        let file = temporary.appendingPathComponent("Handwritten.MD")
        try source.write(to: file, atomically: true, encoding: .utf8)
        try model.importText(from: file)
        let expected = "# Heading\nBold one two end and a**b." + example
        check(model.currentText == expected, "Markdown import retains block prefixes, links, fences, escapes and line endings")
        let ascii = expected as NSString
        let runs = [("Heading", TextEmphasis.bold), ("one ", .bold), ("two", [.bold, .italic]), (" end", .bold), ("a**b", .code)]
        check(model.selectedPage?.formatting == runs.map { word, style in
            let range = ascii.range(of: word)
            return TextFormatRun(location: range.location, length: range.length, emphasis: style)
        }, "nested Markdown import restores independent editable spans")

        let plain = temporary.appendingPathComponent("Handwritten.txt")
        try source.write(to: plain, atomically: true, encoding: .utf8)
        try model.importText(from: plain)
        check(model.currentText.utf8.elementsEqual(source.utf8) && model.selectedPage?.formatting == [],
              "plain-text import retains typed markers verbatim")

        let word = "🖋_x*<&>"
        let literal = "`x` &"
        let richText = "pre" + word + "fix " + literal
        let original = Page(text: richText, formatting: [
            TextFormatRun(location: 3, length: word.utf16.count, emphasis: [.bold, .italic, .underline]),
            TextFormatRun(location: richText.utf16.count - literal.utf16.count, length: literal.utf16.count, emphasis: .code)
        ])
        let imported = Page(markdown: original.markdownText)
        check(imported.text == original.text && imported.formatting == original.formatting,
              "exported intraword underline, combined emphasis, escaped punctuation and backticks round trip")
    }

    static func formattingSurvivesRestart(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Formatted letters")
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults, defaultRootURL: root, schedulesAutosave: false)
        let words = "A🖋 letter"
        model.createPage(text: words)
        let repository = try PageRepository(rootURL: root)
        let file = repository.fileURL(for: model.selectedID!)
        let plainData = try Data(contentsOf: file)
        var json = try JSONSerialization.jsonObject(with: plainData) as! [String: Any]
        check(json["formatting"] == nil, "plain letters retain the original JSON fields")
        let legacy = try repository.load().pages.first { $0.id == model.selectedID }
        check(legacy?.text == words && legacy?.formatting == [], "legacy letters load without emphasis")

        let pen = TextFormatRun(location: 1, length: 2, emphasis: [.bold, .italic])
        let word = TextFormatRun(location: 4, length: 6, emphasis: .underline)
        model.edit(words, formatting: [pen, word])
        check(model.isDirty && model.flush(), "an emphasis-only edit is saved")
        let reopened = AppModel(defaults: defaults, defaultRootURL: root, schedulesAutosave: false)
        check(reopened.currentText == words && reopened.selectedPage?.formatting == [pen, word],
              "combined emphasis, UTF-16 ranges and plain words survive a restart")
        reopened.edit(words, formatting: [pen, word])
        check(!reopened.isDirty, "identical words and emphasis retain the saved state")
        reopened.edit(words, formatting: [])
        check(reopened.isDirty && reopened.flush(), "clearing emphasis is saved")
        let cleared = try repository.load().pages.first { $0.id == model.selectedID }
        check(cleared?.formatting == [], "reopening restores cleared emphasis")

        json["formatting"] = [
            ["location": -1, "length": 1, "emphasis": 1],
            ["location": 2, "length": 1, "emphasis": 2],
            ["location": 4, "length": 6, "emphasis": 4],
            ["location": 9, "length": Int.max, "emphasis": 1]
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        let repaired = try repository.load().pages.first { $0.id == model.selectedID }
        check(repaired?.text == words && repaired?.formatting == [word],
              "invalid UTF-16 ranges leave the letter and its valid emphasis readable")
    }

    static func privateTitles(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Private titles")
        let repository = try PageRepository(rootURL: root)
        let id = UUID()
        let letter: [String: Any] = [
            "id": id.uuidString, "createdAt": "2020-01-02T12:00:00Z", "modifiedAt": "2021-03-04T12:00:00Z",
            "text": "Dear Mum,\nHappy birthday."
        ]
        try JSONSerialization.data(withJSONObject: letter).write(to: repository.fileURL(for: id))
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults, defaultRootURL: root, schedulesAutosave: false)
        check(model.selectedPage?.title == "Dear Mum," && model.selectedPage?.privateTitle == nil,
              "letters saved before private titles use their opening line")
        model.edit(model.currentText, formatting: [TextFormatRun(location: 0, length: 4, emphasis: .bold)])
        let original = model.selectedPage!
        model.createPage(text: "Another letter")
        let activeID = model.selectedID
        model.showLibrary = true
        let title = "Mum’s birthday"
        model.rename(id, to: "  \(title)  ")
        check(model.selectedID == activeID && model.showLibrary, "renaming another letter keeps the desk and letter box in place")
        let renamed = model.pages.first { $0.id == id }!
        check(renamed.title == title && renamed.privateTitle == title, "a trimmed private title labels the letter")
        check(renamed.createdAt == original.createdAt && renamed.modifiedAt == original.modifiedAt,
              "renaming preserves the letter's writing dates")
        check(renamed.text == original.text && renamed.formatting == original.formatting &&
              renamed.markdownText == original.markdownText && renamed.exportName == "Dear Mum,",
              "renaming preserves the formatted letter and excludes its private title from exports and their filenames")
        check(model.flush(), "the private title saves")

        let reopened = AppModel(defaults: defaults, defaultRootURL: root, schedulesAutosave: false)
        check(reopened.pages.first { $0.id == id }?.privateTitle == title, "the private title survives relaunch")
        reopened.moveToTrash(id)
        check(reopened.deletedPages().first { $0.id == id }?.title == title, "Recently Deleted shows the private title")
        reopened.restore(id)
        reopened.select(id)
        reopened.edit("A new opening")
        check(reopened.selectedPage?.title == title, "the restored title stays attached when the opening line is edited")
        reopened.rename(id, to: " \t ")
        check(reopened.flush(), "clearing the private title saves")
        let cleared = try repository.load().pages.first { $0.id == id }
        check(cleared?.title == "A new opening" && cleared?.privateTitle == nil,
              "clearing the title restores the current opening line across reloads")
    }

    static func successfulCopyAndRestart(in temporary: URL) throws {
        let oldRoot = temporary.appendingPathComponent("Original")
        let newRoot = temporary.appendingPathComponent("Custom Library")
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults, defaultRootURL: oldRoot, schedulesAutosave: false)
        check(model.storageAvailable, "default library is available")
        check(model.rootURL == oldRoot, "injected default root is used")
        check(defaults.string(forKey: locationKey) == nil, "startup does not invent a custom path")
        check(model.pages.count == 1, "first launch creates welcome letter")
        let id = model.selectedID!
        model.edit("First saved version")
        check(model.flush(), "initial edit saves")
        model.createPage(text: "A deleted letter")
        let deletedID = model.selectedID!
        model.moveToTrash(deletedID)
        check(model.deletedPages().map(\.id).contains(deletedID), "deleted letter is prepared")
        model.select(id)
        model.preferences.fontSize = 23
        model.preferences.soundEnabled = false
        let savedPreferences = defaults.data(forKey: "writing-preferences-v1")
        let recovery = oldRoot.appendingPathComponent("Recovery")
        try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
        let recoveryBytes = Data("preserved damaged bytes".utf8)
        try recoveryBytes.write(to: recovery.appendingPathComponent("original.damaged"))
        model.edit("Latest unsaved writing before the move\nनमस्ते 世界")
        check(model.isDirty, "pending edits exist before relocation")
        let latestText = model.currentText
        check(model.changeStorageLocation(to: newRoot), "relocation succeeds")
        check(model.rootURL.path == newRoot.resolvingSymlinksInPath().path, "current root changes to destination")
        check(defaults.string(forKey: locationKey) == model.rootURL.path, "successful location is persisted")
        check(!model.isDirty, "pending edits were flushed before copy")
        check(model.selectedID == id, "selected letter is unchanged")
        check(model.currentText == latestText, "in-memory writing is preserved")
        check(model.storageMessage?.contains(oldRoot.path) == true, "success identifies retained original")
        check(model.saveState == "Saved on this Mac", "successful move keeps truthful saved status")
        check(defaults.data(forKey: "writing-preferences-v1") == savedPreferences, "appearance preferences remain unchanged")
        let original = try PageRepository(rootURL: oldRoot)
        let copied = try PageRepository(rootURL: newRoot)
        let originalReport = try original.load()
        let copiedReport = try copied.load()
        check(originalReport.pages.first(where: { $0.id == id })?.text == latestText, "original includes final flushed edit")
        check(copiedReport.pages.first(where: { $0.id == id })?.text == latestText, "copy includes final flushed edit")
        check(model.deletedPages().map(\.id).contains(deletedID), "deleted letter survives relocation")
        check(fm.fileExists(atPath: copied.fileURL(for: id).appendingPathExtension("bak").path), "previous valid copy survives relocation")
        let copiedRecovery = try Data(contentsOf: newRoot.appendingPathComponent("Recovery/original.damaged"))
        check(copiedRecovery == recoveryBytes, "recovery bytes survive relocation")

        model.edit("Writing after the move")
        check(model.flush(), "future saves succeed")
        let originalAfterEdit = try original.load()
        let copiedAfterEdit = try copied.load()
        check(originalAfterEdit.pages.first(where: { $0.id == id })?.text == latestText, "old copy receives no future edits")
        check(copiedAfterEdit.pages.first(where: { $0.id == id })?.text == "Writing after the move", "new location receives future edits")
        model.restore(deletedID)
        check(model.pages.contains(where: { $0.id == deletedID }), "restore works after relocation")
        check(!model.deletedPages().contains(where: { $0.id == deletedID }), "restore removes from new trash")
        let originalTrash = try original.load(inTrash: true)
        check(originalTrash.pages.contains(where: { $0.id == deletedID }), "restore does not mutate old copy")
        model.moveToTrash(deletedID)
        check(!model.pages.contains(where: { $0.id == deletedID }), "delete works after relocation")
        check(model.deletedPages().contains(where: { $0.id == deletedID }), "delete uses new trash")

        let restoredDefaults = MemoryDefaults(values: defaults.values)
        let unusedDefault = temporary.appendingPathComponent("Unused restart default")
        let reopened = AppModel(defaults: restoredDefaults, defaultRootURL: unusedDefault, schedulesAutosave: false)
        check(reopened.storageAvailable, "custom library opens on next model launch")
        check(reopened.rootURL.path == model.rootURL.path, "saved custom path wins over default")
        check(reopened.selectedID == id, "selection survives restart")
        check(reopened.currentText == "Writing after the move", "next launch loads custom writing")
        check(reopened.preferences.fontSize == 23 && !reopened.preferences.soundEnabled, "preferences survive restart")
        check(!fm.fileExists(atPath: unusedDefault.path), "restart does not create default library")

        let occupied = temporary.appendingPathComponent("Occupied")
        try fm.createDirectory(at: occupied, withIntermediateDirectories: false)
        let marker = occupied.appendingPathComponent("keep.txt")
        try Data("Keep me".utf8).write(to: marker)
        check(!reopened.changeStorageLocation(to: occupied), "nonempty destination is refused")
        check(reopened.rootURL.path == model.rootURL.path, "failed change retains current root")
        check(restoredDefaults.string(forKey: locationKey) == model.rootURL.path, "failed change retains persisted root")
        let markerBytes = try Data(contentsOf: marker)
        check(markerBytes == Data("Keep me".utf8), "existing destination data is untouched")
        check(reopened.storageMessage?.contains("not changed") == true, "failure is reported")
        reopened.edit("Still writing to custom library")
        check(reopened.flush(), "current repository still saves after refusal")
        let reportAfterRefusal = try copied.load()
        check(reportAfterRefusal.pages.first(where: { $0.id == id })?.text == reopened.currentText, "failed change retains repository")
        check(!reopened.changeStorageLocation(to: reopened.rootURL), "same location is refused")
        check(reopened.storageAvailable, "refusal does not disable healthy storage")
    }

    static func missingLocation(in temporary: URL) throws {
        let missing = temporary.appendingPathComponent("Disconnected disk/Custom library")
        let fallback = temporary.appendingPathComponent("Must not create fallback")
        let defaults = MemoryDefaults(values: [locationKey: missing.path])
        let model = AppModel(defaults: defaults, defaultRootURL: fallback, schedulesAutosave: false)
        check(!model.storageAvailable, "missing custom location reports unavailable")
        check(model.rootURL.path == missing.path, "missing custom path remains selected")
        check(!fm.fileExists(atPath: missing.path), "missing custom path is not recreated")
        check(!fm.fileExists(atPath: fallback.path), "missing custom path does not fall back")
        check(model.errorMessage?.contains(missing.path) == true, "startup error identifies missing path")
        check(defaults.string(forKey: locationKey) == missing.path, "startup failure retains preference")
        model.edit("Unsaved emergency writing")
        check(model.isDirty, "writing while unavailable stays dirty")
        check(!model.flush(), "unavailable storage does not report successful save")
        check(model.currentText == "Unsaved emergency writing", "unsaved text remains in memory")
        let destination = temporary.appendingPathComponent("Unavailable change destination")
        check(!model.changeStorageLocation(to: destination), "unavailable library cannot be silently abandoned")
        check(!fm.fileExists(atPath: destination.path), "unavailable change does not create destination")

        let partial = temporary.appendingPathComponent("Incomplete library")
        try fm.createDirectory(at: partial, withIntermediateDirectories: false)
        try fm.createDirectory(at: partial.appendingPathComponent("Letters"), withIntermediateDirectories: false)
        let partialModel = AppModel(defaults: MemoryDefaults(values: [locationKey: partial.path]),
                                    defaultRootURL: fallback, schedulesAutosave: false)
        check(!partialModel.storageAvailable, "incomplete custom library reports unavailable")
        check(!fm.fileExists(atPath: partial.appendingPathComponent("Recently Deleted").path), "incomplete custom library is not reinitialized")
    }

    static func failedPendingSave(in temporary: URL) throws {
        let source = temporary.appendingPathComponent("Save failure source")
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults, defaultRootURL: source, schedulesAutosave: false)
        let letters = source.appendingPathComponent("Letters")
        let preserved = source.appendingPathComponent("Preserved Letters")
        try fm.moveItem(at: letters, to: preserved)
        try Data("A file blocks the Letters directory".utf8).write(to: letters)
        model.edit("This pending edit must not be lost")
        let destination = temporary.appendingPathComponent("Must not copy after save failure")
        check(!model.changeStorageLocation(to: destination), "failed pending save aborts location change")
        check(model.rootURL == source, "save failure keeps root")
        check(defaults.string(forKey: locationKey) == nil, "save failure does not persist new location")
        check(model.isDirty, "failed edit remains dirty")
        check(model.currentText == "This pending edit must not be lost", "failed edit stays in memory")
        check(model.saveState.contains("Save failed"), "failed edit is not labeled saved")
        check(model.storageMessage?.contains("pending writing could not be saved") == true, "location failure explains pending save")
        check(!fm.fileExists(atPath: destination.path), "save failure aborts before creating destination")
        check(fm.fileExists(atPath: preserved.path), "prior saved letters remain preserved")
    }

    static let retention: TimeInterval = 30 * 24 * 60 * 60

    static func retentionStartupAndLegacyGrace(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Retention startup")
        let repo = try PageRepository(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = StorageFixtureClock(start)
        var active = Page(text: "Active letter remains")
        try repo.save(active)
        active.text = "Current active writing"
        try repo.save(active)
        let activeBytes = try Data(contentsOf: repo.fileURL(for: active.id))
        let activeBackup = repo.fileURL(for: active.id).appendingPathExtension("bak")
        let activeBackupBytes = try Data(contentsOf: activeBackup)
        var expired = Page(text: "Expired previous version")
        try repo.save(expired)
        expired.text = "Expired latest version"
        try repo.save(expired)
        try repo.moveToTrash(expired.id, at: start.addingTimeInterval(-retention))
        let recent = Page(text: "One second remains")
        try repo.save(recent)
        try repo.moveToTrash(recent.id, at: start.addingTimeInterval(-retention + 1))
        let legacy = Page(createdAt: Date(timeIntervalSince1970: 10), text: "Legacy deleted letter")
        try repo.save(legacy)
        try fm.moveItem(at: repo.fileURL(for: legacy.id), to: repo.fileURL(for: legacy.id, inTrash: true))
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)],
                             ofItemAtPath: repo.fileURL(for: legacy.id, inTrash: true).path)
        let legacyBytes = try Data(contentsOf: repo.fileURL(for: legacy.id, inTrash: true))

        let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: root,
                             schedulesAutosave: false, nowProvider: { clock.now })
        check(model.storageAvailable, "retention startup preserves healthy storage")
        check(!fm.fileExists(atPath: repo.fileURL(for: expired.id, inTrash: true).path), "startup removes a letter at exactly 30 days")
        check(!fm.fileExists(atPath: repo.fileURL(for: expired.id, inTrash: true).appendingPathExtension("bak").path), "startup removes the expired deleted letter's backup")
        check(fm.fileExists(atPath: repo.fileURL(for: recent.id, inTrash: true).path), "startup retains a letter before its deadline")
        check(fm.fileExists(atPath: repo.fileURL(for: legacy.id, inTrash: true).path), "legacy letter gets a fresh grace period despite old edit and file dates")
        let retainedLegacyBytes = try Data(contentsOf: repo.fileURL(for: legacy.id, inTrash: true))
        check(retainedLegacyBytes == legacyBytes, "legacy grace period does not rewrite letter content")
        let retainedActive = try Data(contentsOf: repo.fileURL(for: active.id))
        let retainedActiveBackup = try Data(contentsOf: activeBackup)
        check(retainedActive == activeBytes && retainedActiveBackup == activeBackupBytes, "cleanup does not alter active writing or its previous saved copy")
        check(model.pages.map(\.id) == [active.id], "startup loads only the existing active letter")
        clock.now = start.addingTimeInterval(retention - 1)
        model.performTrashMaintenance(force: true)
        check(fm.fileExists(atPath: repo.fileURL(for: legacy.id, inTrash: true).path), "legacy grace lasts the full 30 days")
        clock.now = start.addingTimeInterval(retention)
        model.performTrashMaintenance(force: true)
        check(!fm.fileExists(atPath: repo.fileURL(for: legacy.id, inTrash: true).path), "legacy letter expires after its own 30-day grace period")
    }

    static func retentionMaintenanceSchedule(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Retention maintenance")
        let start = Date(timeIntervalSince1970: 1_810_000_000)
        let clock = StorageFixtureClock(start)
        let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: root,
                             schedulesAutosave: false, nowProvider: { clock.now })
        let deletedID = model.selectedID!
        model.moveToTrash(deletedID)
        let repo = try PageRepository(rootURL: root)
        let deletedFile = repo.fileURL(for: deletedID, inTrash: true)
        check(fm.fileExists(atPath: deletedFile.path), "new deletion starts retained")
        clock.now = start.addingTimeInterval(retention - 600)
        model.performTrashMaintenance(force: true)
        let revisionBeforeExpiry = model.trashRevision
        clock.now = start.addingTimeInterval(retention + 1)
        model.performTrashMaintenance()
        check(fm.fileExists(atPath: deletedFile.path), "periodic maintenance is throttled within an hour")
        check(model.trashRevision == revisionBeforeExpiry, "skipped maintenance does not signal a false deletion")
        clock.now = start.addingTimeInterval(retention + 3000)
        model.performTrashMaintenance()
        check(!fm.fileExists(atPath: deletedFile.path), "next hourly maintenance removes expired writing")
        check(model.trashRevision > revisionBeforeExpiry, "successful cleanup publishes a trash refresh")
        check(model.storageAvailable && model.saveState == "Saved on this Mac", "cleanup leaves active autosave healthy")
    }

    static func retentionRestoreAndDeleteAgain(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Retention restoration")
        let start = Date(timeIntervalSince1970: 1_820_000_000)
        let clock = StorageFixtureClock(start)
        let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: root,
                             schedulesAutosave: false, nowProvider: { clock.now })
        let id = model.selectedID!
        model.edit("Restore this writing")
        check(model.flush(), "restorable writing is saved")
        let savedReport = try PageRepository(rootURL: root).load()
        let originalModifiedAt = savedReport.pages.first(where: { $0.id == id })!.modifiedAt
        model.moveToTrash(id)
        clock.now = start.addingTimeInterval(retention - 1)
        model.restore(id)
        check(model.pages.contains(where: { $0.id == id && $0.text == "Restore this writing" }), "restore works just before the deadline")
        check(model.pages.first(where: { $0.id == id })?.modifiedAt == originalModifiedAt, "restoration does not change the letter's edit date")
        clock.now = start.addingTimeInterval(retention + 1)
        model.performTrashMaintenance(force: true)
        let repo = try PageRepository(rootURL: root)
        check(fm.fileExists(atPath: repo.fileURL(for: id).path), "restored letter survives its previous expiry date")
        model.moveToTrash(id)
        let secondDeletion = clock.now
        clock.now = secondDeletion.addingTimeInterval(retention - 1)
        model.performTrashMaintenance(force: true)
        check(fm.fileExists(atPath: repo.fileURL(for: id, inTrash: true).path), "deleting again starts a new full retention period")
        clock.now = secondDeletion.addingTimeInterval(retention)
        model.performTrashMaintenance(force: true)
        check(!fm.fileExists(atPath: repo.fileURL(for: id, inTrash: true).path), "second deletion expires at its new deadline")
    }

    static func retentionOpeningAndExpiredRestore(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("Retention list and restore")
        let start = Date(timeIntervalSince1970: 1_830_000_000)
        let clock = StorageFixtureClock(start)
        let model = AppModel(defaults: MemoryDefaults(), defaultRootURL: root,
                             schedulesAutosave: false, nowProvider: { clock.now })
        let first = model.selectedID!
        model.moveToTrash(first)
        clock.now = start.addingTimeInterval(retention - 60)
        model.performTrashMaintenance(force: true)
        clock.now = start.addingTimeInterval(retention)
        check(!model.deletedPages().contains(where: { $0.id == first }), "opening Recently Deleted forces cleanup even within the hourly throttle")
        let repo = try PageRepository(rootURL: root)
        check(!fm.fileExists(atPath: repo.fileURL(for: first, inTrash: true).path), "opening Recently Deleted removes the expired file")
        let second = model.selectedID!
        model.moveToTrash(second)
        let secondDeletion = clock.now
        clock.now = secondDeletion.addingTimeInterval(retention - 60)
        model.performTrashMaintenance(force: true)
        let activeIDs = model.pages.map(\.id)
        clock.now = secondDeletion.addingTimeInterval(retention)
        model.restore(second)
        check(model.pages.map(\.id) == activeIDs, "an expired restore cannot bring the letter into active writing")
        check(!fm.fileExists(atPath: repo.fileURL(for: second).path), "expired restore does not recreate an active file")
        check(!fm.fileExists(atPath: repo.fileURL(for: second, inTrash: true).path), "restore action enforces the deletion deadline")
    }

    static func retentionAfterLocationChange(in temporary: URL) throws {
        let originalRoot = temporary.appendingPathComponent("Retention old library")
        let customRoot = temporary.appendingPathComponent("Retention custom library")
        let start = Date(timeIntervalSince1970: 1_840_000_000)
        let clock = StorageFixtureClock(start)
        let defaults = MemoryDefaults()
        let model = AppModel(defaults: defaults, defaultRootURL: originalRoot,
                             schedulesAutosave: false, nowProvider: { clock.now })
        let id = model.selectedID!
        model.moveToTrash(id)
        clock.now = start.addingTimeInterval(retention / 2)
        check(model.changeStorageLocation(to: customRoot), "library with retained letters can change location")
        let original = try PageRepository(rootURL: originalRoot)
        let copied = try PageRepository(rootURL: customRoot)
        check(fm.fileExists(atPath: original.fileURL(for: id, inTrash: true).path), "relocation preserves the old deleted letter")
        check(fm.fileExists(atPath: copied.fileURL(for: id, inTrash: true).path), "relocation copies the retained deleted letter")
        clock.now = start.addingTimeInterval(retention)
        let restoredDefaults = MemoryDefaults(values: defaults.values)
        let unusedDefault = temporary.appendingPathComponent("Retention restart unused")
        let reopened = AppModel(defaults: restoredDefaults, defaultRootURL: unusedDefault,
                                schedulesAutosave: false, nowProvider: { clock.now })
        check(reopened.storageAvailable, "custom location stays available during startup cleanup")
        check(!fm.fileExists(atPath: copied.fileURL(for: id, inTrash: true).path), "custom location preserves the original deletion deadline across copy and restart")
        check(fm.fileExists(atPath: original.fileURL(for: id, inTrash: true).path), "cleanup never revisits the old library safety copy")
        check(!fm.fileExists(atPath: unusedDefault.path), "custom cleanup does not create or touch a fallback library")
    }
}
