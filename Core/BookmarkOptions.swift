// BookmarkOptions.swift
// Les textes de l'écran « Mes marques-pages » — port de `src/BookmarksScreen.tsx`.
//
// POURQUOI CE FICHIER
//   `Features/Quran/BookmarksView.swift` énonce la règle du dossier : un écran ne
//   calcule rien et n'écrit aucun libellé. Ces chaînes vivent donc ici, comme
//   celles des cartes voisines (`QuranSourcesCard`, `QuranDisplayOptions`).
//
// CE QUE L'ÉCRAN DIT, ET CE QU'IL NE DIT PAS
//   La première carte n'est pas décorative : elle énonce la PROMESSE de la
//   fonction — « le verset exact où reprendre ta lecture ». La seconde est
//   l'état vide, et elle nomme le geste : toucher « Marque-page », puis un
//   verset. Un état vide qui dirait seulement « aucun élément » laisserait
//   l'utilisateur sans le geste.
//
//   La phrase de l'alerte est une RÉSERVE, pas une politesse : « Le verset
//   restera disponible dans le Coran. » Elle dit que la suppression porte sur le
//   REPÈRE, jamais sur le texte — ce que le modèle fait vraiment (`Bookmark.delete`
//   pose une marque, il n'efface pas l'entrée).
//
// DEUX DÉTAILS TYPOGRAPHIQUES, MESURÉS
//   - Les guillemets de « Marque-page » sont des chevrons SIMPLES (U+00AB et
//     U+00BB), séparés par des espaces ORDINAIRES. `App.tsx` en utilise ailleurs
//     de plus fins ; ici, non — et un test épingle les octets.
//   - Le séparateur de « Page N · Verset M » est un point médian (U+00B7), et
//     l'espace avant le « ? » de l'alerte est ORDINAIRE (U+0020), non insécable.
//     Les deux sont mesurés dans `BookmarksScreen.tsx`, et un test les épingle.
//
// CE QUI N'EST PAS ICI
//   Les noms d'icônes, les tailles, les couleurs, l'ordre des éléments : c'est la
//   « chrome » de l'écran, et elle appartient à la vue. Les noms de sourates non
//   plus : ils viennent de `Quran.surahAt(_:)`, comme partout ailleurs.

import Foundation

public enum BookmarkOptions {

    /// « Mes marques-pages » — le titre de l'écran.
    public static let screenTitle = "Mes marques-pages"

    /// « Retrouve facilement tes passages enregistrés » — le sous-titre.
    public static let screenSubtitle = "Retrouve facilement tes passages enregistrés"

    /// La carte d'explication, en tête de liste.
    public static let explanation = "Chaque marque-page conserve le verset exact où reprendre ta lecture."

    /// L'état vide — il nomme le geste, sans quoi il ne dit rien.
    public static let emptyState = "Aucun marque-page enregistré. Touche « Marque-page », puis un verset sur la page."

    /// Le badge de l'entrée la plus récemment REPRISE (`lastUsedAt`), pas la plus
    /// récemment créée : l'écran marque celle que `Bookmark.use` a datée en dernier.
    public static let lastUsedBadge = "Dernière reprise"

    /// « Reprendre » — le bouton qui ramène le lecteur sur la page du verset.
    public static let resumeAction = "Reprendre"

    /// Le libellé d'accessibilité du bouton de retour.
    public static let backLabel = "Retour à la lecture"

    /// L'alerte de suppression — trois textes, comme `Alert.alert` de l'original.
    public static let deleteConfirmTitle = "Supprimer ce marque-page ?"
    public static let deleteConfirmDetail = "Le verset restera disponible dans le Coran."
    public static let deleteCancel = "Annuler"
    public static let deleteConfirm = "Supprimer"

    /// « Page N · Verset M » — la position affichée sous le nom de la sourate.
    ///
    /// La page est celle de la SOURCE affichée, quand l'entrée la connaît
    /// (`sourcePages`) ; l'appelant décide, ce fichier ne porte que le gabarit.
    public static func position(page: Int, ayah: Int) -> String {
        "Page \(page) · Verset \(ayah)"
    }

    /// Le libellé d'accessibilité du bouton de suppression — il NOMME l'entrée
    /// visée, sans quoi deux boutons voisins se ressemblent pour un lecteur d'écran.
    public static func deleteLabel(surah: String, ayah: Int) -> String {
        "Supprimer le marque-page \(surah) verset \(ayah)"
    }
}
