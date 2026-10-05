// TajweedOptions.swift
// L'édition « Lecture simplifiée » : le texte arabe d'un verset, découpé en
// fragments colorés selon la règle de Tajweed qui les gouverne.
//
// Port de `tajweedVerse`, `tajweedSpans` et `tajweedColor`
// (`src/core/readerData.ts:15-40`) et du rendu « verset par verset » de
// `MushafPage.tsx:34-43`.
//
// POURQUOI CE FICHIER EXISTE
//   Les données étaient **déjà** dans le dépôt — `tajweed-text.json` (1 531 274
//   octets), `tajweed-rules.json` (2 755 691), `translation-fr-rashid.json`
//   (1 522 305) — et **aucun** code Swift ne les lisait. L'édition `tajweed`
//   était rangée avec les éditions paginées dans `QuranSourceNavigation`, alors
//   que l'original ne la rend pas comme une page : `MushafPage.tsx:34` la fait
//   passer par le rendu **verset par verset**, celui des cartes de verset.
//
// LA QUESTION QUI DÉCIDE DE TOUT : L'UNITÉ DE COMPTAGE
//   Les `start` / `end` des annotations indexent le texte. En JavaScript,
//   `[...verse.text]` découpe en **points de code**. En Swift, `Array(text)`
//   découpe en **graphèmes** — et une lettre arabe suivie de ses harakat est UN
//   graphème pour plusieurs points de code.
//
//   Mesuré sur les 6 236 versets livrés (`_banc/oracle-tajweed.txt`) :
//   points de code et unités UTF-16 coïncident partout (0 écart), mais points de
//   code et graphèmes diffèrent sur **6 236 versets sur 6 236**. La fin
//   d'annotation la plus grande est **1 171** (verset 2:282, dont le texte porte
//   1 173 points de code et **680** graphèmes) : indexer en `Character`
//   sortirait du tableau, donc **planterait** — sur le plus long verset du
//   Coran, celui qu'on ouvre pour vérifier. Ce fichier indexe donc en
//   `Unicode.Scalar`, jamais autrement.
//
// DEUX PIÈGES DE VÉRITÉ, ET NON DE PRÉSENCE
//   L'original teste des **valeurs**, pas des clés — et une chaîne vide est
//   fausse en JavaScript comme un tableau vide. Swift, lui, distingue `nil` de
//   `""`. Les deux écarts sont mesurés :
//
//   1. `footnotes` est **présent sur les 6 236 lignes** et vaut `""` sur **4 906**
//      d'entre elles. `translation?.footnotes ? <Label> : null`
//      (`MushafPage.tsx:38`) n'affiche donc rien dans ce cas. Un `String?`
//      décodé rendrait `Optional("")`, qu'un `if let` aurait affiché : 4 906
//      notes vides, et un blanc de plus sous chacune. D'où `Translation.footnote`,
//      qui rend `nil` sur `""` — la vérité, pas la présence.
//   2. `annotations` vaut `[]` sur **63** lignes. Un verset sans règle rend
//      **un** fragment nu, pas zéro : la boucle de fusion pousse toujours le
//      premier fragment. Rendre `[]` laisserait la carte sans texte.
//
// CE QUI EST MESURÉ, ET NON SUPPOSÉ
//   `tajweedVerse` : 6 236 versets rendus, 0 ligne absente, 0 discordance entre
//   le texte et les règles — la garde existe, elle ne se déclenche pas.
//   18 règles distinctes, 119 032 fragments sur tout le Moushaf, 160 au maximum
//   pour un verset (2:282), et **63** versets dont tous les fragments sont nus.
//   Traduction : 6 236 lignes, 0 manquante, **1 330** notes véridiques.

import CoreGraphics
import Foundation

public enum TajweedOptions {

    // MARK: - Les données

    /// Une annotation : `end` est **exclusif** (`for i = start; i < end`).
    ///
    /// Mesuré : aucune annotation n'a `start == end` (elle n'écrirait rien),
    /// `start < 0` (l'original écrirait une propriété que sa boucle ne relit
    /// jamais) ni `rule` vide. Les trois gardes de `spans` sont donc des
    /// ceintures, pas des bretelles — elles ne se déclenchent sur aucun des
    /// 119 032 fragments livrés.
    public struct Annotation: Codable, Sendable {
        public let start: Int
        public let end: Int
        public let rule: String
    }

    /// Une ligne de `tajweed-rules.json`.
    public struct Rules: Codable, Sendable {
        public let surah: Int
        public let ayah: Int
        public let annotations: [Annotation]
    }

