import Foundation
import simd

enum EarthSunPosition {
    /// Unit vector pointing from Earth center toward the sun (world space).
    /// Matches the Sequoia / three-globe subsolar-point calculation.
    static func direction(at date: Date = .now) -> SIMD3<Float> {
        let calendar = Calendar(identifier: .gregorian)
        let utc = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1

        let sunLatDeg = -23.44 * cos(Double(dayOfYear + 10) * (360.0 / 365.0) * .pi / 180.0)
        let hour = Double(utc.hour ?? 0)
        let minute = Double(utc.minute ?? 0)
        let second = Double(utc.second ?? 0)
        let sunLngDeg = -((hour + minute / 60.0 + second / 3600.0) / 24.0 * 360.0) + 180.0

        let lat = Float(sunLatDeg * .pi / 180)
        let lon = Float(sunLngDeg * .pi / 180)

        return normalize(SIMD3(
            cos(lat) * cos(lon),
            sin(lat),
            cos(lat) * sin(lon)
        ))
    }
}
