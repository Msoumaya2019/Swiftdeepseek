// KnowledgeEditorView.swift
// « Modifier mes connaissances » — l'écran qui déclare ce qui est déjà appris.
//
// Correspondance : l'étape 0 de l'assistant d'accueil, `src/App.tsx:399-402` —
// « Que connais-tu déjà ? ». C'est ce qu'ouvre le bouton `openKnowledge` de
// `src/App.tsx:325`.
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   La liste des passages partiels vient de `Program.partialKnownRanges`, l'état
//   d'une case de `AppState.isRangeKnown`, les bornes d'une sourate, d'un juz’ ou
//   d'un hizb de `Quran`, et les références lisibles de `Quran.reference`. Aucune
//   borne, aucune liste n'est écrite ici — les trois listes sont construites à
//   partir des tables, pas recopiées.
//
// LES TROIS LISTES, ET POURQUOI ELLES SONT TOUTES LES TROIS LÀ
//   L'original propose les sourates (114), les juz’ (30) et les hizbs (60) : ce
//   sont trois découpages du même Coran, et un utilisateur qui a appris un hizb
//   n'a pas forcément appris les sourates qu'il traverse. Cocher un juz’ marque
//   donc tous ses versets, sans passer par les sourates — c'est `markKnowledge`
//   sur la plage entière, pas une boucle sur les cases voisines.
//
// CE QUI EST CONSERVÉ, ET CE QUI NE L'EST PAS
//   Cocher puis décocher ne laisse pas de trace : `markKnowledge(…, .learning)`
//   efface la date de mémorisation et l'échéance de révision de chaque verset
//   concerné (`src/core/program.ts:106`). Décocher une sourate ne se contente
//   donc pas de la retirer de l'affichage — c'est ce qui permet de corriger une
//   déclaration faite par erreur.

import SwiftUI

struct KnowledgeEditorView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var partSurah = ""
    @State private var partStart = ""
    @State private var partEnd = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                partialSection
                divisionSection(title: "Sourates connues par cœur", entries: surahEntries)
                divisionSection(title: "Juz’ déjà connus", entries: divisionEntries(Quran.juzs, unit: "Juz’"))
                divisionSection(title: "Hizb déjà connus", entries: divisionEntries(Quran.hizbs, unit: "Hizb"))
                if let error {
                    Section { Text(error).foregroundStyle(palette.red) }
                }
            }
            .navigationTitle("Mes connaissances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    // MARK: - Passages partiellement mémorisés

    /// `src/App.tsx:400` — deux champs de versets, un bouton, puis la liste des
    /// passages déjà partiels avec leur bouton de retrait.
    ///
    /// `partialKnownRanges` **exclut** les sourates entières : une sourate sue
    /// par cœur se coche dans la liste des sourates, pas ici. Les deux listes ne
    /// se recouvrent donc jamais.
    @ViewBuilder private var partialSection: some View {
        Section {
            TextField("Numéro de sourate (1–114)", text: $partSurah)
                .keyboardType(.numberPad)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Verset de début", text: $partStart)
                    .keyboardType(.numberPad)
                TextField("Verset de fin", text: $partEnd)
                    .keyboardType(.numberPad)
            }
            Button("Ajouter ce passage") { addPartial() }
            ForEach(Program.partialKnownRanges(model.state), id: \.self) { range in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(Quran.reference(range))
                        .font(.system(size: Theme.Typography.body))
                    Spacer(minLength: Theme.Spacing.sm)
                    Button("Retirer") {
                        model.setKnowledge(range, mastery: .learning)
                    }
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.red)
                }
            }
        } header: {
            Text("Passages partiellement mémorisés")
        } footer: {
            Text(
                "Les connaissances existantes sont conservées. Un passage retiré "
                + "redevient à apprendre."
            )
        }
    }

    /// `addPartial(false)` — `src/App.tsx:369`.
    ///
    /// L'original refuse dès que l'un des trois champs n'est pas un entier
    /// valide (`Number('')` vaut `0`, et `verseId(0, 0)` rend `null`) ou que le
    /// début dépasse la fin. Le message est celui de l'original.
    private func addPartial() {
        guard let surah = Int(partSurah),
              let start = Int(partStart),
              let end = Int(partEnd),
              let first = Quran.verseID(surah: surah, ayah: start),
              let last = Quran.verseID(surah: surah, ayah: end),
              first <= last else {
            error = "Indique une sourate et des versets valides."
            return
        }
        model.setKnowledge(VerseRange(start: first, end: last), mastery: .perfect)
        partSurah = ""
        partStart = ""
        partEnd = ""
        error = nil
    }

    // MARK: - Listes de divisions

    /// Une ligne de case à cocher : le libellé, le sous-titre facultatif, et la
    /// plage que la coche désigne. La plage porte l'identité de la ligne.
    struct Entry: Hashable {
        var label: String
        var subtitle: String?
        var range: VerseRange
    }

    /// Les 114 sourates — libellé « 2. Al-Baqara », sous-titre = la traduction du
    /// nom (`src/App.tsx:400`).
    private var surahEntries: [Entry] {
        Quran.surahs.map { surah in
            Entry(
                label: "\(surah.number). \(surah.name)",
                subtitle: surah.meaning,
                range: VerseRange(start: surah.start, end: surah.end)
            )
        }
    }

    /// « Juz’ 12 » / « Hizb 30 », sans sous-titre (`src/App.tsx:401-402`).
    private func divisionEntries(_ divisions: [Division], unit: String) -> [Entry] {
        divisions.map { division in
            Entry(label: "\(unit) \(division.number)", subtitle: nil, range: Program.range(of: division))
        }
    }

    /// L'état vient de `AppState.isRangeKnown`, la bascule de
    /// `AppViewModel.toggleKnownRange` — qui régénère le programme quand
    /// l'assistant est terminé.
    private func divisionSection(title: String, entries: [Entry]) -> some View {
        Section(title) {
            ForEach(entries, id: \.range) { entry in
                SelectableRow(
                    label: entry.label,
                    subtitle: entry.subtitle,
                    selected: model.state.isRangeKnown(entry.range),
                    style: .multiple
                ) {
                    model.toggleKnownRange(entry.range)
                }
            }
        }
    }
}