    /// Une ligne de `translation-fr-rashid.json`.
    ///
    /// `footnotes` est déclaré **optionnel** parce que le décodeur de Swift
    /// accepte l'absence de la clé — mais la clé est toujours là, et vaut `""`
    /// sur 4 906 lignes. C'est `footnote` qu'il faut lire, jamais `footnotes` :
    /// voir l'en-tête.
    public struct Translation: Codable, Sendable {
        public let surah: Int
        public let ayah: Int
        public let translation: String
        public let footnotes: String?

        /// La note à afficher, ou `nil` s'il n'y en a pas.
        ///
        /// Reproduit la **vérité** JavaScript de `MushafPage.tsx:38` :
        /// `translation?.footnotes ? <Label> : null`. Une chaîne vide est
        /// fausse, donc elle ne s'affiche pas — alors que `footnotes` vaut
        /// `""` (non `nil`) sur 4 906 des 6 236 lignes.
        public var footnote: String? {
            guard let text = footnotes, !text.isEmpty else { return nil }
            return text
        }
    }

    /// Un fragment de verset : son texte, et la règle qui le colore — `nil` quand
    /// aucune ne le gouverne. C'est l'unité que l'écran rend.
    public struct Span: Equatable, Sendable {
        public let text: String
        public let rule: String?

        public init(text: String, rule: String?) {
            self.text = text
            self.rule = rule
        }
    }

    /// L'état d'une carte de verset, dans l'ordre où l'original le décide
    /// (`MushafPage.tsx:36`) : `difficult` d'abord, puis `bookmarked`, puis
    /// `playing`, puis `plain`.
    ///
    /// Les **couleurs** appartiennent à l'écran et au thème ; la **décision** est
    /// ici, parce que l'ordre des `?:` est une règle, pas un goût. `.bookmarked`
    /// et `.playing` rendent aujourd'hui la **même** couleur (`colors.selected`) :
    /// c'est ce que dit l'original, et le banc le fixe plutôt que de le
    /// supposer — deux cas distincts qui ne se distinguent pas encore.
    public enum CardState: Equatable, Sendable {
        case difficult
        case bookmarked
        case playing
        case plain

        public static func of(difficult: Bool, bookmarked: Bool, playing: Bool) -> CardState {
            if difficult { return .difficult }
            if bookmarked { return .bookmarked }
            if playing { return .playing }
            return .plain
        }
    }

    // MARK: - Le chargement

    /// Les trois fichiers sont présents et lisibles, langue par langue.
    ///
    /// **Absence tolérée**, à l'inverse des tables de `Quran.load` qui appellent
    /// `fatalError` : sans `meta.json` ou `verses.json` l'application n'a pas de
    /// Coran du tout, alors que sans les données de Tajweed elle doit continuer
    /// à lire le Coran de Médine. Mais le manque ne doit pas être **silencieux** :
    /// un écran qui annonce « Lecture simplifiée » sans ces données ouvrirait des
    /// cartes vides — d'où `isAvailable`, que le menu doit consulter.
    private static let texts: [Verse] = load("tajweed-text")
    private static let rules: [Rules] = load("tajweed-rules")
    private static let translations: [Translation] = load("translation-fr-rashid")

    /// Le texte arabe et ses règles sont chargés — de quoi rendre le mode `ar`.
    public static var hasArabic: Bool {
        !texts.isEmpty && !rules.isEmpty
    }

    /// La traduction est chargée — de quoi rendre le mode `fr`.
    ///
    /// En `fr`, l'original ne calcule **aucun** fragment
    /// (`language==='ar'?tajweedSpans(id):[]`, `MushafPage.tsx:36`) : la
    /// traduction suffit donc à elle seule.
    public static var hasTranslation: Bool {
        !translations.isEmpty
    }

    /// L'édition peut s'afficher **dans les deux langues**.
    public static var isAvailable: Bool {
        hasArabic && hasTranslation
    }

