import Foundation

struct DictionaryReplacement: Codable, Equatable {
    var word: String = ""
    var replacement: String = ""
}

struct ConfigData: Codable {
    var apiKey: String = ""
    var deepgramApiKey: String = ""
    var customVocabulary: String = ""
    var dictionaryReplacements: [DictionaryReplacement] = []
    var transcriptionModel: String = "gpt-4o-transcribe"
    var cleanupModel: String = "gpt-4o-mini"
    var enableCleanup: Bool = true
    var hideMode: Bool = false

    enum CodingKeys: String, CodingKey {
        case apiKey
        case deepgramApiKey
        case customVocabulary
        case dictionaryReplacements
        case transcriptionModel
        case cleanupModel
        case enableCleanup
        case hideMode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        deepgramApiKey = try c.decodeIfPresent(String.self, forKey: .deepgramApiKey) ?? ""
        customVocabulary = try c.decodeIfPresent(String.self, forKey: .customVocabulary) ?? ""
        dictionaryReplacements = try c.decodeIfPresent([DictionaryReplacement].self, forKey: .dictionaryReplacements) ?? []
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? "gpt-4o-transcribe"
        cleanupModel = try c.decodeIfPresent(String.self, forKey: .cleanupModel) ?? "gpt-4o-mini"
        enableCleanup = try c.decodeIfPresent(Bool.self, forKey: .enableCleanup) ?? true
        hideMode = try c.decodeIfPresent(Bool.self, forKey: .hideMode) ?? false
    }
}

final class Config {
    static let shared = Config()
    private(set) var data: ConfigData

    init(data: ConfigData = ConfigData()) {
        self.data = data
    }

    var apiKey: String { data.apiKey }
    var deepgramApiKey: String { data.deepgramApiKey }
    var customVocabulary: String { data.customVocabulary }
    var dictionaryReplacements: [DictionaryReplacement] { data.dictionaryReplacements }

    private var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    func load() {
        if let bytes = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode(ConfigData.self, from: bytes) {
            self.data = parsed
        }
        if data.apiKey.isEmpty, let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            data.apiKey = env
        }
        if data.deepgramApiKey.isEmpty, let env = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"] {
            data.deepgramApiKey = env
        }
    }

    func save(_ newData: ConfigData) {
        self.data = newData
        if let bytes = try? JSONEncoder().encode(newData) {
            try? bytes.write(to: url, options: .atomic)
        }
    }

    func saveDictionaryReplacements(_ replacements: [DictionaryReplacement]) {
        var newData = data
        newData.dictionaryReplacements = replacements
        save(newData)
    }
}
