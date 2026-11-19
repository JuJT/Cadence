import XCTest
@testable import CadenceCore

final class PronoteModelsTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = SchoolDateCodec.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid school date"))
            }
            return date
        }
        return decoder
    }

    func testProfileDecodesPeriodsWithOffsetsAndOptionalStudentClass() throws {
        let json = """
        {"displayName":"Élève","establishment":"Lycée","resourceID":"student-1",
        "resources":[{"id":"student-1","name":"Élève"}],"capabilities":["grades","contents"],
        "periods":[{"id":"term-1","name":"Trimestre 1","kind":0,
        "startDate":"2026-09-01T00:00:00+02:00","endDate":"2026-11-30T23:59:59.123456Z"}]}
        """
        let profile = try decoder().decode(PronoteProfile.self, from: Data(json.utf8))
        XCTAssertNil(profile.className)
        XCTAssertNil(profile.resources.first?.className)
        XCTAssertEqual(profile.periods.first?.startDate, SchoolDateCodec.date(from: "2026-08-31T22:00:00Z"))
        XCTAssertEqual(profile.periods.first?.endDate, SchoolDateCodec.date(from: "2026-11-30T23:59:59.123456Z"))
        XCTAssertEqual(profile.capabilities, ["grades", "contents"])
        XCTAssertNil(profile.defaultPeriodIDs)
        XCTAssertNil(profile.sectionPeriodIDs)
    }

    func testCurrentPeriodUsesTheScreenDefaultAndAvoidsOverlappingAnnualPeriod() {
        let annual = PronotePeriod(id: "year", name: "Année", kind: 0,
            startDate: SchoolDateCodec.date(from: "2026-09-01T00:00:00Z")!, endDate: SchoolDateCodec.date(from: "2027-08-31T23:59:59Z")!)
        let term = PronotePeriod(id: "term1", name: "Trimestre 1", kind: 1,
            startDate: annual.startDate, endDate: SchoolDateCodec.date(from: "2026-12-15T23:59:59Z")!)
        let date = SchoolDateCodec.date(from: "2026-11-19T12:00:00Z")!
        var profile = PronoteProfile(displayName: "Élève", establishment: "Lycée", resourceID: "student",
            periods: [annual, term], defaultPeriodIDs: ["grades": term.id], sectionPeriodIDs: ["grades": [term.id]])
        XCTAssertEqual(profile.currentPeriodID(for: "grades", at: date), term.id)
        XCTAssertEqual(profile.periods(for: "grades").map(\.id), [term.id])
        profile.defaultPeriodIDs = nil; profile.sectionPeriodIDs = nil
        XCTAssertEqual(profile.currentPeriodID(for: "grades", at: date), term.id)
        profile.defaultPeriodIDs = ["grades": annual.id]
        XCTAssertEqual(profile.currentPeriodID(for: "grades", at: date), annual.id)
    }

    func testPortalCacheRoundTripPreservesOfflineSectionsAndAvailabilityDates() throws {
        let date = SchoolDateCodec.date(from: "2026-11-18T07:00:00Z")!
        let cache = PronotePortalCache(
            profile: PronoteProfile(displayName: "Élève", establishment: "Lycée", resourceID: "student-1"),
            sections: ["grades:term-1": .object(["grades": .array([
                .object(["value": .object(["kind": .number(1), "points": .null])])
            ])]), "discussion:thread-1": .object(["sents": .array([])])],
            updatedAt: ["grades:term-1": date])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try decoder().decode(PronotePortalCache.self, from: encoder.encode(cache))
        XCTAssertEqual(cache, decoded)
        XCTAssertEqual(decoded.sections["grades:term-1"]?["grades"]?.arrayValues?.count, 1)
        XCTAssertEqual(decoded.sections["grades:term-1"]?["grades"]?.arrayValues?.first?["value"]?["kind"]?.integerValue, 1)
        XCTAssertNil(decoded.sections["grades:term-1"]?["grades"]?.arrayValues?.first?["value"]?["points"]?.numberValue)
    }

    func testJSONTypedAccessorsDoNotConfuseBooleanStringOrOutOfRangeNumbers() throws {
        XCTAssertEqual(SchoolJSON.number(16).integerValue, 16)
        XCTAssertNil(SchoolJSON.number(16.5).integerValue)
        XCTAssertNil(SchoolJSON.number(.infinity).integerValue)
        XCTAssertNil(SchoolJSON.number(Double(Int.max)).integerValue)
        XCTAssertNil(SchoolJSON.string("16").numberValue)
        XCTAssertNil(SchoolJSON.bool(true).integerValue)
        XCTAssertNil(SchoolJSON.array([])["id"])
        XCTAssertEqual(SchoolJSON.object(["done": .bool(false)])["done"]?.boolValue, false)
        let school = PronoteSchool(url: "https://example.edu/pronote/", name: "Lycée")
        XCTAssertEqual(school.id, school.url)
        XCTAssertNil(school.distance)
        let challenge = PronoteSecurityChallenge(shouldEnterPIN: true, availableModes: [0, 2], passwordMinLength: 8)
        XCTAssertEqual(try JSONDecoder().decode(PronoteSecurityChallenge.self, from: JSONEncoder().encode(challenge)), challenge)
    }
}
