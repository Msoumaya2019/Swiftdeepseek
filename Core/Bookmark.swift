// Bookmark.swift
// Marques-pages — port de `src/core/bookmarks.ts`.
//
// Point de compatibilité : la suppression laisse une marque (`deletedAt`) au lieu
// d'effacer l'entrée. Sans cela, un autre appareil encore hors ligne pourrait
// ressusciter une marque-page supprimée. `mergeBookmarks` garde la version la
// plus récente de chaque entrée, marques de suppression comprises.

import Foundation

public enum Bookmark {

    /// `saveBookmark` — `src/core/bookmarks.ts:5`.
    ///
    /// **`lastUsedAt` est EFFACÉ, et c'est mesuré.** L'original construit un objet
    /// NEUF à sept clés — `verseId, surah, ayah, page, sourcePages, createdAt,
    /// updatedAt` — qui ne reprend **ni** `lastUsedAt` **ni** `deletedAt`. Le
    /// ré-enregistrement ressuscite donc une marque-page supprimée, et remet la
    /// date de dernier usage à zéro. Or `visible` trie par
    /// `(lastUsedAt ?? updatedAt)` : conserver `lastUsedAt` ferait diverger
    /// l'ORDRE de la liste entre les deux applications, sur un même document.
    ///
    /// L'original **lève** « Verset inexistant. » sur un identifiant hors bornes ;
    /// une fonction pure n'a pas de quoi lever, elle rend donc l'état INCHANGÉ —
    /// la seule divergence assumée de ce fichier, et elle ne touche aucune donnée.
    public static func save(_ state: AppState, verseID: Int, source: String, page: Int) -> AppState {
        guard verseID >= 1, verseID <= Quran.verses.count else { return state }
        let verse = Quran.verseAt(verseID)
        let now = DateKeys.iso(Date())
        let previous = state.bookmarks?[String(verseID)]

        var next = state
        next.updatedAt = now
        next.lastRead = LastRead(page: page, verseId: verseID, readAt: now)

        var bookmarks = state.bookmarks ?? [:]
        var sourcePages = previous?.sourcePages ?? [:]
        sourcePages[source] = page
        bookmarks[String(verseID)] = VerseBookmark(
            verseId: verseID,
            surah: verse.surah,
            ayah: verse.ayah,
            page: Quran.pageOf(verseID) ?? page,
            sourcePages: sourcePages,
            createdAt: previous?.createdAt ?? now,
            updatedAt: now,
            lastUsedAt: nil,
            deletedAt: nil
        )
        next.bookmarks = bookmarks
        return next
    }

    public static func delete(_ state: AppState, verseID: Int) -> AppState {
        guard let existing = state.bookmarks?[String(verseID)] else { return state }
        let now = DateKeys.iso(Date())
        var bookmarks = state.bookmarks ?? [:]
        var copy = existing
        copy.deletedAt = now
        copy.updatedAt = now
        bookmarks[String(verseID)] = copy

        var next = state
        next.bookmarks = bookmarks
        next.updatedAt = now
        return next
    }

    public static func use(_ state: AppState, verseID: Int, page: Int? = nil) -> AppState {
        guard let existing = state.bookmarks?[String(verseID)], existing.deletedAt == nil else { return state }
        let now = DateKeys.iso(Date())
        var bookmarks = state.bookmarks ?? [:]
        var copy = existing
        copy.lastUsedAt = now
        copy.updatedAt = now
        bookmarks[String(verseID)] = copy

        var next = state
        next.bookmarks = bookmarks
        next.lastRead = LastRead(page: page ?? Quran.pageOf(verseID) ?? existing.page, verseId: verseID, readAt: now)
        next.updatedAt = now
        return next
    }

    /// Les marques-pages visibles, dans l'ordre de l'original — `visibleBookmarks`,
    /// `src/core/bookmarks.ts:18`.
    ///
    /// L'ÉGALITÉ EST ÉPINGLÉE, ET CE N'EST PAS UN DÉTAIL.
    ///   L'original trie sur `(lastUsedAt ?? updatedAt)` décroissant, sans
    ///   départager les ex æquo — mais son entrée n'est pas arbitraire : les clés
    ///   de `state.bookmarks` sont des indices de tableau (`"1"`, `"2"`, …), et
    ///   `Object.values` rend ces clés en ordre NUMÉRIQUE CROISSANT. Comme
    ///   `Array.prototype.sort` est stable, deux marques-pages de même horodatage
    ///   restent dans l'ordre croissant des versets.
    ///
    ///   Swift ne donne aucune de ces deux garanties : un `Dictionary` n'a pas
    ///   d'ordre, et `sorted(by:)` n'est pas stable. Sans le départage explicite
    ///   ci-dessous, l'ordre de la liste divergerait donc de celui de
    ///   l'application React Native — sur le même document, sans qu'aucun écran
    ///   ne le signale. Les ex æquo ne sont pas théoriques : `save` écrit
    ///   l'horodatage de l'appel, et deux enregistrements dans la même
    ///   milliseconde partagent la même date.
    ///
    /// C'est aussi ce qui rend `BookmarksView.lastUsedID` correct : le badge est
    /// le PREMIER maximum de cette liste, donc le plus petit verset à égalité —
    /// comme le `sort` stable suivi de `[0]` de `BookmarksScreen.tsx:10`.
    public static func visible(_ state: AppState) -> [VerseBookmark] {
        (state.bookmarks ?? [:]).values
            .filter { $0.deletedAt == nil }
            .sorted { first, second in
                let left = first.lastUsedAt ?? first.updatedAt
                let right = second.lastUsedAt ?? second.updatedAt
                if left != right { return left > right }
                return first.verseId < second.verseId
            }
    }

    /// Fusion par date de modification — `mergeBookmarks`, `src/core/bookmarks.ts:20`.
    public static func merge(
        _ first: [String: VerseBookmark]?,
        _ second: [String: VerseBookmark]?
    ) -> [String: VerseBookmark]? {
        guard let first else { return second }
        guard let second else { return first }
        var merged = first
        for (key, item) in second {
            if merged[key] == nil || item.updatedAt > merged[key]!.updatedAt {
                merged[key] = item
            }
        }
        return merged
    }
}
