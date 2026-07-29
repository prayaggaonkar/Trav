import XCTest
import MapKit
@testable import Trav

final class ExperienceInsertTests: XCTestCase {
    func testExperienceInsertEncoding() throws {
        let insert = ExperienceInsert(
            title: "The Best of Paris in One Day",
            city: "Paris",
            stops: ["Café de Flore", "Louvre Museum", "Le Bistrot"],
            description: "A perfect 1-day loop in Paris."
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(insert)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["title"] as? String, "The Best of Paris in One Day")
        XCTAssertEqual(json?["city"] as? String, "Paris")
        XCTAssertEqual(json?["user_id"] as? String, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(json?["save_count"] as? Int, 0)
        XCTAssertEqual(json?["is_published"] as? Bool, true)
    }

    func testAutoSeedManagerDescriptionTemplating() async {
        await MainActor.run {
            let manager = AutoSeedManager.shared

            let cafePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522))
            let cafeItem = MKMapItem(placemark: cafePlacemark)
            cafeItem.name = "Café de Flore"
            cafeItem.pointOfInterestCategory = .cafe

            let museumPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 48.8606, longitude: 2.3376))
            let museumItem = MKMapItem(placemark: museumPlacemark)
            museumItem.name = "Louvre Museum"
            museumItem.pointOfInterestCategory = .museum

            let dinnerPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 48.8530, longitude: 2.3499))
            let dinnerItem = MKMapItem(placemark: dinnerPlacemark)
            dinnerItem.name = "Le Bistrot"
            dinnerItem.pointOfInterestCategory = .restaurant

            let description = manager.generateItineraryDescription(
                stops: [cafeItem, museumItem, dinnerItem],
                city: "Paris"
            )

            XCTAssertTrue(description.contains("Paris"))
            XCTAssertTrue(description.contains("Café de Flore"))
            XCTAssertTrue(description.contains("Louvre Museum"))
            XCTAssertTrue(description.contains("Le Bistrot"))
            XCTAssertTrue(description.contains("A perfect 1-day loop"))
        }
    }
}
