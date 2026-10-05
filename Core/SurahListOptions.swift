// SurahListOptions.swift
// L'onglet Coran de l'original : la liste des sourates, des Juz' et des Hizb.
// Port de `QuranScreen` (`src/ui/MainScreens.tsx:28-34`).
//
// CE FICHIER PORTE TOUT CE QU'UN ÉCRAN NE DOIT PAS DÉCIDER
//   Les trois vues, le filtre, la dérivation des lignes, les textes, et les
//   **deux** règles de recherche — qui ne portent pas sur les mêmes champs.
//   `SurahListView` ne fait que rendre et déclencher des effets.
//
// LES DEUX RÈGLES DE RECHERCHE, ET POURQUOI ELLES SONT SÉPARÉES
//   Une SOURATE se cherche sur quatre champs concaténés : numéro, nom,
//   signification, arabe (`MainScreens.tsx:31`, première branche). Une
//   DIVISION se cherche sur trois autres : numéro, LIBELLÉ DE LA VUE, et nom de
//   la sourate où la division COMMENCE (même ligne, seconde branche). Les
//   confondre ne se verrait pas — la liste s'afficherait, simplement la
//   recherche ne trouverait pas les mêmes choses.
//
//   Deux conséquences mesurables, qu'un portage « propre » perdrait :
//     - taper « juz » ne trouve RIEN : le libellé porte une apostrophe
//       typographique (U+2019), et `contains` ne l'ignore pas ;
//     - le filtre Mecquoise/Médinoise ne s'applique QU'À la vue « Liste » :
//       la branche des divisions ne le teste pas du tout, et le bouton de
//       filtre n'est d'ailleurs rendu que dans cette vue.
//
// LA PAGE D'UNE DIVISION N'EST PAS UNE ARITHMÉTIQUE LOCALE
//   « Pages X – Y » vient de `studyPage` (`src/core/studyProgress.ts:8`), qui
//   est exactement `QuranSourceNavigation.versePage` **sans** page connue. On
//   réemploie donc la même fonction que la reprise d'une marque-page, au lieu
//   d'en écrire une seconde — deux copies d'une même règle divergent en
//   silence, et c'est le défaut que ce portage vient de fermer ailleurs.
//
//   L'original résout cette page sur `state.reader?.mushaf` **brut**, y compris
//   `coranTest` — dont la pagination n'est pas portée (607 polices `.woff2`,
//   `src/coranTest/html.ts`). On lui passe donc l'édition **affichée**
//   (`QuranEdition.displayed(stored:)`) : pour `traditional` et `coran_1441`,
//   les deux donnent la même page ; pour les trois éditions non rendues, le
//   repli du portage est le Coran de Médine, et c'est la seule réponse que
//   cette version sait donner. Divergence bornée, et la même que celle du
//   lecteur — voir `SWIFT_MIGRATION.md` §9.3.

import Foundation

public enum SurahListOptions {

    // MARK: - Les trois vues

    /// L'original appelle ce type `view` (`MainScreens.tsx:29`). Renommé en
    /// `Mode` parce que `View` est pris par SwiftUI, et parce qu'un
    /// `SegmentedControl` de trois choix se lit comme un mode d'affichage.
    public enum Mode: String, CaseIterable, Sendable {
        case liste
        case juz
        case hizb

        /// Le libellé du sélecteur **et** le préfixe du nom d'une division.
        ///
        /// L'apostrophe de « Juz’ » est U+2019, celle de l'original. Ce n'est pas
        /// cosmétique : elle entre dans la CHAÎNE DE RECHERCHE, donc « juz » ne
        /// trouve rien là où « juz’ » trouve les trente parties. La reproduire à
        /// l'identique est le seul moyen de garder ce comportement.
        public var label: String {
            switch self {
            case .liste: return "Liste"
            case .juz: return "Juz’"
            case .hizb: return "Hizb"
            }
        }
    }

    /// Le filtre de lieu de révélation (`MainScreens.tsx:29`).
    public enum Filter: String, CaseIterable, Sendable {
        case all
        case meccan
        case medinan
    }

    // MARK: - Une ligne

