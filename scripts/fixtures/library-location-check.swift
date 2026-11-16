import Foundation

private final class InterruptedCopy: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private final class CorruptedCopy: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        if dstURL.lastPathComponent == ".metadata" {
            try Data("changed copy".utf8).write(to: dstURL)
        }
    }
}

@main
enum LibraryLocationCheck {
    static var checks = 0
    static let fm = FileManager.default

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { fatalError("FAIL: \(message)") }
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch { checks += 1; return }
        fatalError("FAIL: \(message)")
    }

    static func snapshot(_ root: URL) throws -> [String: Data] {
        var output: [String: Data] = [:]
        func visit(_ folder: URL, prefix: String) throws {
            for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let name = prefix + url.lastPathComponent
                let type = try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                if type == .typeDirectory {
                    output[name + "/"] = Data()
                    try visit(url, prefix: name + "/")
                } else if type == .typeSymbolicLink {
                    output[name] = Data(try fm.destinationOfSymbolicLink(atPath: url.path).utf8)
                } else { output[name] = try Data(contentsOf: url) }
            }
        }
        try visit(root, prefix: "")
        return output
    }

    static func main() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("inkrail-location-" + UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let original = base.appendingPathComponent("Original")
        let repo = try PageRepository(rootURL: original)
        var active = Page(text: "पहला पत्र — First letter")
        try repo.save(active)
        active.text += "\nCurrent text"
        try repo.save(active)
        var deleted = Page(text: "Deleted first draft")
        try repo.save(deleted)
        deleted.text = "Deleted final draft"
        try repo.save(deleted)
        try repo.moveToTrash(deleted.id)
        let recovery = original.appendingPathComponent("Recovery/Empty folder")
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        try Data([0, 255, 20, 128]).write(to: recovery.deletingLastPathComponent().appendingPathComponent("preserved.damaged"))
        try Data("hidden library note".utf8).write(to: original.appendingPathComponent(".metadata"))
        let before = try snapshot(original)
        try LibraryLocation.validateExistingLibrary(at: original)
        checks += 1

        // Both a newly created destination and an existing empty selection work.
        for existing in [false, true] {
            let target = base.appendingPathComponent(existing ? "Existing empty" : "New location")
            if existing { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
            let relocated = try LibraryLocation.copyLibrary(from: original, to: target)
            try check(relocated.rootURL.path == target.standardizedFileURL.resolvingSymlinksInPath().path, "returned repository uses new folder")
            try check(try snapshot(target) == before, "complete copy includes hidden, deleted, backups, recovery and empty dirs")
            try check(try snapshot(original) == before, "copy leaves original byte-for-byte unchanged")
            try check(try relocated.load().pages.map(\.id) == [active.id], "active letter reloads")
            try check(try relocated.load(inTrash: true).pages.map(\.id) == [deleted.id], "deleted letter reloads")
            try check(try relocated.load().pages.first?.text == active.text, "Unicode text preserved")
            try relocated.restore(deleted.id)
            try check(try relocated.load(inTrash: true).pages.isEmpty, "restore uses new location")
            try check(fm.fileExists(atPath: relocated.fileURL(for: deleted.id).appendingPathExtension("bak").path), "restored backup preserved")
            try relocated.moveToTrash(active.id)
            try check(try relocated.load(inTrash: true).pages.map(\.id) == [active.id], "delete uses new location")
            var edited = deleted
            edited.text += "\nAt the new desk"
            try relocated.save(edited)
            try check(try relocated.load().pages.first?.text == edited.text, "subsequent autosave uses new location")
            try check(try snapshot(original) == before, "save/delete/restore cannot modify original")
            try check(!(try snapshot(target).keys.contains { $0.contains("inkrail-write-check") }), "write probes cleaned up")
        }

        for target in [original, original.appendingPathComponent("Nested"), base] {
            try rejects("same or nested folders must be rejected") {
                _ = try LibraryLocation.copyLibrary(from: original, to: target)
            }
            try check(try snapshot(original) == before, "overlap rejection leaves source unchanged")
        }

        let sourceLink = base.appendingPathComponent("Source alias")
        try fm.createSymbolicLink(at: sourceLink, withDestinationURL: original)
        let linkedCopy = base.appendingPathComponent("Copied via source alias")
        _ = try LibraryLocation.copyLibrary(from: sourceLink, to: linkedCopy)
        try check(try snapshot(linkedCopy) == before, "legacy root symlink library can relocate")
        let targetLink = base.appendingPathComponent("Target alias")
        try fm.createSymbolicLink(at: targetLink, withDestinationURL: original)
        try rejects("destination alias to original must be rejected") {
            _ = try LibraryLocation.copyLibrary(from: original, to: targetLink)
        }
        let nestedLink = base.appendingPathComponent("Nested alias")
        try fm.createSymbolicLink(at: nestedLink, withDestinationURL: original.appendingPathComponent("Recovery"))
        try rejects("destination alias into original must be rejected") {
            _ = try LibraryLocation.copyLibrary(from: original, to: nestedLink.appendingPathComponent("New"))
        }
        try check(try snapshot(original) == before, "alias guards preserve source")

        let occupied = base.appendingPathComponent("Occupied")
        try fm.createDirectory(at: occupied, withIntermediateDirectories: false)
        try Data("Keep me".utf8).write(to: occupied.appendingPathComponent(".hidden"))
        let occupiedBefore = try snapshot(occupied)
        try rejects("hidden contents must not be overwritten") {
            _ = try LibraryLocation.copyLibrary(from: original, to: occupied)
        }
        try check(try snapshot(occupied) == occupiedBefore, "occupied destination untouched")
        let file = base.appendingPathComponent("A file")
        try Data("Not a directory".utf8).write(to: file)
        try rejects("file destination rejected") { _ = try LibraryLocation.copyLibrary(from: original, to: file) }
        try check(try String(contentsOf: file) == "Not a directory", "file destination preserved")

        let missing = base.appendingPathComponent("Missing disk/Library")
        try rejects("missing source must not initialize empty library") {
            _ = try LibraryLocation.copyLibrary(from: missing, to: base.appendingPathComponent("Missing copy"))
        }
        try rejects("saved custom path must exist at launch") { try LibraryLocation.validateExistingLibrary(at: missing) }
        try check(!fm.fileExists(atPath: missing.path), "missing source not created")
        let malformed = base.appendingPathComponent("Missing trash")
        try fm.createDirectory(at: malformed.appendingPathComponent("Letters"), withIntermediateDirectories: true)
        try rejects("incomplete source rejected") { try LibraryLocation.validateExistingLibrary(at: malformed) }
        try check(!fm.fileExists(atPath: malformed.appendingPathComponent("Recently Deleted").path), "validation does not repair or initialize")
        try rejects("missing destination parent rejected") {
            _ = try LibraryLocation.copyLibrary(from: original, to: missing)
        }
        try check(!fm.fileExists(atPath: missing.deletingLastPathComponent().path), "missing disk hierarchy not created")

        let internalLink = original.appendingPathComponent("Letters/external-link")
        try fm.createSymbolicLink(at: internalLink, withDestinationURL: occupied)
        try rejects("internal symbolic links rejected before copy") {
            _ = try LibraryLocation.copyLibrary(from: original, to: base.appendingPathComponent("Unsafe copy"))
        }
        try check(!fm.fileExists(atPath: base.appendingPathComponent("Unsafe copy").path), "unsupported source not partially copied")
        try check(try snapshot(occupied) == occupiedBefore, "link target untouched")
        try fm.removeItem(at: internalLink)

        let interrupted = base.appendingPathComponent("Interrupted copy")
        try rejects("copy errors must propagate") {
            _ = try LibraryLocation.copyLibrary(from: original, to: interrupted, fileManager: InterruptedCopy())
        }
        try check(!(try fm.contentsOfDirectory(atPath: interrupted.path).isEmpty), "partial destination retained for inspection")
        try check(try snapshot(original) == before, "interrupted copy leaves original intact")
        let corrupted = base.appendingPathComponent("Corrupted copy")
        try rejects("byte verification must reject corruption") {
            _ = try LibraryLocation.copyLibrary(from: original, to: corrupted, fileManager: CorruptedCopy())
        }
        try check(try snapshot(original) == before, "failed verification leaves original intact")
        try check(try String(contentsOf: corrupted.appendingPathComponent(".metadata")) == "changed copy", "failed destination retained")
        print("Passed \(checks) library-location checks using disposable folders.")
    }
}
