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
