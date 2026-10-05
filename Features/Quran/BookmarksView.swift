// BookmarksView.swift
// « Mes marques-pages » — port de `src/BookmarksScreen.tsx`.
//
// Correspondance : l'écran que `App.tsx:492` rend à la place du lecteur quand
// `bookmarksOpen` est vrai. Il liste les marques-pages VISIBLES, permet d'en
// supprimer une, et de REPRENDRE la lecture sur la page du verset.
//
// CE QUE CET ÉCRAN NE DÉCIDE PAS
//   Aucun libellé, aucune borne, aucune date : tout vient de `BookmarkOptions`
//   pour les textes, de `Bookmark` pour les données, de `Quran` pour les noms de
//   sourates et le texte des versets. La seule chose écrite ici est sa propre
//   « chrome » — les icônes, les tailles, l'ordre des éléments —, comme
//   `ProfileView` écrit la sienne.
//
// DEUX RÈGLES SILENCIEUSES, PORTÉES TELLES QUELLES
//
//   1. LE BADGE « Dernière reprise » NE SUIT PAS L'ORDRE DE LA LISTE.
//      `BookmarksScreen.tsx:10` le calcule sur `lastUsedAt` SEUL — en écartant
//      les entrées qui n'en portent pas —, alors que `visibleBookmarks` trie sur
//      `(lastUsedAt ?? updatedAt)`. Les deux listes ne sont donc pas dans le même
//      ordre, et une marque-page jamais reprise ne reçoit jamais le badge. Un
//      portage « cohérent » qui réutiliserait la première entrée de la liste
//      poserait le badge sur la mauvaise, dès la deuxième reprise.
//
//   2. LA PAGE AFFICHÉE EST CELLE QUE « REPRENDRE » OUVRIRA.
//      Elle vient de `QuranSourceNavigation.versePage` — le portage de
//      `sourceVersePage` —, la MÊME fonction que celle qu'appelle la reprise.
//      C'est la seule façon d'être sûr que la page annoncée sous le nom de la
//      sourate est bien celle que le bouton ouvre : deux calculs divergeraient,
//      et l'écart serait silencieux — l'écran afficherait une page, le bouton en
//      ouvrirait une autre.
//
// CE QUI N'EST PAS MONTÉ
//   La suppression est une suppression DOUCE, et l'écran le dit à sa manière :
//   la phrase de l'alerte promet que « le verset restera disponible dans le
//   Coran », ce que `Bookmark.delete` fait vraiment — il pose une marque
//   `deletedAt`, sans effacer l'entrée, pour qu'un autre appareil encore hors
//   ligne ne puisse pas la ressusciter.

import SwiftUI

