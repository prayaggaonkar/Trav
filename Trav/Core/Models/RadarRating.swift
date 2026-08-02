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
        if disabledCategories.isEmpty && !scores.isEmpty {
            let activeKeys = Set(scores.keys.map { Self.canonicalAxisID($0) })
            let allKeys = Set(RadarAxis.defaultAxes.map(\.id))
            self.disabledCategories = allKeys.subtracting(activeKeys)
        } else {
            self.disabledCategories = Self.normalizedDisabled(disabledCategories)
        }
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

    /// Empty chart for create flows — user must enable/score at least one axis.
    static var emptyRating: RadarRating {
        RadarRating(
            scores: [:],
            disabledCategories: Set(RadarAxis.defaultAxes.map(\.id))
        )
    }

    /// Ensures all scored categories are enabled so the polygon chart renders filled.
    var sanitizedForEditing: RadarRating {
        var copy = self
        for (key, val) in copy.scores {
            if val >= 1.0 {
                let canonical = Self.canonicalAxisID(key)
                copy.disabledCategories.remove(canonical)
            }
        }
        return copy
    }

    // MARK: - Enable / Disable Category Controls

    /// Returns whether a category is currently active/enabled.
    func isEnabled(_ key: String) -> Bool {
        let canonical = Self.canonicalAxisID(key)
        if disabledCategories.contains(canonical) { return false }
        // Legacy Immersion → Niche alias.
        if canonical == "Niche", disabledCategories.contains("Immersion") { return false }
        return true
    }

    /// True when at least one axis is enabled and has a score in range.
    var hasActiveScores: Bool {
        !activeScores.isEmpty
    }

    /// Enabled axis scores only — the sole input to overallScore.
    var activeScores: [String: Double] {
        var result: [String: Double] = [:]
        for (key, value) in scores {
            let canonical = Self.canonicalAxisID(key)
            guard isEnabled(canonical) else { continue }
            guard value >= 1.0, value <= 10.0 else { continue }
            // Prefer Niche over legacy Immersion if both somehow present.
            if canonical == "Niche", result["Niche"] != nil, key == "Immersion" { continue }
            result[canonical] = value
        }
        return result
    }

    /// Toggles a category between enabled and disabled states.
    /// Keeps at least one category on when scores already exist.
    mutating func toggleCategory(_ key: String) {
        let canonical = Self.canonicalAxisID(key)
        if disabledCategories.contains(canonical) {
            disabledCategories.remove(canonical)
            disabledCategories.remove("Immersion")
            if scores[canonical] == nil, canonical == "Niche", let legacy = scores["Immersion"] {
                scores[canonical] = legacy
            } else if scores[canonical] == nil {
                // Turning a category on counts as rating it (mid default until dragged).
                scores[canonical] = 5.0
            }
        } else {
            let enabledKeys = Set(scores.keys.map(Self.canonicalAxisID)).union(
                Set(RadarAxis.defaultAxes.map(\.id))
            ).filter { isEnabled($0) }
            if enabledKeys.count <= 1, enabledKeys.contains(canonical) {
                return
            }
            disabledCategories.insert(canonical)
        }
    }

    /// Explicitly sets the enabled state of a category.
    mutating func setEnabled(_ enabled: Bool, for key: String) {
        let canonical = Self.canonicalAxisID(key)
        if enabled {
            disabledCategories.remove(canonical)
            if canonical == "Niche" { disabledCategories.remove("Immersion") }
        } else {
            disabledCategories.insert(canonical)
        }
    }

    // MARK: - Score Calculations & Accessors

    /// Overall aggregate across ONLY enabled axes. Disabled subratings never count.
    var overallScore: Double {
        let active = activeScores
        if !active.isEmpty {
            let sum = active.values.reduce(0.0, +)
            let average = sum / Double(active.count)
            return (average * 10.0).rounded() / 10.0
        }
        let validScores = scores.values.filter { $0 >= 1.0 && $0 <= 10.0 }
        if !validScores.isEmpty {
            let sum = validScores.reduce(0.0, +)
            let average = sum / Double(validScores.count)
            return (average * 10.0).rounded() / 10.0
        }
        return 0.0
    }

    /// Returns score for a specific axis ID. If disabled, returns 0.0.
    func score(for key: String, default defaultVal: Double = 5.0) -> Double {
        let canonical = Self.canonicalAxisID(key)
        guard isEnabled(canonical) else { return 0.0 }
        if let val = scores[canonical] { return val }
        if let val = scores[key] { return val }
        if canonical == "Niche", let legacyVal = scores["Immersion"] { return legacyVal }
        return defaultVal
    }

    /// Sets score for a specific axis ID, clamping within [minValue, maxValue]. Automatically enables category if score is set.
    mutating func setScore(_ value: Double, for key: String, min minVal: Double = 1.0, max maxVal: Double = 10.0) {
        let canonical = Self.canonicalAxisID(key)
        let clamped = Swift.max(minVal, Swift.min(maxVal, value))
        scores[canonical] = clamped
        disabledCategories.remove(canonical)
        if canonical == "Niche" {
            disabledCategories.remove("Immersion")
            scores.removeValue(forKey: "Immersion")
        }
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

    private static func canonicalAxisID(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("Cost") == .orderedSame { return "Cost" }
        if trimmed.caseInsensitiveCompare("Food") == .orderedSame { return "Food" }
        if trimmed.caseInsensitiveCompare("Memorability") == .orderedSame { return "Memorability" }
        if trimmed.caseInsensitiveCompare("Authenticity") == .orderedSame { return "Authenticity" }
        if trimmed.caseInsensitiveCompare("Niche") == .orderedSame || trimmed.caseInsensitiveCompare("Immersion") == .orderedSame { return "Niche" }
        return trimmed
    }

    private static func normalizedDisabled(_ set: Set<String>) -> Set<String> {
        Set(set.map { canonicalAxisID($0) })
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
            let activeKeys = Set(dict.keys.map { Self.canonicalAxisID($0) })
            let allKeys = Set(RadarAxis.defaultAxes.map(\.id))
            self.disabledCategories = allKeys.subtracting(activeKeys)
            return
        }

        let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.scores = try objectContainer.decode([String: Double].self, forKey: .scores)
        let rawDisabled = (try? objectContainer.decode(Set<String>.self, forKey: .disabledCategories)) ?? []
        if rawDisabled.isEmpty && !self.scores.isEmpty {
            let activeKeys = Set(self.scores.keys.map { Self.canonicalAxisID($0) })
            let allKeys = Set(RadarAxis.defaultAxes.map(\.id))
            self.disabledCategories = allKeys.subtracting(activeKeys)
        } else {
            self.disabledCategories = Self.normalizedDisabled(rawDisabled)
        }
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
