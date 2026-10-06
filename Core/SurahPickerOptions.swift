// SurahPickerOptions.swift
// Les règles du sélecteur de sourate. Port de `src/SurahPicker.tsx` (18 lignes).
//
// CE QUE CE FICHIER PORTE, ET CE QU'IL NE PORTE PAS
//   Trois règles seulement, parce que l'original n'en a que trois :
//
//   1. LA PAGE VALIDE — `goPage` (`:11`) :
//        const page = Number(pageText);
//        if (!Number.isInteger(page) || page < 1 || page > 604) {
//          Alert.alert('Page invalide', 'Choisis une page entre 1 et 604.');
//          return;
//        }
//      Trois refus, et **un quatrième qui ne se voit pas** : `Number('')`
//      vaut `0`, `Number(' 12 ')` vaut `12`, et `Number('3.5')` vaut `3.5` —
//      `Number.isInteger(3.5)` est faux, donc refusé. Swift n'a pas de
//      coercition de chaîne : `Int("3.5")` rend `nil`, et c'est le même refus
//      par un autre chemin. Le portage passe donc par `Int(...)` **et** par
//      l'intervalle, jamais par un `Double` tronqué.
//
//      `Number.isInteger` est faux pour `NaN` et `Infinity` : `Int("nan")` et
//      `Int("inf")` rendent `nil` aussi. L'accord tient sur toute la classe.
//
//   2. LA PAGE DE DÉPART — `initialScrollIndex={Math.max(0, currentSurah-1)}`
//      (`:15`). C'est la sourate **1-basée** de l'original ramenée à un indice
//      **0-basé**. Le `Math.max(0, …)` n'est pas décoratif : `currentSurah`
//      peut valoir `0` (aucune sourate choisie), et l'indice vaudrait alors
//      `-1` — que `FlatList` refuse. Swift doit refuser la même valeur.
//
//   3. LA LIGNE DE SAUT N'EXISTE QUE SI `onPage` EST FOURNI — `{onPage&& …}`
//      (`:14`). Ce n'est pas un détail de mise en page : c'est la même
//      **prop optionnelle** que le type de la référence déclare
//      (`onPage?:(page:number)=>void`). Un appelant sans `onPage` ne voit ni
//      le champ ni le bouton.
//
//   Les textes sont ici pour la même raison que dans les autres écrans : un
//   écran de `Features/` n'écrit aucun libellé.

import Foundation

public enum SurahPickerOptions {

    /// Les bornes de la pagination du moushaf — `page<1||page>604`.
    public static let firstPage = 1
    public static let lastPage = 604

    // MARK: - Textes

    public static let title = "Choisir une sourate"
    public static let subtitle = "Les 114 sourates du Coran"
    public static let closeTitle = "Fermer"
    public static let pageFieldPlaceholder = "Page 1 à 604"
    public static let pageSubmitTitle = "Aller à la page"
    public static let invalidPageTitle = "Page invalide"
    public static let invalidPageMessage = "Choisis une page entre 1 et 604."

    /// Le libellé d'une ligne : `« {count} versets »`.
    public static func verseCountLabel(_ count: Int) -> String { "\(count) versets" }

    /// L'étiquette d'accessibilité : `` `${item.number}. ${item.name}` ``.
    public static func accessibilityLabel(number: Int, name: String) -> String {
        "\(number). \(name)"
    }

    // MARK: - La page saisie

    /// Ce que `goPage` décide : une page, ou un refus.
    ///
    /// POURQUOI UN RÉSULTAT ET NON UN `Int?`
    ///   Le refus de l'original a **deux** effets : il ne navigue pas, et il
    ///   montre une alerte. Un `Int?` confondrait « refusé » et « rien à
    ///   faire » ; le cas nommé dit lequel des deux, et l'écran n'a plus qu'à
    ///   obéir.
    public enum PageOutcome: Equatable, Sendable {
        case go(Int)
        case refused
    }

    /// Reproduit `Number(text)` suivi du prédicat de `goPage`.
    ///
    /// MESURÉ SUR L'ORIGINAL, PAS SUPPOSÉ
    ///   `Number(t)` n'est pas `parseInt`. Relevé sur dix-neuf saisies :
    ///
    ///     ""     → 0     refus (0 < 1)        " 12 "  → 12   accepté
    ///     " "    → 0     refus                 "abc"   → NaN  refus
    ///     "0"    → 0     refus                 "12abc" → NaN  refus
    ///     "-5"   → -5    refus                 "nan"   → NaN  refus
    ///     "605"  → 605   refus (> 604)         "inf"   → NaN  refus
    ///     "3,5"  → NaN   refus                 "+5"    → 5    accepté
    ///     "3.5"  → 3.5   refus (non entier)    "0007"  → 7    accepté
    ///     "1e2"  → 100   accepté               "604.0" → 604  accepté
    ///     "0x10" → 16    accepté
    ///
    /// DEUX DIVERGENCES, ET ELLES SONT HORS D'ATTEINTE
    ///   `Int("1e2")` et `Int("0x10")` rendent `nil` en Swift : le portage
    ///   refuse ce que l'original accepte. La divergence est **réelle** et
    ///   **injoignable** : le champ porte `keyboardType="number-pad"`
    ///   (`SurahPicker.tsx:14`), un pavé qui n'offre que des chiffres — ni `e`,
    ///   ni `x`, ni `.`, ni `,`, ni `+`, ni `-`. Aucune de ces cinq saisies ne
    ///   peut sortir du clavier. Un `Int` nu refuse par ailleurs `"3.5"` comme
    ///   `Number.isInteger` le refuse : l'accord tient sur tout ce qui est
    ///   atteignable.
    ///
    ///   Ce qui EST atteignable et se teste : `""`, `" "`, `"0"`, `"605"`,
    ///   `" 12 "`, `"0007"`, et les non-chiffres collés (une saisie vide puis un
    ///   caractère reste possible par collage). Tous tombent juste.
    public static func page(from text: String) -> PageOutcome {
        // `Number('  12  ')` vaut `12` : l'original tolère les espaces autour.
        // `Int(_:)` de Swift ne les tolère pas — on les retire donc avant.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = Int(trimmed) else { return .refused }
        guard page >= firstPage, page <= lastPage else { return .refused }
        return .go(page)
    }

    // MARK: - L'indice de départ

    /// `Math.max(0, currentSurah-1)` — l'indice 0-basé de la ligne à montrer.
    ///
    /// Le `max` est **le** point : `currentSurah` valant `0` rendrait `-1`.
    public static func initialScrollIndex(currentSurah: Int) -> Int {
        max(0, currentSurah - 1)
    }

    // MARK: - La ligne de saut

    /// `{onPage && …}` — la ligne n'existe que si l'appelant sait naviguer.
    public static func showsPageJump(hasOnPage: Bool) -> Bool { hasOnPage }

    // MARK: - L'état initial du champ

    /// `useState(String(currentPage ?? 1))` (`:9`) **et** l'effet d'ouverture
    /// (`:10`) : `if (visible) setPageText(String(currentPage ?? 1))`.
    ///
    /// Le champ se **réinitialise à chaque ouverture** sur la page courante —
    /// une saisie abandonnée ne survit pas à la fermeture. C'est la seule
    /// raison d'être de l'effet, et sans lui le champ garderait la dernière
    /// frappe.
    public static func initialPageText(currentPage: Int?) -> String {
        String(currentPage ?? 1)
    }
}