struct BookmarksView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// L'édition **affichée** par l'appelant. C'est elle qui décide quelle page
    /// de source montrer — et non celle qui est enregistrée : les deux diffèrent
    /// quand le lecteur substitue une édition qu'il ne sait pas rendre
    /// (`QuranEdition.displayed(stored:)`).
    let edition: QuranEdition

    /// « Reprendre » — l'appelant seul sait où aller : le lecteur plein écran
    /// depuis le lecteur, la feuille de lecture depuis l'onglet Coran.
    let onResume: (Int) -> Void

    /// L'entrée dont la suppression attend confirmation. `nil` : aucune alerte.
    /// C'est un état LOCAL, comme `bookmarkMode` l'est dans l'original.
    @State private var pendingDeletion: VerseBookmark?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    explanationCard
                    if items.isEmpty {
                        emptyCard
                    }
                    ForEach(items, id: \.verseId) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
        }
        .background(palette.cream)
        .alert(
            BookmarkOptions.deleteConfirmTitle,
            isPresented: deletionBinding,
            presenting: pendingDeletion
        ) { item in
            Button(BookmarkOptions.deleteCancel, role: .cancel) { pendingDeletion = nil }
            Button(BookmarkOptions.deleteConfirm, role: .destructive) {
                model.update { Bookmark.delete($0, verseID: item.verseId) }
                pendingDeletion = nil
            }
        } message: { _ in
            Text(BookmarkOptions.deleteConfirmDetail)
        }
    }

    // MARK: - L'en-tête

    /// Le retour, le titre et le sous-titre — la « chrome » de l'écran.
    ///
    /// Le chevron est écrit ici plutôt que laissé à une barre de navigation :
    /// l'original fait de cet écran un plein écran qui REMPLACE le lecteur, avec
    /// son propre en-tête. Une barre de navigation aurait rendu `backLabel`
    /// inatteignable, alors que son libellé d'accessibilité est explicite dans
    /// l'original (« Retour à la lecture » — pas « Retour »).
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.green)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BookmarkOptions.backLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(BookmarkOptions.screenTitle)
                    .font(.system(size: Theme.Typography.screen, weight: .semibold))
                    .foregroundStyle(palette.green)
                Text(BookmarkOptions.screenSubtitle)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Les deux cartes de tête

    /// La carte d'explication — fond `soft`, comme l'original (`colors.soft`).
    private var explanationCard: some View {
        Card(tint: palette.soft) {
            Text(BookmarkOptions.explanation)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// L'état vide. Il nomme le geste, sans quoi il ne dit rien.
    private var emptyCard: some View {
        Card {
            Text(BookmarkOptions.emptyState)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Une entrée

    private func row(_ item: VerseBookmark) -> some View {
        let surah = Quran.surahAt(item.verseId)
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bookmark")
                        .foregroundStyle(palette.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(surah.name)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(palette.text)
                        Text(BookmarkOptions.position(page: displayedPage(item), ayah: item.ayah))
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(palette.muted)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    Button {
                        pendingDeletion = item
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(palette.green)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        BookmarkOptions.deleteLabel(surah: surah.name, ayah: item.ayah)
                    )
                }

                if lastUsedID == item.verseId {
                    Text(BookmarkOptions.lastUsedBadge)
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(palette.green)
                        .padding(.top, Theme.Spacing.sm)
                }

                Text(Quran.verseAt(item.verseId).text)
                    .font(.system(size: 23))
                    .lineSpacing(19)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, Theme.Spacing.md)

                CardButton(title: BookmarkOptions.resumeAction) {
                    onResume(item.verseId)
                }
                .padding(.top, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Les données

    /// Les marques-pages VISIBLES, dans l'ordre de l'original : `deletedAt` exclu,
    /// tri décroissant sur `lastUsedAt ?? updatedAt`.
    private var items: [VerseBookmark] {
        Bookmark.visible(model.state)
    }

    /// L'entrée qui porte le badge « Dernière reprise » — `BookmarksScreen.tsx:10`.
    ///
    /// Calculée sur `lastUsedAt` **seul**, en écartant les entrées qui n'en
    /// portent pas : une marque-page jamais reprise ne reçoit jamais le badge, et
    /// si aucune ne l'a été, aucune ne le reçoit. Sur une égalité de date,
    /// `max(by:)` garde le PREMIER élément rencontré — comme le `sort` stable de
    /// JavaScript suivi de `[0]`.
    private var lastUsedID: Int? {
        items
            .filter { $0.lastUsedAt != nil }
            .max { ($0.lastUsedAt ?? "") < ($1.lastUsedAt ?? "") }?
            .verseId
    }

    /// La page montrée pour une entrée — `sourceVersePage`, c'est-à-dire
    /// exactement la fonction que la reprise appelle pour décider où ouvrir.
    ///
    /// Le repli sur `item.page` ne sert que si la page ne peut pas être
    /// déterminée. Pour les deux éditions que ce portage sait rendre, `versePage`
    /// en rend toujours une ; le repli évite seulement d'afficher une page
    /// absente si cela changeait un jour.
    private func displayedPage(_ item: VerseBookmark) -> Int {
        QuranSourceNavigation.versePage(
            edition,
            verseID: item.verseId,
            current: item.sourcePages?[edition.rawValue]
        ) ?? item.page
    }

    /// Le lien entre l'alerte et l'entrée visée.
    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { shown in if !shown { pendingDeletion = nil } }
        )
    }
}
