// QuranSourcesCard.swift
// La carte « Sources du Coran » — les attributions et le lien de l'original.
//
// Correspondance : la carte de `src/App.tsx:350`, dernière de la page
// « Réglages ». Elle ne propose **aucun** choix : c'est un texte d'attribution,
// avec un seul lien sortant vers tanzil.net. C'est la dernière carte de
// l'original qui n'était pas encore portée.
//
// POURQUOI CE FICHIER, ET POURQUOI CE NOM
//   `Features/Settings/SettingsView.swift` énonce la règle du dossier : un écran
//   ne calcule rien et n'écrit aucun libellé. Ces chaînes vivent donc ici, comme
//   les textes des cartes voisines (`AppearanceOptions`, `QuranDisplayOptions`,
//   `NotificationOptions`).
//
//   Le nom dit « la carte », pas « les sources ». Le dépôt de référence a déjà
//   un module `src/core/quranSources.ts`, qui décrit les sources d'IMAGES des
//   pages — et ce portage l'a traduit ailleurs (`Core/VerseBounds.swift:5`,
//   `Services/QuranSourceService.swift`). Les confondre serait une erreur de
//   lecture : `QuranSourcesCard` ne parle que du texte affiché.
//
// CE QUE LA CARTE DIT, ET CE QU'ELLE NE DIT PAS
//   Elle n'est pas décorative : chaque phrase est une obligation ou une réserve
//   de licence, recopiée **sans modification** — c'est le texte lui-même qui le
//   dit (« Texte reproduit sans modification »). Deux détails typographiques de
//   l'original sont conservés tels quels, parce qu'un test les épingle :
//
//     - `juz’` porte une apostrophe courbe FERMANTE (U+2019) ;
//     - `rub‘` porte une apostrophe courbe OUVRANTE (U+2018).
//
//   La seconde est une singularité de l'original — probablement une coquille —
//   mais la corriger ici ferait diverger les deux applications à l'écran pour
//   une raison qui n'appartient à aucune des deux. On la recopie.
//
//   La dernière phrase est une RÉSERVE, pas un fait : « Les toumoun Hafs
//   attendent une validation indépendante. » C'est la même réserve qui rend le
//   rythme `toumoun` indisponible dans ce portage (voir `SettingsView.paceLabel`).
//
// CE QUI N'EST PAS ICI
//   Le texte est affiché en clair, tel quel. Aucune mise en forme, aucune
//   énumération, aucun découpage : l'original écrit **deux** paragraphes et un
//   lien, et cette structure est portée telle quelle par la vue. Découper les
//   attributions en liste serait une décision d'affichage que l'original n'a
//   pas prise.

import Foundation

public enum QuranSourcesCard {

    /// « Sources du Coran » — `App.tsx:350`.
    ///
    /// Le titre est rendu par l'original avec `fontSize:14, fontWeight:'600'` et
    /// la couleur `muted` — plus petit et plus clair que les titres des autres
    /// cartes (`fontWeight:'700'`, couleur de texte). Ce n'est pas un oubli :
    /// la carte est une note de bas de page, pas un réglage. La vue reprend ce
    /// choix ; ce fichier ne porte que la chaîne.
    public static let title = "Sources du Coran"

    /// Le premier paragraphe — attribution du texte coranique.
    ///
    /// Le tiret de « 2007–2021 » est un tiret demi-cadratin (U+2013), comme dans
    /// l'original, et non un trait d'union ASCII.
    public static let textAttribution = "Texte Uthmani Hafs : Tanzil Project, copyright 2007–2021, licence CC BY 3.0. Texte reproduit sans modification."

    /// Le libellé du lien — `App.tsx:350`.
    ///
    /// La flèche finale est U+2197 (« flèche nord-est »), telle quelle.
    public static let linkTitle = "Voir Tanzil et les mises à jour ↗"

    /// L'adresse du lien — `App.tsx:350`, `Linking.openURL('https://tanzil.net')`.
    ///
    /// La chaîne est conservée **en plus** de `linkURL` : c'est elle que le banc
    /// compare au littéral de la référence, sans passer par la normalisation
    /// d'une `URL` (qui ajouterait un « / » final).
    public static let linkURLString = "https://tanzil.net"

    /// L'adresse, résolue une fois.
    ///
    /// Le littéral vient de la référence et le banc le compare à
    /// `App.tsx:350` : une adresse illisible serait une faute de frappe dans
    /// **ce** fichier, pas une donnée utilisateur. Le `!` suit
    /// `Core/AppConfig.swift:38`, qui force de même un littéral constant du
    /// dépôt — même famille de valeur, même garantie.
    public static let linkURL = URL(string: linkURLString)!

    /// Le second paragraphe — les attributions par édition, et la réserve.
    ///
    /// Six sources y sont nommées : Tanzil (Hafs 1405), QPC V4 (polices du
    /// moushaf de Tajwid), cpfair (annotations de la lecture simplifiée, CC BY
    /// 4.0), Rachid Maach (traduction française, version 1.0.3, QuranEnc), et
    /// Quran Meta (divisions juz’, hizb, rub‘). Un test compte ces six noms :
    /// une troncature de la phrase est ainsi visible, alors qu'un texte long
    /// recopié à la main se coupe volontiers sans que rien ne le dise.
    public static let editionAttribution = "Pages Hafs 1405 issues de l’IPA fournie. Moushaf avec règles de Tajwid : polices QPC V4 et pagination originales issues de l’IPA fournie. Lecture simplifiée : annotations de cpfair sous CC BY 4.0 sur texte Tanzil Hafs 2017. Traduction française du sens : Rachid Maach, version 1.0.3, QuranEnc. Divisions juz’, hizb et rub‘ : Quran Meta. Les toumoun Hafs attendent une validation indépendante."
}
