// QuranSourceNavigation.swift
// Traduire un verset en page, et une page en plage de versets, pour une édition
// donnée — port de `src/core/sourceNavigation.ts`.
//
// POURQUOI CE FICHIER EXISTE
//   Un marque-page enregistre un VERSET, pas seulement une page. « Reprendre »
//   doit donc retrouver la page de ce verset dans l'édition qu'on est en train
//   de lire. Or chaque édition a sa propre pagination : la page 100 du Coran de
//   Médine et la page 100 du Coran 1441 ne montrent pas le même passage. Ouvrir,
//   dans le Coran 1441, la page du moushaf retenue pour un verset mène donc à un
//   endroit sans rapport — et rien ne le signale, la page s'affiche.
//
//   La même erreur existe dans l'autre sens, et c'est la seconde moitié de ce
//   fichier : le panneau audio offre « Toute la page », c'est-à-dire la plage de
//   versets de la page lue. Là encore la réponse dépend de l'édition — et
//   l'original lui passe explicitement la bonne (`App.tsx:437`, `:505`).
//
//   L'original a une fonction pour chacune (`sourceVersePage`,
//   `sourcePageRange`), et deux appelants pour la première : la liste des
//   marque-pages — pour écrire « Page N · Verset M » — et la reprise — pour
//   ouvrir la bonne page. La règle vit donc ici, une seule fois : deux copies
//   divergeraient, et l'écran afficherait une page que « Reprendre »
//   n'ouvrirait pas.
//
// TROIS BRANCHES DANS L'ORIGINAL, DEUX ICI
//   `sourceNavigation.ts:4` et `:5` sont le MÊME aiguillage, appliqué au verset
//   et à la page :
//
//     source === 'coranTest' → testVersePage(id, current) / testPageRange(page)
//     isZipSource(source)    → zipVersePage(…) / zipPageRange(…)   // coran_1441
//     sinon                  → pageOf(id) / pageRange(page)        // Médine
//
//   DEUX BRANCHES SUR TROIS, ET C'EST UNE MESURE, PAS UNE ÉCONOMIE
//     Les deux premières lisent deux fichiers différents — `coranTest` un index
//     `sourate:verset → pages` (`src/coranTest/data/verse-index.json`), le 1441
//     les rectangles de `coran_1441-bounds.json` — mais ils rendent la MÊME
//     réponse. Mesuré par `_banc/oracle-source-navigation.mjs`, qui exécute le
//     vrai `sourceNavigation.ts` et confronte la formulation de ce fichier, sur
//     les actifs de CE dépôt :
//
//       · les 604 pages, pour les cinq identifiants d'édition : 0 divergence ;
//       · les 6 236 versets, pour trois valeurs de `current` : 0 divergence.
//
//     Les deux branches sont donc repliées en une seule. C'est le seul endroit
//     du portage où deux branches de l'original se confondent, et la raison est
//     mesurée : `coran_1441-bounds.json` **est** l'index du `coranTest`, verset
//     par verset.
//
// CE QUE CE FICHIER NE PRÉTEND PAS
//   Le `coranTest` n'est PAS rendu ici : il l'est par une page HTML dans un
//   WebView, avec 607 polices `.woff2` (`src/coranTest/html.ts`). C'est une
//   chaîne de RENDU, et elle manque toujours. Mais elle ne doit pas être
//   confondue avec la chaîne de NAVIGATION : celle-ci ne lit que des nombres —
//   `verse-index.json` fait 380 782 octets et ne contient que `{id, pages,
//   lines}` pour 6 236 versets, aucune police, aucune vue. La navigation du
//   `coranTest` est donc **portée ici**, et ses deux branches sont **justes** ;
//   elles sont simplement **dormantes**, parce que `QuranEdition.isAvailable`
//   est faux pour `.coranTest` et que `displayed(stored:)` le remplace alors par
//   `.medine`. Le jour où le rendu arrive, la navigation est déjà bonne. Voir
//   §9.28 et §9.33.
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
//      qui porte le verset. Un verset à cheval sur deux pages s'ouvrirait donc
//      sur la première — comme `pageOf(id)` pour le Coran de Médine, qui rend la
//      page d'OUVERTURE du verset.
//
//      CE CAS NE SE PRODUIT PAS, ET C'EST MESURÉ : sur les 6 236 versets du
//      1441, **aucun** n'est porté par plus d'une page (le maximum est 1). La
//      règle est donc sans effet ici, et la valeur connue avec elle — c'est ce
//      qui permet à `ReaderView` de ne pas la transmettre. La garder telle
//      quelle reste juste : elle protège contre un découpage qui changerait.
//
// TROISIÈME RÈGLE, POUR LA PLAGE : ELLE DÉPEND DE L'ÉDITION
//   `zipPageRange` prend le minimum et le maximum des versets OUVERTS par les
//   lignes de la page. La table `pages.json` du Coran de Médine donne la même
//   chose pour ses propres pages. Les deux ne coïncident PAS : **36 pages sur
//   604** portent une plage différente, et sur 33 d'entre elles la LONGUEUR
//   diffère aussi (page 597 : 6 099…6 125 au Médine contre 6 093…6 118 en 1441).
//   Servir l'une pour l'autre annonce donc un passage qui n'est pas celui qu'on
//   lit — d'où `pageRange(_:page:)`, et d'où le fait qu'un appelant doive
//   toujours dire de quelle édition il parle.

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
        case .coran1441, .coranTest:
            // `testVersePage` et `zipVersePage` lisent deux fichiers différents
            // et rendent la même réponse — mesuré, 0 divergence sur 6 236
            // versets. Ils ne diffèrent que sur un verset ABSENT de l'index :
            // `testVersePage` lève `'Verset introuvable dans le Mushaf.'`,
            // `zipVersePage` rend `pages[0] ?? 1`. Aucun des deux index n'a de
            // trou — les 6 236 versets y figurent —, donc ce cas est
            // inatteignable, et le portage garde le repli de `zipVersePage`.
            let pages = coran1441VersePages(verseID)
            if let current, pages.contains(current) { return current }
            return pages.first ?? 1

        case .medine, .tajweed, .tajweedPages:
            // `pageOf(id)`. `sourcePages` est délibérément IGNORÉ pour ces
            // éditions : `sourceVersePage` ne lit la page connue que pour les
            // sources à pagination propre. Le retenir ici ouvrirait la deuxième
            // page d'un verset à cheval sur deux lignes, là où l'original ouvre
            // la première.
            //
            // `tajweedPages` emprunte cette branche sans être atteignable :
            // `isAvailable` est faux pour elle, et `displayed(stored:)` la
            // remplace par `.medine`. `.tajweed`, elle, est atteignable — et
            // c'est bien la pagination du Coran de Médine que
            // `TajweedVerseListView` reçoit.
            return Quran.pageOf(verseID)
        }
    }

    /// `sourcePageRange` — `src/core/sourceNavigation.ts:5`.
    ///
    /// La plage de versets d'une page, **dans la pagination de cette édition**.
    /// L'original l'appelle pour trois usages, tous dans `App.tsx` : la plage de
    /// la page que le panneau audio reçoit (`:437`, `:505`, sous le nom
    /// `pageRangeOverride`), la plage de l'enregistreur de récitation (`:508`)
    /// et celle du panneau de traduction (`:509`). Les deux derniers
    /// appartiennent à des écrans non portés ; le premier, si.
    ///
    /// `nil` veut dire « page hors bornes, ou page sans ligne ». Les deux sont
    /// inatteignables ici — `pages.json` porte 604 pages et
    /// `coran_1441-bounds.json` en porte 604 —, mais l'original ne lève que dans
    /// un cas sur trois (`testPageRange` lève `'Page invalide.'`, `zipPageRange`
    /// rend `{Infinity, -Infinity}`, `pageRange` lève `'Page invalide'`), et un
    /// `nil` unique dit la même chose pour les trois sans reproduire une
    /// arithmétique qui n'a pas de sens.
    public static func pageRange(_ edition: QuranEdition, page: Int) -> VerseRange? {
        switch edition {
        case .coran1441, .coranTest:
            return coran1441PageRange(page)
        case .medine, .tajweed, .tajweedPages:
            return Quran.pageRange(page)
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

    /// Page → plage de versets du Coran 1441 — `zipPageRange`,
    /// `src/core/quranSources.ts:15`.
    ///
    /// DÉRIVÉE DE L'INDEX CI-DESSUS, ET NON RECALCULÉE SUR LES LIGNES. L'original
    /// fait l'inverse — il reparcourt les lignes de la page et prend le minimum
    /// et le maximum des versets qu'elles ouvrent. Les deux donnent la même
    /// table, mais celle-ci ne PEUT PAS diverger de `versePage` : les deux
    /// répondent depuis la même donnée, donc une page ne peut pas annoncer une
    /// plage dont elle n'ouvrirait pas les versets. Deux parcours séparés
    /// finiraient par se contredire, et la contradiction serait silencieuse.
    ///
    /// `zipPageRange` ne trie ni ne dédoublonne : il prend `Math.min` et
    /// `Math.max` sur la liste. Un minimum et un maximum ne dépendent donc pas de
    /// l'ordre, et l'accumulation ci-dessous les rend identiques.
    private static let coran1441PageRanges: [Int: VerseRange] = {
        var ranges: [Int: VerseRange] = [:]
        for (verseID, pages) in coran1441Index {
            for page in pages {
                if let existing = ranges[page] {
                    ranges[page] = VerseRange(
                        start: min(existing.start, verseID),
                        end: max(existing.end, verseID)
                    )
                } else {
                    ranges[page] = VerseRange(start: verseID, end: verseID)
                }
            }
        }
        return ranges
    }()

    private static func coran1441PageRange(_ page: Int) -> VerseRange? {
        coran1441PageRanges[page]
    }
}
