// QuranDisplayOptions.swift
// L'affichage du Coran — les éditions proposées, les quatre fonds, et les
// règles d'écriture d'un appui.
//
// Correspondance : la carte « Affichage du Coran » de `src/App.tsx:330`, le
// sélecteur modal de `src/App.tsx:515`, `src/ui/QuranDownload.tsx:8`
// (`DownloadSourceChoice`) et `src/core/readerAppearance.ts:1-8`.
//
// POURQUOI CE FICHIER
//   `Features/Settings/SettingsView.swift` énonce la règle du dossier : un écran
//   ne calcule rien. Or l'affichage du Coran porte cinq décisions qui, si elles
//   vivaient dans une vue, divergeraient en silence :
//
//     1. la LISTE des éditions proposées n'est pas `QuranEdition.allCases`. Elle
//        compte **quatre** entrées, dans cet ordre : Coran de Médine, Coran avec
//        règles de Tajwid, Lecture simplifiée, Coran 1441. `tajweedPages`
//        (« Moushaf Tajwid ») n'est proposé par **aucun** des deux écrans de
//        l'original — c'est une clé d'écriture que `migrateReaderState` réécrit
//        vers `coranTest` à chaque chargement (`src/core/program.ts:60`) ;
//     2. un appui sur une édition a TROIS issues, pas deux : refus (édition que
//        cette version ne sait pas rendre), installation (Coran 1441 absent du
//        téléphone), ou sélection. Les confondre ouvrirait un lecteur vide ;
//     3. les trois écritures de l'original ne posent pas le même défaut sur
//        `reader.mushaf` : celle des éditions écrit la valeur choisie, celles du
//        fond et du suivi audio écrivent `state.reader?.mushaf ?? 'coranTest'`
//        (`App.tsx:330`) — si bien qu'un appui sur un fond, sur une installation
//        neuve, ENREGISTRE `coranTest`. C'est surprenant mais c'est le contrat :
//        la réécrire autrement ferait diverger les deux applications ;
//     4. `followAudio` a pour défaut `true`, mais la comparaison de l'original
//        est `!== false` et non `|| true` : un `false` stocké reste `false` ;
//     5. la couleur d'un fond inconnu est celle du PREMIER fond, pas celle du
//        thème (`quranPaperColor`, `readerAppearance.ts:8`).
//
// CE QUI N'EST PAS APPLIQUÉ, ET POURQUOI C'EST DIT
//   La couleur de fond n'est consommée par l'original qu'à un seul endroit :
//   `readerState.background` de `CoranTestScreen`, l'édition rendue par une page
//   HTML dans un WebView avec 607 polices `.woff2` — une chaîne que cette
//   application n'a pas (voir `Services/QuranSourceService.swift`). La
//   préférence est donc **stockée, affichée et vérifiée**, mais elle ne colore
//   encore rien ici. Même raisonnement que pour `state.uiFont`. La stocker est
//   nécessaire : l'utilisateur qui choisit « Sépia » dans React Native doit
//   retrouver son choix dans les deux applications, et réciproquement.

import SwiftUI

public enum QuranDisplayOptions {

    // MARK: - Les éditions proposées, dans l'ordre de l'original

    /// Un choix d'édition tel que les deux écrans de l'original le présentent.
    public struct EditionOption: Identifiable, Equatable, Sendable {
        /// La valeur **stockée** dans `reader.mushaf`.
        public var id: String
        public var label: String
        public var subtitle: String
        public var edition: QuranEdition
    }

    /// Les quatre clés proposées, dans l'ordre de `App.tsx:515` :
    ///
    ///     [{label:'Coran de Médine',mode:'traditional'},
    ///      {label:'Coran avec règles de Tajwid',mode:'coranTest'},
    ///      {label:'Lecture simplifiée',mode:'tajweed'},
    ///      ...zipSources.map(s => ({label: s.label, mode: s.id}))]
    ///
    /// `zipSources` vaut `[{id:'coran_1441', label:'Coran 1441'}]`
    /// (`src/core/quranSources.ts:5`). La carte de réglages (`App.tsx:330`)
    /// énumère exactement les mêmes quatre entrées, dans le même ordre : les
    /// deux écrans de l'original s'accordent, et cette liste est ce qui les
    /// tient d'accord ici.
    public static let editionKeys: [String] = [
        "traditional", "coranTest", "tajweed", "coran_1441"
    ]

