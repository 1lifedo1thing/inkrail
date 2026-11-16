import Foundation

public enum LibraryLocationError: LocalizedError {
    case invalidLibrary(String)
    case overlappingLocations
    case destinationNotEmpty
    case unsupportedEntry(String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary(let path):
            return "The library at \(path) is unavailable or is missing its Letters or Recently Deleted folder. Reconnect its disk or choose its original folder."
        case .overlappingLocations:
            return "Choose a different folder outside the current library. A library cannot be copied into itself or into a folder that contains it."
        case .destinationNotEmpty:
            return "Choose an empty folder, or create a new one. Inkrail will not overwrite or merge another folder's contents."
        case .unsupportedEntry(let path):
            return "The library contains a link or unsupported file at \(path). Its original files were left untouched."
        case .verificationFailed(let path):
            return "Inkrail could not verify the copied file at \(path). The current library has not changed."
        }
    }
}

/// Copies a complete library before the caller changes its saved location.
/// This never moves, deletes or rewrites source files, and never merges libraries.
public enum LibraryLocation {
    /// Unlike PageRepository.init, this refuses missing stores instead of creating them.
    /// Use it before opening a previously chosen custom location on the next launch.
    public static func validateExistingLibrary(at root: URL, fileManager: FileManager = .default) throws {
        guard root.isFileURL, isDirectory(root, fileManager: fileManager),
              isDirectory(root.appendingPathComponent("Letters"), fileManager: fileManager),
              isDirectory(root.appendingPathComponent("Recently Deleted"), fileManager: fileManager) else {
            throw LibraryLocationError.invalidLibrary(root.path)
        }
    }

    public static func copyLibrary(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> PageRepository {
        let source = canonicalURL(source, fileManager: fileManager)
        let destination = canonicalURL(destination, fileManager: fileManager)
        try validateExistingLibrary(at: source, fileManager: fileManager)
        guard destination.isFileURL else { throw LibraryLocationError.destinationNotEmpty }
        // Case-insensitive comparison is deliberately conservative on case-sensitive disks.
        let sourceParts = source.pathComponents.map { $0.lowercased() }
        let destinationParts = destination.pathComponents.map { $0.lowercased() }
        guard !sourceParts.starts(with: destinationParts), !destinationParts.starts(with: sourceParts) else {
            throw LibraryLocationError.overlappingLocations
        }
        let originalEntries = try entries(in: source, fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            guard isDirectory(destination, fileManager: fileManager),
                  try fileManager.contentsOfDirectory(atPath: destination.path).isEmpty else {
                throw LibraryLocationError.destinationNotEmpty
            }
        } else {
            // Only create the chosen folder, not an unexpected hierarchy on a missing disk.
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        }

        // copyItem refuses existing paths. An interrupted copy may remain for inspection;
        // never remove destination data on an error or mutate the source to roll back.
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
        let copiedEntries = try entries(in: destination, fileManager: fileManager)
        guard originalEntries == copiedEntries,
              originalEntries == (try entries(in: source, fileManager: fileManager)) else {
            throw LibraryLocationError.verificationFailed(destination.path)
        }
        for entry in originalEntries where !entry.isDirectory {
            let oldFile = source.appendingPathComponent(entry.path)
            let newFile = destination.appendingPathComponent(entry.path)
            guard fileManager.contentsEqual(atPath: oldFile.path, andPath: newFile.path) else {
                throw LibraryLocationError.verificationFailed(newFile.path)
            }
        }
        for folder in [destination, destination.appendingPathComponent("Letters"),
                       destination.appendingPathComponent("Recently Deleted")] {
            try verifyWritable(folder, fileManager: fileManager)
        }
        return try PageRepository(rootURL: destination, fileManager: fileManager)
    }

    private struct Entry: Equatable {
        let path: String
        let isDirectory: Bool
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static func canonicalURL(_ url: URL, fileManager: FileManager) -> URL {
        guard url.isFileURL else { return url }
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        // Foundation does not reliably resolve a symlink in a parent when the leaf
        // does not exist yet. Resolve the existing ancestor first, then add the leaf.
        while !fileManager.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() { resolved.appendPathComponent(component) }
        return resolved.standardizedFileURL
    }

    private static func entries(in root: URL, fileManager: FileManager) throws -> [Entry] {
        var result: [Entry] = []
        func visit(_ folder: URL, relativePath: String) throws {
            for url in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let path = relativePath.isEmpty ? url.lastPathComponent : relativePath + "/" + url.lastPathComponent
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let type = attributes[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeDirectory else {
                    throw LibraryLocationError.unsupportedEntry(url.path)
                }
                let directory = type == .typeDirectory
                result.append(Entry(path: path, isDirectory: directory))
                if directory { try visit(url, relativePath: path) }
            }
        }
        try visit(root, relativePath: "")
        return result.sorted { $0.path < $1.path }
    }

    private static func verifyWritable(_ folder: URL, fileManager: FileManager) throws {
        let probe = folder.appendingPathComponent(".inkrail-write-check-" + UUID().uuidString)
        try Data("Inkrail location check".utf8).write(to: probe, options: .withoutOverwriting)
        defer { try? fileManager.removeItem(at: probe) }
        let replacement = Data("Inkrail atomic save check".utf8)
        try replacement.write(to: probe, options: .atomic)
        guard try Data(contentsOf: probe) == replacement else {
            throw LibraryLocationError.verificationFailed(probe.path)
        }
        try fileManager.removeItem(at: probe)
    }
}
