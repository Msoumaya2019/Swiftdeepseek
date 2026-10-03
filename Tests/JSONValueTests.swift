// JSONValueTests.swift
// Le type qui permet de ne rien perdre du document partagé.
//
// `canonical` sert de comparaison d'égalité dans la fusion à trois voies : il
// doit reproduire `JSON.stringify`, sinon deux valeurs identiques seraient vues
// comme différentes (et une modification serait perdue ou dupliquée).

import XCTest
@testable import Swiftdeepseek

final class JSONValueTests: XCTestCase {

    func testWholeNumbersDoNotGainADecimalPart() {
        // JavaScript écrit `1`, pas `1.0` : sans cela, la fusion croirait à un
        // changement à chaque aller-retour.
        XCTAssertEqual(JSONValue.number(1).canonical, "1")
        XCTAssertEqual(JSONValue.number(42).canonical, "42")
        XCTAssertEqual(JSONValue.number(-7).canonical, "-7")
    }

    func testFractionalNumbersKeepTheirFraction() {
        XCTAssertEqual(JSONValue.number(1.5).canonical, "1.5")
    }

    func testBooleansAndNull() {
        XCTAssertEqual(JSONValue.bool(true).canonical, "true")
        XCTAssertEqual(JSONValue.bool(false).canonical, "false")
        XCTAssertEqual(JSONValue.null.canonical, "null")
    }

    func testObjectKeysAreSortedSoComparisonIsStable() {
        // L'ordre d'insertion ne doit pas influer : deux dictionnaires de même
        // contenu doivent produire la même chaîne.
        let first = JSONValue.object(["b": .number(2), "a": .number(1)])
        let second = JSONValue.object(["a": .number(1), "b": .number(2)])
        XCTAssertEqual(first.canonical, second.canonical)
        XCTAssertEqual(first.canonical, #"{"a":1,"b":2}"#)
    }

    func testStringsAreEscapedLikeJSONStringify() {
        XCTAssertEqual(JSONValue.string("a\"b").canonical, #""a\"b""#)
        XCTAssertEqual(JSONValue.string("ligne\nsuivante").canonical, #""ligne\nsuivante""#)
        XCTAssertEqual(JSONValue.string("ta\tb").canonical, #""ta\tb""#)
    }

    func testArabicTextIsPreservedAsIs() {
        // Le texte coranique ne doit pas être échappé : il doit survivre
        // octet pour octet à un aller-retour.
        let arabic = "بِسْمِ اللَّهِ"
        XCTAssertEqual(JSONValue.string(arabic).canonical, "\"\(arabic)\"")
    }

    func testNestedStructures() {
        let value = JSONValue.object([
            "a": .array([.number(1), .string("x"), .bool(false)]),
            "b": .object(["c": .null])
        ])
        XCTAssertEqual(value.canonical, #"{"a":[1,"x",false],"b":{"c":null}}"#)
    }

    func testBridgingToAndFromNativeTypes() {
        let native: [String: Any] = [
            "nombre": 3,
            "texte": "ok",
            "drapeau": true,
            "liste": [1, 2]
        ]
        let value = JSONValue.from(native)
        XCTAssertEqual(value["nombre"]?.intValue, 3)
        XCTAssertEqual(value["texte"]?.stringValue, "ok")
        XCTAssertEqual(value["drapeau"]?.boolValue, true)
        XCTAssertEqual(value["liste"]?.arrayValue?.compactMap { $0.intValue }, [1, 2])
    }

    func testNullIsNotTheSameAsAbsent() {
        // Distinction importante : `nil` (clé absente) et `.null` (clé présente
        // mais nulle) ne veulent pas dire la même chose, et la fusion les
        // traite différemment.
        let withNull = JSONValue.object(["a": .null])
        let withoutKey = JSONValue.object([:])
        XCTAssertNotNil(withNull["a"])
        XCTAssertNil(withoutKey["a"])
        XCTAssertTrue(withNull["a"]?.isNull == true)
    }

    func testRoundTripThroughEncodingKeepsTheDocument() throws {
        let original = JSONValue.object([
            "userId": .string("A"),
            "knowledge": .object(["1": .string("perfect")]),
            "readPages": .array([.number(1), .number(2)]),
            "note": .null
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded.canonical, original.canonical)
    }

    func testUnknownKeysSurviveADecodeEncodeCycle() throws {
        // Le cas qui justifie tout ce type : une clé que cette application ne
        // connaît pas doit ressortir intacte.
        let json = #"{"userId":"A","cleFuture":{"profondeur":[1,2,{"x":null}]}}"#
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let reencoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode(JSONValue.self, from: reencoded)
        XCTAssertEqual(again["cleFuture"]?["profondeur"]?.arrayValue?.count, 3)
    }
}
