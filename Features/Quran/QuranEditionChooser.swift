// QuranEditionChooser.swift
// Les quatre éditions du Coran, et ce qu'un appui déclenche.
//
// Correspondance : les `Choice` de la carte « Affichage du Coran »
// (`src/App.tsx:330`), les `Button` du sélecteur modal (`src/App.tsx:515`), et
// `DownloadSourceChoice` (`src/ui/QuranDownload.tsx:8`).
//
// POURQUOI CE COMPOSANT EXISTE
//   L'original propose les mêmes quatre éditions à DEUX endroits — la carte
//   « Affichage du Coran » des réglages (`src/App.tsx:330`) et le sélecteur
//   modal du **lecteur** (`src/App.tsx:515`) —, et il les écrit deux fois.
//   Cette application en a compté jusqu'à trois : `QuranScreenView`, qui
//   occupait l'onglet Coran avant que celui-ci ne devienne la liste des sourates
//   (`SurahListView`), parcourait `QuranEdition.allCases` et affichait donc
//   **cinq** éditions dans un **autre** ordre, dont `tajweedPages`
//   (« Moushaf Tajwid ») que l'original ne propose nulle part.
//
//   Ici la liste vient de `QuranDisplayOptions.editionOptions`, la décision de
//   `QuranDisplayOptions.choice`, et l'état d'installation de
//   `QuranDisplayOptions.installationStatus`. Ce fichier ne décide donc **rien** :
//   il rend une liste et dispatche sur une décision déjà prise. Les deux écrans
//   restants partagent le même composant, donc la même liste et le même ordre.
//
// CE QUE CE COMPOSANT NE FAIT PAS
//   Il ne démarre aucune installation, n'écrit aucune préférence et n'ouvre
//   aucun lecteur : il appelle celui de ses trois rappels qui correspond à la
//   décision. Les effets restent dans les écrans, qui seuls connaissent le
//   modèle — c'est ce qui permet au sélecteur du lecteur de refermer sa feuille
//   après un choix, et à l'écran de réglages d'en faire autant.

import SwiftUI

struct QuranEditionChooser: View {

    /// La valeur **stockée** de `reader.mushaf`, telle quelle — c'est elle qui
    /// décide de la coche, et non l'édition affichée. Une préférence que cette
    /// version ne sait pas rendre reste donc cochée : l'utilisateur voit ce
    /// qu'il a choisi, pas ce que l'application substitue.
    let stored: String?

    /// Le Coran 1441 est-il installé sur ce téléphone ?
    let coran1441Installed: Bool

    /// Afficher les sous-titres descriptifs.
    ///
    /// Le sélecteur modal de l'original ne les montre pas (`App.tsx:515` rend les
    /// trois premières éditions en `Button` nus) ; la carte de réglages si
    /// (`App.tsx:330`). C'est une différence de présentation, pas de contenu :
    /// les deux listes portent les mêmes quatre entrées dans le même ordre.
    var showsSubtitles: Bool = true

    /// Appelés selon la décision. Les trois sont requis : un écran qui oublierait
    /// d'en brancher un rendrait un appui silencieux, et le défaut serait
    /// invisible — la ligne s'affiche, elle ne réagit simplement pas.
    let onSelect: (QuranEdition) -> Void
    let onInstall: (QuranEdition) -> Void
    let onUnavailable: (QuranEdition) -> Void

    @Environment(\.palette) private var palette

    private var options: [QuranDisplayOptions.EditionOption] {
        QuranDisplayOptions.editionOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            // `ForEach(options)` et non `Array(options.enumerated())` : la liste
            // est identifiée par la clé de chaque édition, et le séparateur se
            // décide en comparant à la dernière. Parcourir les indices
            // demanderait une clé de chemin à travers un élément de tuple —
            // `\.element.id` —, forme que ce dépôt n'emploie nulle part : ses
            // cinq autres `ForEach` énumérés utilisent tous `\.offset`.
            ForEach(options) { option in
                row(option)
                if option.id != options.last?.id {
                    Divider().foregroundStyle(palette.line)
                }
            }
        }
    }

    // MARK: - Une ligne

    private func row(_ option: QuranDisplayOptions.EditionOption) -> some View {
        Button {
            // La décision est prise ailleurs ; ici on ne fait que la router.
            switch QuranDisplayOptions.choice(
                for: option.edition,
                coran1441Installed: coran1441Installed
            ) {
            case .select: onSelect(option.edition)
            case .install: onInstall(option.edition)
            case .unavailable: onUnavailable(option.edition)
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        // Une édition que cette version ne sait pas rendre est
                        // grisée : l'original, lui, la laisse en couleur pleine
                        // parce qu'il sait toutes les rendre.
                        .foregroundStyle(option.edition.isAvailable ? palette.text : palette.muted)
                    if showsSubtitles {
                        Text(option.subtitle)
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(palette.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                if let status = QuranDisplayOptions.installationStatus(
                    for: option.edition,
                    coran1441Installed: coran1441Installed
                ) {
                    Text(status)
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(palette.muted)
                }
                if option.id == stored {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        .foregroundStyle(palette.green)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option.id == stored ? [.isSelected] : [])
    }
}
