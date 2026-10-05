// QuranSourceNavigation.swift
// Traduire un verset en page, pour une édition donnée — port de
// `src/core/sourceNavigation.ts`.
//
// POURQUOI CE FICHIER EXISTE
//   Un marque-page enregistre un VERSET, pas seulement une page. « Reprendre »
//   doit donc retrouver la page de ce verset dans l'édition qu'on est en train
//   de lire. Or chaque édition a sa propre pagination : la page 100 du Coran de
//   Médine et la page 100 du Coran 1441 ne montrent pas le même passage. Ouvrir,
//   dans le Coran 1441, la page du moushaf retenue pour un verset mène donc à un
//   endroit sans rapport — et rien ne le signale, la page s'affiche.
//
//   L'original a une fonction pour cela (`sourceVersePage`), et deux appelants :
//   la liste des marque-pages — pour écrire « Page N · Verset M » — et la
//   reprise — pour ouvrir la bonne page. La règle vit donc ici, une seule fois :
//   deux copies divergeraient, et l'écran afficherait une page que « Reprendre »
//   n'ouvrirait pas.
//
// TROIS BRANCHES DANS L'ORIGINAL, DEUX ICI
//   `sourceNavigation.ts:4` :
//     source === 'coranTest' → testVersePage(id, current)
//     isZipSource(source)    → zipVersePage(source, id, current)   // coran_1441
//     sinon                  → pageOf(id)
//
//   La branche `coranTest` n'est PAS portée : `testVersePage` lit un index
//   verset → pages construit depuis le moushaf de Tajwid (607 polices `.woff2`),
//   que cette application n'embarque pas. Elle est **inatteignable** ici, et
//   c'est mesurable : `QuranEdition.isAvailable` n'est vrai que pour `.medine`
//   et `.coran1441`, et `QuranEdition.displayed(stored:)` remplace toute autre
//   préférence par `.medine`. Les deux appelants ne reçoivent donc jamais
//   `.coranTest`. Voir §9.28.
//
// DEUX RÈGLES SILENCIEUSES DE LA BRANCHE 1441
//
//   1. LA PAGE STOCKÉE N'EST PAS CRUE SUR PAROLE. `zipVersePage` ne retient
//      `current` que s'il fait partie des pages du verset (`pages.includes`) ;
//      sinon il rend la PREMIÈRE page du verset. Un `current` périmé — écrit
//      avant un changement de découpage, ou hérité d'une autre édition — mènerait
//      sinon n'importe où.
//
//   2. LA PREMIÈRE PAGE, PAS LA PLUS PROCHE. `zipVersePages` parcourt les pages
//      dans l'ordre CROISSANT et empile, donc `pages[0]` est la plus PETITE page
//      qui porte le verset. Un verset à cheval sur deux pages s'ouvre donc sur la
//      première — comme `pageOf(id)` pour le Coran de Médine, qui rend la page
//      d'OUVERTURE du verset.
//
// CE QUI N'EST PAS ICI
//   `sourcePageRange` (`sourceNavigation.ts:5`) n'est pas portée : elle traduit
//   une page en plage de versets pour les sources à pagination propre, et aucun
//   écran monté n'en a besoin.

import Foundation

public enum QuranSourceNavigation {

    /// `sourceVersePage` — `src/core/sourceNavigation.ts:4`.
    ///
    /// `current` est la page que l'appelant connaît déjà pour cette édition
    /// (`VerseBookmark.sourcePages[édition]`). Elle n'est retenue que si elle
    /// porte réellement le verset. `nil` veut dire « la page ne peut pas être
    /// déterminée » : l'appelant garde alors la sienne, plutôt que d'en inventer
    /// une dans une pagination qui n'est pas la sienne.
    public static func versePage(
        _ edition: QuranEdition,
        verseID: Int,
        current: Int? = nil
    ) -> Int? {
        switch edition {
        case .coran1441:
            let pages = coran1441VersePages(verseID)
            if let current, pages.contains(current) { return current }
            // `pages[0] ?? 1` dans l'original : un verset absent de l'index rend
            // `undefined`, que l'original remplace par 1.
            return pages.first ?? 1

        case .medine, .tajweed, .tajweedPages, .coranTest:
            // `pageOf(id)`. `sourcePages` est délibérément IGNORÉ pour ces
            // éditions : `sourceVersePage` ne lit la page connue que pour les
            // sources à pagination propre. Le retenir ici ouvrirait la deuxième
            // page d'un verset à cheval sur deux lignes, là où l'original ouvre
            // la première.
            return Quran.pageOf(verseID)
        }
    }

    // MARK: L'index du Coran 1441

    /// Verset → pages du Coran 1441, croissantes — `zipVersePages`,
    /// `src/core/quranSources.ts:13`.
    ///
    /// Construit **une fois**, à la première demande, comme l'original le met en
    /// cache (`indexes`). Le parcours est celui de l'original : les pages dans
    /// l'ordre croissant, et pour chacune ses lignes — c'est ce qui rend chaque
    /// liste croissante, et donc `pages.first` la première page du verset.
    ///
    /// Un verset absent de l'index rend une liste vide : l'index est bâti sur
    /// `coran_1441-bounds.json`, qui décrit les 604 pages ; un verset qu'aucune
    /// ligne n'ouvre n'y figure pas.
    private static let coran1441Index: [Int: [Int]] = {
        var index: [Int: [Int]] = [:]
        for page in 1...QuranSourceService.totalPages {
            for row in VerseBounds.rows(page: page, source: .coran1441) {
                guard let id = Quran.verseID(surah: row.surah, ayah: row.ayahStart) else { continue }
                if index[id]?.contains(page) != true {
                    index[id, default: []].append(page)
                }
            }
        }
        return index
    }()

    private static func coran1441VersePages(_ verseID: Int) -> [Int] {
        coran1441Index[verseID] ?? []
    }
}
