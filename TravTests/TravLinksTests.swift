import XCTest
@testable import Trav

final class TravLinksTests: XCTestCase {
    func testExperienceDeepLinkRoundTrip() {
        let id = UUID()
        let url = TravLinks.experience(id)
        let route = TravLinks.route(for: url)
        guard case let .experience(parsed)? = route else {
            return XCTFail("Expected experience route")
        }
        XCTAssertEqual(parsed, id)
    }

    func testProfileDeepLink() {
        let url = TravLinks.profile("maya.chen")
        let route = TravLinks.route(for: url)
        guard case let .profile(username)? = route else {
            return XCTFail("Expected profile route")
        }
        XCTAssertEqual(username, "maya.chen")
    }

    func testCityDeepLink() {
        let id = UUID()
        let url = TravLinks.city(id)
        let route = TravLinks.route(for: url)
        guard case let .city(parsed)? = route else {
            return XCTFail("Expected city route")
        }
        XCTAssertEqual(parsed, id)
    }

    func testIgnoresForeignSchemes() {
        let url = URL(string: "https://example.com/experience/\(UUID().uuidString)")!
        XCTAssertNil(TravLinks.route(for: url))
    }
}

final class UsernameValidatorTests: XCTestCase {
    func testValidUsername() {
        XCTAssertEqual(UsernameValidator.validateFormat("traveler_1"), .available)
    }

    func testRejectsTooShort() {
        if case .invalid = UsernameValidator.validateFormat("ab") {
            // expected
        } else {
            XCTFail("Expected invalid for short username")
        }
    }

    func testRejectsReserved() {
        if case .invalid = UsernameValidator.validateFormat("admin") {
            // expected
        } else {
            XCTFail("Expected reserved username rejection")
        }
    }
}

final class StableUUIDTests: XCTestCase {
    func testParsesRealUUID() {
        let id = UUID()
        XCTAssertEqual(StableUUID.from(id.uuidString), id)
    }

    func testDeterministicForOpaqueIDs() {
        let a = StableUUID.from("overture:place:abc")
        let b = StableUUID.from("overture:place:abc")
        let c = StableUUID.from("overture:place:xyz")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