    /// Charge un tableau depuis `Resources/Data`.
    ///
    /// Rend `[]` sur toute défaillance — fichier absent, illisible, JSON
    /// malformé, forme inattendue — au lieu de planter : voir le contrat
    /// d'absence ci-dessus. Le type d'élément est déduit du type déclaré de la
    /// propriété, ce qui évite de répéter `as: [Verse].self` et de se tromper.
    private static func load<Element: Decodable>(_ name: String) -> [Element] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Element].self, from: data) else {
            return []
        }
        return rows
    }

    // MARK: - `tajweedVerse(id)`

    /// Le texte d'un verset et ses annotations.
    ///
    /// La garde est celle de l'original (`readerData.ts:17`) : les deux lignes
    /// doivent exister **et** concorder sur `surah`/`ayah`. Un décalage d'une
    /// seule ligne entre les deux fichiers rendrait le verset — et le rendrait
    /// **silencieusement**, avec les couleurs d'un autre. La borne d'indice est
    /// l'ajout de Swift : JavaScript rend `undefined` sur un indice hors bornes,
    /// Swift sortirait du tableau.
    public static func verse(_ id: Int) -> (text: String, annotations: [Annotation])? {
        guard id >= 1, id <= texts.count, id <= rules.count else { return nil }
        let text = texts[id - 1]
        let row = rules[id - 1]
        guard text.surah == row.surah, text.ayah == row.ayah else { return nil }
        return (text.text, row.annotations)
    }

    /// La traduction française d'un verset — `frenchVerse(id)`.
    ///
    /// Aucune garde de concordance ici, contrairement au Tajweed : l'original
    /// prend la ligne telle quelle (`readerData.ts:14`). Mesuré : 6 236 lignes,
    /// aucune traduction vide.
    public static func translation(_ id: Int) -> Translation? {
        guard id >= 1, id <= translations.count else { return nil }
        return translations[id - 1]
    }

    // MARK: - `tajweedSpans(id)`

    /// Les fragments colorés d'un verset — `tajweedSpans(id)`.
    ///
    /// Trois règles, et chacune est silencieuse :
    ///
    /// 1. l'indexation se fait en **scalaires Unicode** (voir l'en-tête) ;
    /// 2. une annotation écrit de `start` à `end - 1`, et **la dernière écriture
    ///    gagne** quand deux annotations se recouvrent — c'est l'ordre du tableau
    ///    qui décide, pas une priorité de règle ;
    /// 3. deux voisins de **même** règle fusionnent, `nil` compris : un verset
    ///    sans annotation rend donc UN fragment nu, pas un par lettre. Mesuré :
    ///    **63** versets sont dans ce cas (`annotations: []`).
    ///
    /// Une annotation dont la fin dépasse le texte est **tronquée** au lieu
    /// d'être ignorée : c'est ce que fait JavaScript, où `rules[i] = r` au-delà
    /// de la longueur agrandit le tableau — et la boucle de lecture, elle, ne
    /// dépasse jamais. Mesuré : aucune annotation ne dépasse, sur les 6 236
    /// versets (la plus grande fin vaut 1 171 pour un texte de 1 173 scalaires).
    public static func spans(_ id: Int) -> [Span] {
        guard let content = verse(id) else { return [] }
        let scalars = Array(content.text.unicodeScalars)
        var rule: [String?] = [String?](repeating: nil, count: scalars.count)

        for annotation in content.annotations {
            let start = max(0, annotation.start)
            let end = min(annotation.end, scalars.count)
            guard start < end else { continue }
            for index in start..<end { rule[index] = annotation.rule }
        }

        var spans: [Span] = []
        for index in 0..<scalars.count {
            let piece = String(scalars[index])
            if let last = spans.last, last.rule == rule[index] {
                spans[spans.count - 1] = Span(text: last.text + piece, rule: last.rule)
            } else {
                spans.append(Span(text: piece, rule: rule[index]))
            }
        }
        return spans
    }

    // MARK: - `tajweedColor(rule)`

    /// La couleur d'une règle — `tajweedColor(rule: string): string`,
    /// `readerData.ts:20-27`.
    ///
    /// **L'ordre des branches est la règle.** Deux préfixes sont testés avant les
    /// égalités, et une règle nommée autrement tomberait dans la dernière
    /// branche sans que rien ne le dise. Mesuré sur les 18 règles livrées :
    /// 5 par `madd`, 3 par `ikhfa`/`iqlab`, 6 par `idghaam`/`ghunnah`, 1 par
    /// `qalqalah`, 1 par `silent`, et **2** dans le défaut — `hamzat_wasl` et
    /// `lam_shamsiyyah`, les deux plus fréquentes (13 252 et 2 733 annotations).
    ///
    /// Le paramètre est **non optionnel**, comme dans l'original : la couleur du
    /// fragment **nu** n'appartient pas à cette table, elle vient du thème
    /// (`colors.text`). C'est `color(of:textColor:)` qui compose les deux.
    public static func color(_ rule: String) -> String {
        if rule.hasPrefix("madd") { return "#B45375" }
        if rule.hasPrefix("ikhfa") || rule == "iqlab" { return "#3A779B" }
        if rule.hasPrefix("idghaam") || rule == "ghunnah" { return "#6F5FA5" }
        if rule == "qalqalah" { return "#B05E32" }
        if rule == "silent" { return "#A2A2A2" }
        return "#A26C44"
    }

    /// La couleur d'un fragment — `` span.rule ? tajweedColor(span.rule) : colors.text ``
    /// (`MushafPage.tsx:39`). La couleur du texte est **passée** par l'écran :
    /// elle vient du thème actif, que ce fichier ne connaît pas.
    public static func color(of span: Span, textColor: String) -> String {
        guard let rule = span.rule else { return textColor }
        return color(rule)
    }

    /// Les 18 règles livrées, triées par fréquence décroissante — mesuré.
    public static let ruleVocabulary: [(rule: String, annotations: Int)] = [
        ("hamzat_wasl", 13252),
        ("madd_2", 9028),
        ("ikhfa", 5301),
        ("ghunnah", 4946),
        ("madd_246", 4543),
        ("silent", 4174),
        ("idghaam_ghunnah", 3933),
        ("qalqalah", 3834),
        ("madd_munfasil", 3172),
        ("lam_shamsiyyah", 2733),
        ("madd_muttasil", 1997),
        ("idghaam_no_ghunnah", 1035),
        ("idghaam_shafawi", 832),
        ("iqlab", 562),
        ("ikhfa_shafawi", 496),
        ("madd_6", 148),
        ("idghaam_mutanajisayn", 58),
        ("idghaam_mutaqaribayn", 13),
    ]

    // MARK: - La typographie du texte arabe

    /// `MushafPage.tsx:39` : `Math.min(34, Math.max(25, width * .078)) * textScale`.
    ///
    /// Les deux bornes sont des **pixels indépendants de la largeur** : en deçà de
    /// 321 pt de large le texte ne rétrécit plus, au-delà de 436 pt il ne grandit
    /// plus.
    public static func arabicFontSize(width: CGFloat, textScale: CGFloat = 1) -> CGFloat {
        min(34, max(25, width * 0.078)) * textScale
    }

    /// `MushafPage.tsx:39` : `Math.min(62, Math.max(48, width * .145)) * textScale`.
    public static func arabicLineHeight(width: CGFloat, textScale: CGFloat = 1) -> CGFloat {
        min(62, max(48, width * 0.145)) * textScale
    }

    // MARK: - Les textes

    /// Le repère de fin de verset. L'original l'écrit dans un `Text` doré, après
    /// les fragments — et précédé d'une **espace** qui, elle, garde la couleur du
    /// texte (`MushafPage.tsx:39`). D'où les deux constantes : les confondre
    /// peindrait l'espace en doré.
    public static let ornament = "۞"
    public static let ornamentGap = " "

    public static let frenchHeader = "Traduction française du sens des versets"
    public static let frenchFooter = "Traduction du sens : Rachid Maach · QuranEnc"
    public static let arabicFooter = "Tajweed : cpfair, CC BY 4.0 · texte Hafs Tanzil 2017"
    public static let missingTranslation = "Traduction indisponible."

    /// `MushafPage.tsx:35` : `` `Lecture simplifiée · page ${page}` ``.
    public static func arabicHeader(page: Int) -> String {
        "Lecture simplifiée · page \(page)"
    }

    /// `MushafPage.tsx:37` : `` `${surahs[verse.surah-1].name} · verset ${verse.ayah}` ``.
    ///
    /// Aucune garde de borne, comme l'original : un `surah` hors de 1…114 est une
    /// donnée corrompue, et les deux langages échouent alors — JavaScript sur
    /// `undefined.name`, Swift sur l'indice. Ajouter une garde qui rendrait `""`
    /// **divergerait** en silence au lieu d'échouer.
    public static func verseLabel(_ verse: Verse) -> String {
        "\(Quran.surahs[verse.surah - 1].name) · verset \(verse.ayah)"
    }

    /// L'en-tête de la liste : le titre du mode, puis la page.
    public static func header(page: Int, language: ReaderLanguage) -> String {
        language == .french ? frenchHeader : arabicHeader(page: page)
    }

    /// Le pied de la liste : la provenance du texte.
    public static func footer(language: ReaderLanguage) -> String {
        language == .french ? frenchFooter : arabicFooter
    }

    /// La langue d'affichage du lecteur. L'original écrit `language==='ar'` à
    /// chaque fois (`MushafPage.tsx:36,38,39,42`) : c'est la **seule** valeur qui
    /// décide entre le texte arabe coloré et la traduction.
    public enum ReaderLanguage: String, Sendable {
        case arabic = "ar"
        case french = "fr"
    }
}