    /// Une ligne de la liste, sourate ou division.
    ///
    /// `id` vient de `keyExtractor` (`MainScreens.tsx:33`) :
    /// `` `${view}-${row.number}` ``. La VUE fait partie de la clé, pas seulement
    /// le numéro : « Juz’ 1 » et « Hizb 1 » sont deux lignes distinctes du même
    /// numéro, et une clé réduite au numéro ferait disparaître l'une des deux.
    public struct Row: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case surah
            case division
        }

        public let id: String
        public let kind: Kind
        public let number: Int
        public let name: String
        public let meaning: String
        public let arabic: String
        public let isMeccan: Bool
        public let count: Int
        public let start: Int
        public let end: Int
    }

    // MARK: - La dérivation des lignes

    /// Les lignes affichées — `MainScreens.tsx:31`.
    ///
    /// Pas de `state` : la ligne ne dépend que de la vue, de la recherche, du
    /// filtre et de l'édition. La seule donnée d'état dont l'original se sert
    /// ici est `reader.mushaf`, et elle arrive par `edition`.
    public static func rows(
        mode: Mode,
        query: String,
        filter: Filter,
        edition: QuranEdition
    ) -> [Row] {
        switch mode {
        case .liste:
            return Quran.surahs
                .filter { matches($0, query: query, filter: filter) }
                .map { row($0, mode: mode) }
        case .juz, .hizb:
            let divisions = mode == .juz ? Quran.juzs : Quran.hizbs
            return divisions
                .filter { matches($0, mode: mode, query: query) }
                .map { row($0, mode: mode, edition: edition) }
        }
    }

    /// La recherche d'une **sourate** — `MainScreens.tsx:31`, première branche.
    ///
    /// Le numéro fait partie de la chaîne cherchée, donc « 1 » trouve la
    /// sourate 1 **et** 10 à 19, 21, 31, … 114 : c'est un `contains`, pas une
    /// égalité. Le filtre est testé **après** la recherche, comme dans
    /// l'original, où les deux sont joints par `&&`.
    static func matches(_ surah: Surah, query: String, filter: Filter) -> Bool {
        let haystack = "\(surah.number) \(surah.name) \(surah.meaning ?? "") \(surah.arabic ?? "")"
        // Une recherche VIDE ramène tout : `''.includes('')` vaut `true` en
        // JavaScript, alors que `"abc".contains("")` vaut **false** en Swift. Sans
        // ce garde, l'écran s'ouvrait sur une liste vide — la recherche part
        // toujours vide, donc c'était le cas NORMAL, pas un cas limite. Trouvé
        // par l'intégration continue, pas par le banc : un banc qui relit le
        // source ne voit pas ce que le langage fait de ce qu'il lit.
        guard query.isEmpty || haystack.lowercased().contains(query.lowercased()) else { return false }
        switch filter {
        case .all: return true
        case .meccan: return surah.isMeccan ?? false
        case .medinan: return !(surah.isMeccan ?? false)
        }
    }

    /// La recherche d'une **division** — `MainScreens.tsx:31`, seconde branche.
    ///
    /// Trois champs, et aucun n'est la signification ni l'arabe. Le nom de
    /// sourate est celui du **premier** verset de la division
    /// (`surahs[verseAt(d.start).surah - 1].name`), pas de sa fin.
    ///
    /// Le filtre n'est **pas** appliqué : l'original ne le teste pas dans cette
    /// branche. Chercher « Mecquoise » dans la vue « Juz’ » ne filtre donc rien —
    /// la chaîne n'est même pas dans les champs cherchés.
    static func matches(_ division: Division, mode: Mode, query: String) -> Bool {
        let surahName = Quran.surahs[Quran.verseAt(division.start).surah - 1].name
        let haystack = "\(division.number) \(mode.label) \(surahName)"
        // Même garde que pour une sourate, et pour la même raison : sans elle, la
        // vue « Juz’ » s'ouvre vide, `contains("")` étant faux en Swift.
        return query.isEmpty || haystack.lowercased().contains(query.lowercased())
    }

    static func row(_ surah: Surah, mode: Mode) -> Row {
        Row(
            id: "\(mode.label)-\(surah.number)",
            kind: .surah,
            number: surah.number,
            name: surah.name,
            meaning: surah.meaning ?? "",
            arabic: surah.arabic ?? "",
            isMeccan: surah.isMeccan ?? false,
            count: surah.count,
            start: surah.start,
            end: surah.end
        )
    }

    /// Une division — `MainScreens.tsx:31`, seconde branche.
    ///
    /// Quatre champs sont **écrasés** après l'étalement de `d` : le nom, la
    /// signification, l'arabe (vidé) et le nombre de versets. `isMeccan` est
    /// posé à `false` — sans effet visible, puisque le badge d'origine n'est
    /// rendu que pour `kind === 'surah'`, mais c'est ce que l'original écrit.
    static func row(_ division: Division, mode: Mode, edition: QuranEdition) -> Row {
        Row(
            id: "\(mode.label)-\(division.number)",
            kind: .division,
            number: division.number,
            name: "\(mode.label) \(division.number)",
            meaning: pageSpan(division, edition: edition),
            arabic: "",
            isMeccan: false,
            count: division.end - division.start + 1,
            start: division.start,
            end: division.end
        )
    }

    // MARK: - Les pages d'une division

    /// « Pages X – Y ».
    ///
    /// Le séparateur est un **cadratin** (U+2013) entouré de deux espaces —
    /// pas un trait d'union, et pas un tiret demi-cadratin. Un œil ne fait pas
    /// la différence dans un écran ; un `grep` la fait.
    public static func pageSpan(_ division: Division, edition: QuranEdition) -> String {
        "Pages \(page(division.start, edition: edition)) – \(page(division.end, edition: edition))"
    }

    /// `studyPage` (`src/core/studyProgress.ts:8`) : la page d'un verset dans
    /// l'édition donnée.
    ///
    /// C'est `QuranSourceNavigation.versePage` **sans page connue** — la même
    /// fonction que `AppViewModel.resumeBookmark` emploie. Le repli `?? 1`
    /// reproduit `pages[0] ?? 1` de `zipVersePage` : une division dont le
    /// premier verset n'est indexé nulle part ouvre la page 1.
    public static func page(_ verseID: Int, edition: QuranEdition) -> Int {
        QuranSourceNavigation.versePage(edition, verseID: verseID) ?? 1
    }

    // MARK: - « J'ai appris jusqu'à »

    /// Le libellé de la carte de progression — `MainScreens.tsx:30` et `:32`.
    ///
    /// `memorizedIds` retient `perfect` et `review` (`program.ts:138`), et
    /// l'original prend le **plus grand** identifiant (`Math.max(...known)`),
    /// pas le plus récemment validé. `AppState.memorizedIDs` est trié croissant,
    /// donc `.last` est ce maximum — et c'est une autre règle que « le dernier
    /// appris », qui aurait demandé `memorizedAt`.
    public static func lastLearned(_ state: AppState) -> String {
        guard let last = state.memorizedIDs.last else { return noVerseValidated }
        let verse = Quran.verseAt(last)
        return "\(Quran.surahs[verse.surah - 1].name) • verset \(verse.ayah)"
    }

    // MARK: - Les deux actions de la liste

    /// Le verset sur lequel ouvre « Dernière lecture »
    /// (`MainScreens.tsx:33`) : `state.lastRead?.verseId`, ou le verset 1.
    public static func lastReadVerse(_ state: AppState) -> Int {
        state.lastRead?.verseId ?? 1
    }

    /// L'édition qu'écrit la carte de pied « Coran avec règles de Tajwid ».
    public static let tajweedEdition: QuranEdition = .coranTest

    /// La plage qu'ouvre cette carte — `pageRange(state.reader?.testPage ?? 1)`.
    ///
    /// `pageRange` est la pagination du **moushaf**, pas `studyPage` : c'est ce
    /// que fait l'original, qui passe ensuite cette plage à `openReader`.
    public static func tajweedRange(_ state: AppState) -> VerseRange {
        Quran.pageRange(state.reader?.testPage ?? 1) ?? VerseRange(start: 1, end: 1)
    }

    // MARK: - Les textes

    public static let heroTitle = "Le Coran"

    /// Le sous-titre du héros — trois variantes (`MainScreens.tsx:32`).
    ///
    /// Le séparateur est une **puce** (U+2022), pas le point médian (U+00B7) que
    /// porte le libellé de position des marque-pages. Les guillemets de
    /// « Hafs ‘an ‘Âsim » sont des guillemets simples **ouvrants** (U+2018) :
    /// l'original n'a jamais de fermant, faute d'espace.
    public static func heroSubtitle(_ mode: Mode) -> String {
        switch mode {
        case .liste: return "Mushaf de Médine • Hafs ‘an ‘Âsim • 604 pages"
        case .juz: return "Liste des Juz’ • 30 parties"
        case .hizb: return "Liste des Hizb • 60 parties"
        }
    }

    public static let learnedPrefix = "J’ai appris jusqu’à :"
    public static let noVerseValidated = "Aucun verset validé"
    public static let editKnowledge = "Modifier mes connaissances"
    public static let knowledgeAlertTitle = "Mes connaissances"
    public static let knowledgeAlertBody =
        "Modifie tes connaissances depuis ton objectif dans Programme."

    public static let searchSurah = "Rechercher une sourate"

    /// Le texte d'invite du champ — `MainScreens.tsx:32`. « Rechercher un Juz’ »
    /// porte l'apostrophe typographique, comme le libellé de la vue.
    public static func searchPlaceholder(_ mode: Mode) -> String {
        mode == .liste ? searchSurah : "Rechercher un \(mode.label)"
    }

    public static let filterButton = "Filtrer les sourates"
    public static let filterAlertMessage = "Lieu de révélation"
    public static let filterCancel = "Annuler"

    public static func filterLabel(_ filter: Filter) -> String {
        switch filter {
        case .all: return "Toutes"
        case .meccan: return "Mecquoises"
        case .medinan: return "Médinoises"
        }
    }

    public static func originBadge(isMeccan: Bool) -> String {
        isMeccan ? "Mecquoise" : "Médinoise"
    }

    /// Le nombre de versets — `MainScreens.tsx:33`.
    ///
    /// Toujours au pluriel, y compris pour un : l'original écrit
    /// `` `${item.count} versets` `` sans condition. Aucune division n'a un seul
    /// verset (le plus petit hizb en compte 48), donc le cas ne se produit pas —
    /// mais le porter tel quel évite d'inventer une règle que l'original n'a pas.
    public static func verseCount(_ count: Int) -> String {
        "\(count) versets"
    }

    public static let emptyState = "Aucun résultat."
    public static let tajweedTitle = "Coran avec règles de Tajwid"
    public static let tajweedSubtitle =
        "Organisation par couleurs pour faciliter votre lecture et votre apprentissage."
    public static let lastReadButton = "Dernière lecture"

    /// L'étiquette d'accessibilité d'une ligne — `MainScreens.tsx:33` :
    /// `` `Ouvrir ${item.name}` ``.
    public static func openLabel(_ name: String) -> String {
        "Ouvrir \(name)"
    }
}