    /// Les sous-titres. Ceux des trois `Choice` viennent de `App.tsx:330` ;
    /// celui du Coran 1441 de `QuranDownload.tsx:8`.
    ///
    /// Le sélecteur modal (`App.tsx:515`) n'affiche pas les trois premiers — il
    /// les rend en `Button` nus — mais le texte est le même : c'est un choix de
    /// présentation, pas une seconde vérité.
    public static let editionSubtitles: [String: String] = [
        "traditional": "Le Coran traditionnel, avec sa mise en page classique.",
        "coranTest": "Moushaf avec règles de Tajwid en couleur, affichage immersif et suivi audio verset par verset.",
        "tajweed": "Lecture verset par verset, avec les règles de Tajweed en couleur.",
        "coran_1441": "Pages originales · téléchargement à la demande · lecture hors connexion"
    ]

    /// Les éditions à proposer, dans l'ordre.
    ///
    /// `compactMap` et non `map` : une clé de `editionKeys` qui ne correspondrait
    /// à aucune `QuranEdition` disparaîtrait silencieusement de la liste si l'on
    /// écrivait `QuranEdition(rawValue:)!`. Le banc vérifie que les quatre clés
    /// produisent bien quatre entrées — donc que le `compactMap` ne perd rien.
    public static var editionOptions: [EditionOption] {
        editionKeys.compactMap { key in
            guard let edition = QuranEdition(rawValue: key) else { return nil }
            return EditionOption(
                id: key,
                label: edition.label,
                subtitle: editionSubtitles[key] ?? "",
                edition: edition
            )
        }
    }

    // MARK: - La décision d'un appui sur une édition

    /// Ce qu'un appui déclenche.
    ///
    /// Trois cas, et non deux : un appui sur une édition ne se réduit pas à
    /// « changer la préférence ». Il peut aussi falloir l'**installer** — ses
    /// pages ne sont pas sur le téléphone —, ou la **refuser**, parce que cette
    /// version ne sait pas la rendre. `QuranEditionChooser` route les trois, et
    /// chaque écran les traduit en effets.
    public enum EditionChoice: Equatable, Sendable {
        /// Cette version ne sait pas rendre l'édition — on refuse, en le disant.
        case unavailable
        /// L'édition est connue mais ses pages ne sont pas sur le téléphone :
        /// on lance l'installation, on ne change PAS la préférence.
        case install
        /// On change la préférence.
        case select
    }

    /// La décision, isolée de ses effets.
    ///
    /// Elle est **pure** : elle ne démarre rien, n'écrit rien, et ne consulte
    /// que ce qu'on lui donne. C'est ce qui permet aux deux écrans (l'onglet
    /// Coran et les réglages) de partager une seule décision au lieu de la
    /// recopier — et à un banc de l'éprouver sans appareil.
    ///
    /// POURQUOI `.install` NE CHANGE PAS LA PRÉFÉRENCE
    ///   `QuranDownload.tsx:8` fait `if(quranDownloaded()) onSelect(); else
    ///   setExpanded(true)` : tant que les pages ne sont pas là, on ouvre
    ///   l'installateur et on **n'appelle pas** `onSelect`. Écrire la préférence
    ///   d'abord ouvrirait le lecteur sur une édition dont les 9 060 images
    ///   manquent — c'est-à-dire sur des pages vides. Le choix ne devient
    ///   effectif qu'une fois l'installation prête.
    public static func choice(
        for edition: QuranEdition,
        coran1441Installed: Bool
    ) -> EditionChoice {
        guard edition.isAvailable else { return .unavailable }
        if edition == .coran1441, !coran1441Installed { return .install }
        return .select
    }

    /// Le texte du refus, quand cette version ne sait pas rendre l'édition.
    ///
    /// Il vit ici pour que les deux écrans refusent avec les mêmes mots.
    public static func unavailableNotice(for edition: QuranEdition) -> String {
        "\(edition.label) n'est pas encore disponible dans cette version."
    }

    /// L'état d'installation à afficher à côté d'une édition, ou `nil` quand il
    /// n'y a rien à dire.
    ///
    /// Seul le Coran 1441 s'installe : ses 9 060 images ne sont pas dans le
    /// paquet, alors que les 604 pages du Coran de Médine y sont. Les autres
    /// éditions ne sont pas installables — elles sont soit lisibles tout de
    /// suite, soit absentes de cette version — et n'ont donc aucun état à
    /// montrer.
    ///
    /// C'est une information que l'original ne donne pas sous cette forme : son
    /// `DownloadSourceChoice` (`QuranDownload.tsx:8`) n'affiche l'avancement
    /// qu'**après** avoir été déplié. Ici l'état est visible sur la ligne, sans
    /// ouvrir quoi que ce soit — parce que dans ce portage l'installateur vit
    /// dans l'onglet Coran, pas dans le sélecteur.
    public static func installationStatus(
        for edition: QuranEdition,
        coran1441Installed: Bool
    ) -> String? {
        guard edition == .coran1441, edition.isAvailable else { return nil }
        return coran1441Installed ? "Installé" : "À installer"
    }

