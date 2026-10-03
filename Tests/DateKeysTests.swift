// DateKeysTests.swift
// Le calcul des dates est la base de tout le programme : une date décalée d'un
// jour décale les séances, les révisions et les consolidations.
//
// Les deux pièges couverts ici :
//   1. l'heure d'été — une date doit rester un JOUR calendaire, pas 86 400
//      secondes. C'est pour cela que tout est ancré à midi ;
//   2. le premier jour de la semaine — `Date.getDay()` côté JavaScript renvoie
//      0 pour dimanche, et la semaine d'objectif commence le lundi.

import XCTest
@testable import Swiftdeepseek

final class DateKeysTests: XCTestCase {

    func testDayOfMatchesJavaScriptGetDay() {
        // 2026-10-04 est un dimanche → 0, comme `new Date(...).getDay()`.
        XCTAssertEqual(DateKeys.dayOf("2026-10-04"), 0)
        XCTAssertEqual(DateKeys.dayOf("2026-10-05"), 1) // lundi
        XCTAssertEqual(DateKeys.dayOf("2026-10-10"), 6) // samedi
    }

    func testWeekStartIsMonday() {
        // Dimanche : la semaine en cours a commencé le lundi précédent.
        XCTAssertEqual(DateKeys.weekStart("2026-10-04"), "2026-09-28")
        // Lundi : la semaine commence le jour même.
        XCTAssertEqual(DateKeys.weekStart("2026-10-05"), "2026-10-05")
        // Samedi : toujours le lundi de la même semaine.
        XCTAssertEqual(DateKeys.weekStart("2026-10-10"), "2026-10-05")
    }

    func testMonthStart() {
        XCTAssertEqual(DateKeys.monthStart("2026-10-04"), "2026-10-01")
        XCTAssertEqual(DateKeys.monthStart("2026-01-31"), "2026-01-01")
    }

    func testAddDaysAcrossAYearStaysOnCalendarDays() {
        // Si `addDays` ajoutait 86 400 secondes au lieu d'un jour calendaire,
        // cette boucle dériverait dans tout fuseau qui observe l'heure d'été.
        var key = "2026-01-01"
        for _ in 0..<365 { key = DateKeys.addDays(key, 1) }
        XCTAssertEqual(key, "2027-01-01")
    }

    func testAddDaysIsReversible() {
        for offset in [-40, -7, -1, 0, 1, 7, 40] {
            XCTAssertEqual(DateKeys.addDays(DateKeys.addDays("2026-06-15", offset), -offset), "2026-06-15")
        }
    }

    func testAddDaysCrossesDaylightSavingBoundary() throws {
        // Ce test ne prouve rien dans un fuseau sans heure d'été (un simulateur
        // en UTC, par exemple). On le dit explicitement plutôt que de le laisser
        // vert pour la mauvaise raison.
        let january = try XCTUnwrap(DateKeys.date(from: "2026-01-15"))
        let july = try XCTUnwrap(DateKeys.date(from: "2026-07-15"))
        let observesDST = TimeZone.current.daylightSavingTimeOffset(for: january)
            != TimeZone.current.daylightSavingTimeOffset(for: july)
        try XCTSkipUnless(observesDST, "Fuseau courant sans heure d'été : rien à éprouver.")

        // 2026-03-29 est le passage à l'heure d'été en Europe.
        XCTAssertEqual(DateKeys.addDays("2026-03-28", 1), "2026-03-29")
        XCTAssertEqual(DateKeys.addDays("2026-03-29", 1), "2026-03-30")
        XCTAssertEqual(DateKeys.addDays("2026-10-24", 1), "2026-10-25")
        XCTAssertEqual(DateKeys.addDays("2026-10-25", 1), "2026-10-26")
    }

    func testDateFromKeyIsNoonLocal() throws {
        let date = try XCTUnwrap(DateKeys.date(from: "2026-10-04"))
        let components = DateKeys.calendar.dateComponents([.year, .month, .day, .hour], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 4)
        XCTAssertEqual(components.hour, 12)
    }

    func testMaxISOIsStrictlyLaterThanBothInputs() throws {
        let older = try XCTUnwrap(DateKeys.parseISO("2020-01-01T00:00:00.000Z"))
        let newer = try XCTUnwrap(DateKeys.parseISO("2020-01-02T00:00:00.000Z"))
        let result = try XCTUnwrap(DateKeys.parseISO(DateKeys.maxISO([older, newer])))
        XCTAssertGreaterThan(result, newer)
    }
}
