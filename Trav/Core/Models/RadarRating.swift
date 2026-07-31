import Foundation

/// Represents a single axis definition in the multi-dimensional Radar Chart (e.g., Cost, Food, Memorability, Authenticity, Immersion).
struct RadarAxis: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let iconName: String? // SF Symbol or Emoji name
    let minValue: Double
    let maxValue: Double

    init(
        id: String,
        name: String,
        iconName: String? = nil,
        minValue: Double = 1.0,
        maxValue: Double = 10.0
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.minValue = minValue
        self.maxValue = maxValue
    }

    /// Standard 5 distinct default axes for experiences
    static let defaultAxes: [RadarAxis] = [
        RadarAxis(id: "Cost", name: "Cost", iconName: "dollarsign.circle.fill", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Food", name: "Food", iconName: "fork.knife", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Memorability", name: "Memorability", iconName: "sparkles", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Authenticity", name: "Authenticity", iconName: "checkmark.seal.fill", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Niche", name: "Niche", iconName: "globe.americas.fill", minValue: 1.0, maxValue: 10.0)
    ]
}

/// Multi-dimensional Radar Rating Data Model.
/// Supports enabling/disabling individual rating categories (disabled categories collapse to 0.0 and are excluded from overall average calculation).
struct RadarRating: Codable, Equatable, Hashable, Sendable {
    /// Dictionary mapping axis IDs (e.g. "Cost", "Food") to continuous decimal scores (1.0 ... 10.0).
    var scores: [String: Double]

    /// Set of category IDs that have been disabled by the user.
    var disabledCategories: Set<String>

    init(scores: [String: Double] = [:], disabledCategories: Set<String> = []) {
        self.scores = scores
        self.disabledCategories = disabledCategories
    }

    /// Default sample rating with continuous decimal values
    static var defaultRating: RadarRating {
        RadarRating(scores: [
            "Cost": 5.5,
            "Food": 9.0,
            "Memorability": 8.5,
            "Authenticity": 8.2,
            "Niche": 7.8
        ])
    }

    // MARK: - Enable / Disable Category Controls

    /// Returns whether a category is currently active/enabled.
    func isEnabled(_ key: String) -> Bool {
        if disabledCategories.contains(key) { return false }
        if key == "Niche" && disabledCategories.contains("Immersion") { return false }
        return true
    }

    /// Toggles a category between enabled and disabled states.
    mutating func toggleCategory(_ key: String) {
        if disabledCategories.contains(key) {
            disabledCategories.remove(key)
        } else {
            disabledCategories.insert(key)
        }
    }

    /// Explicitly sets the enabled state of a category.
    mutating func setEnabled(_ enabled: Bool, for key: String) {
        if enabled {
            disabledCategories.remove(key)
        } else {
            disabledCategories.insert(key)
        }
    }

    // MARK: - Score Calculations & Accessors

    /// Overall aggregate score calculated across ONLY active (enabled) rating axes (excluding disabled 0.0 ones).
    var overallScore: Double {
        let activeScores = scores.filter { isEnabled($0.key) }
        guard !activeScores.isEmpty else { return 0.0 }
        let sum = activeScores.values.reduce(0.0, +)
        let average = sum / Double(activeScores.count)
        return (average * 10.0).rounded() / 10.0
    }

    /// Returns score for a specific axis ID. If disabled, returns 0.0.
    func score(for key: String, default defaultVal: Double = 5.0) -> Double {
        guard isEnabled(key) else { return 0.0 }
        if let val = scores[key] { return val }
        if key == "Niche", let legacyVal = scores["Immersion"] { return legacyVal }
        return defaultVal
    }

    /// Sets score for a specific axis ID, clamping within [minValue, maxValue]. Automatically enables category if score is set.
    mutating func setScore(_ value: Double, for key: String, min minVal: Double = 1.0, max maxVal: Double = 10.0) {
        let clamped = Swift.max(minVal, Swift.min(maxVal, value))
        scores[key] = clamped
        disabledCategories.remove(key)
    }

    /// Returns normalized score ratio in range [0.0, 1.0] for drawing calculations.
    /// If disabled, returns 0.0 (collapses vertex to center of polygon chart).
    func normalizedScore(for key: String, min minVal: Double = 1.0, max maxVal: Double = 10.0) -> Double {
        guard isEnabled(key) else { return 0.0 }
        let val = score(for: key, default: minVal)
        let range = maxVal - minVal
        guard range > 0 else { return 0.0 }
        return Swift.max(0.0, Swift.min(1.0, (val - minVal) / range))
    }

    // MARK: - JSON Serialization & Deserialization for Database Integration

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        self.init(jsonData: data)
    }

    init?(jsonData: Data) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(RadarRating.self, from: jsonData) {
            self = decoded
        } else if let dict = try? decoder.decode([String: Double].self, from: jsonData) {
            self.init(scores: dict)
        } else {
            return nil
        }
    }

    func toJSONString() -> String? {
        guard let data = toJSONData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    // MARK: - Custom Codable Conformance
    // Decodes legacy dictionary format `{"Cost": 5.5}` and structured format `{"scores": {...}, "disabledCategories": [...]}` seamlessly.

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: Double].self) {
            self.scores = dict
            self.disabledCategories = []
            return
        }

        let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.scores = try objectContainer.decode([String: Double].self, forKey: .scores)
        self.disabledCategories = (try? objectContainer.decode(Set<String>.self, forKey: .disabledCategories)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scores, forKey: .scores)
        try container.encode(Array(disabledCategories), forKey: .disabledCategories)
    }

    private enum CodingKeys: String, CodingKey {
        case scores
        case disabledCategories
    }
}