    // MARK: - Les quatre fonds

    /// Un fond, tel que `quranPaperOptions` le décrit.
    ///
    /// `hex` est conservé **en plus** de `color` : c'est la chaîne que le banc
    /// compare au fichier de référence. Deux écritures de la même couleur
    /// (`#FAF7F2` et `#faf7f2`) sont indiscernables une fois converties en
    /// `Color`, et l'original n'écrit pas ses couleurs dans la même casse que
    /// ses palettes.
    public struct PaperOption: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var hex: String
        public var color: Color
    }

    /// `quranPaperOptions` — `src/core/readerAppearance.ts:1-6`.
    public static let paperOptions: [PaperOption] = [
        paper("ivory", "Ivoire", "#faf7f2"),
        paper("rose", "Rosé", "#f5e1e7"),
        paper("sand", "Sable", "#e8dcc8"),
        paper("sepia", "Sépia", "#d7c5ad")
    ]

    /// La clé retenue quand aucune n'est stockée — `state.reader?.paper ??
    /// 'ivory'`, écrit quatre fois dans `App.tsx:330`.
    public static let defaultPaperKey = "ivory"

    /// La couleur d'un fond — `quranPaperColor`, `readerAppearance.ts:8` :
    ///
    ///     (quranPaperOptions.find(o => o.key === key) ?? quranPaperOptions[0]).color
    ///
    /// Le repli porte sur la **première entrée**, pas sur une constante : un
    /// fond inconnu — clé d'une version plus ancienne, ou absente — prend la
    /// couleur d'Ivoire. Rendre `nil` laisserait la carte sans fond.
    public static func paperColor(key: String?) -> Color {
        (paperOptions.first { $0.id == key } ?? paperOptions[0]).color
    }

    /// La couleur du LIBELLÉ d'un fond — `'#342a27'`, `App.tsx:330`.
    ///
    /// Elle est écrite en clair dans l'original et n'est PAS `colors.text` : les
    /// quatre fonds sont tous clairs, donc le libellé doit rester sombre quel que
    /// soit le thème. La prendre dans la palette donnerait un libellé illisible
    /// sur les fonds clairs d'un thème sombre.
    public static let paperLabelHex = "#342a27"

    /// La couleur du libellé, résolue une fois.
    public static var paperLabelColor: Color {
        Theme.color(hexString: paperLabelHex) ?? .black
    }

    /// Les mesures du sélecteur de fond — `App.tsx:330`.
    public enum Paper {
        /// `width: '47%'` — la largeur MINIMALE d'un fond, dans une ligne
        /// `flexWrap` avec `flexGrow: 1` et un espacement de 8.
        ///
        /// Sa fonction est de forcer **deux fonds par ligne** : à 47 %, un
        /// troisième élément ne tient pas dans les 100 %, donc il passe à la
        /// ligne. `flexGrow` les étire ensuite, si bien que la largeur finale
        /// est d'environ la moitié moins l'espacement, et non 47 %.
        ///
        /// La vue obtient le même résultat par une grille à deux colonnes, qui
        /// n'a pas besoin de la fraction — c'est pourquoi ce fichier la déclare
        /// comme la mesure de l'original et que le banc la compare à
        /// `App.tsx:330`, plutôt que de la faire lire à un écran qui l'emploie
        /// autrement.
        public static let widthFraction: CGFloat = 0.47
        public static let minHeight: CGFloat = 58
        public static let cornerRadius: CGFloat = 14
        public static let padding: CGFloat = 12
        /// `borderWidth: selected ? 2 : 1`.
        public static let selectedBorderWidth: CGFloat = 2
        public static let borderWidth: CGFloat = 1
        /// `{option.label} {selected ? '✓' : ''}` — le séparateur est une espace,
        /// y compris quand la coche est absente.
        public static let checkmark = "✓"
    }

    // MARK: - Les textes de la carte

    /// « Affichage du Coran », `App.tsx:330`.
    public static let cardTitle = "Affichage du Coran"
    /// « Choisis la présentation arabe des pages. », `App.tsx:330`.
    public static let cardDetail = "Choisis la présentation arabe des pages."
    /// « Fond du Coran avec règles de Tajwid », `App.tsx:330`.
    public static let paperSectionTitle = "Fond du Coran avec règles de Tajwid"
    /// « Suivre automatiquement la récitation sur la page suivante »,
    /// `App.tsx:330`.
    public static let followAudioLabel = "Suivre automatiquement la récitation sur la page suivante"

    // MARK: - Les règles d'écriture

    /// Le `mushaf` que l'original écrit quand `state.reader` est **absent**.
    ///
    /// C'est le littéral `'coranTest'` de `App.tsx:330` — pas la valeur par
    /// défaut de `defaultState()`, qui est la même chaîne mais pour une autre
    /// raison. Les deux écritures qui le posent sont celles du fond et du suivi
    /// audio ; celle des éditions écrit la valeur choisie, puisqu'elle est
    /// justement en train de choisir une édition.
    public static let defaultMushafWhenReaderIsMissing = "coranTest"

    /// `followAudio` a pour défaut `true` : l'original compare `!== false`, ce
    /// qui rend `true` pour une valeur absente ET pour `true`, mais `false` pour
    /// un `false` stocké.
    private static func followAudio(_ reader: ReaderPreferences?) -> Bool {
        reader?.followAudio ?? true
    }

    /// Écrit le choix d'une édition — `App.tsx:330` et `App.tsx:458` :
    ///
    ///     touch({...state, reader:{...state.reader, mushaf: <choix>,
    ///                                followAudio: state.reader?.followAudio !== false}})
    ///
    /// Le `touch` de l'original n'est pas refait ici : dans ce portage, **toute**
    /// écriture passe par `AppStateRepository.mutate`, qui applique
    /// `Program.touch` (`Repositories/AppStateRepository.swift:113`). Le refaire
    /// ici serait un second `touch` sur le même document — même résultat, deux
    /// endroits qui décident de l'horodatage.
    public static func settingEdition(_ state: AppState, _ edition: QuranEdition) -> AppState {
        var next = state
        var reader = next.reader
            ?? ReaderPreferences(mushaf: edition.rawValue, followAudio: true)
        reader.mushaf = edition.rawValue
        reader.followAudio = followAudio(next.reader)
        next.reader = reader
        return next
    }

    /// Écrit le fond choisi — `App.tsx:330` :
    ///
    ///     touch({...state, reader:{...state.reader,
    ///       mushaf: state.reader?.mushaf ?? 'coranTest',
    ///       followAudio: state.reader?.followAudio !== false,
    ///       paper: option.key}})
    ///
    /// `testPage` et les autres clés du lecteur sont conservées : l'original
    /// étale `state.reader`, il ne le remplace pas.
    public static func settingPaper(_ state: AppState, _ paper: String) -> AppState {
        var next = state
        let mushaf = next.reader?.mushaf ?? defaultMushafWhenReaderIsMissing
        var reader = next.reader ?? ReaderPreferences(mushaf: mushaf, followAudio: true)
        reader.mushaf = mushaf
        reader.followAudio = followAudio(next.reader)
        reader.paper = paper
        next.reader = reader
        return next
    }

    /// Écrit le suivi audio — `App.tsx:330` :
    ///
    ///     touch({...state, reader:{...state.reader,
    ///       mushaf: state.reader?.mushaf ?? 'coranTest', followAudio: value}})
    ///
    /// Ici `followAudio` est écrit tel quel : c'est la seule des trois écritures
    /// qui puisse poser `false`.
    public static func settingFollowAudio(_ state: AppState, _ value: Bool) -> AppState {
        var next = state
        let mushaf = next.reader?.mushaf ?? defaultMushafWhenReaderIsMissing
        var reader = next.reader ?? ReaderPreferences(mushaf: mushaf, followAudio: value)
        reader.mushaf = mushaf
        reader.followAudio = value
        next.reader = reader
        return next
    }

    /// Le fond affiché comme coché — `state.reader?.paper ?? 'ivory'`.
    public static func selectedPaper(stored: String?) -> String {
        stored ?? defaultPaperKey
    }

    // MARK: - Construction de la table des fonds

    /// Le littéral hexadécimal vient de la référence ; un hexadécimal illisible
    /// serait une faute de frappe dans **ce** fichier, pas une donnée
    /// utilisateur — le banc compare les quatre chaînes à `readerAppearance.ts`,
    /// donc une faute ne peut pas passer. Le repli sur `.clear` n'est là que
    /// pour éviter un `!` qui ferait planter l'application au chargement.
    private static func paper(_ key: String, _ label: String, _ hex: String) -> PaperOption {
        PaperOption(id: key, label: label, hex: hex, color: Theme.color(hexString: hex) ?? .clear)
    }
}
