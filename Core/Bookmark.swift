// Bookmark.swift
// Marques-pages — port de `src/core/bookmarks.ts`.
//
// Point de compatibilité : la suppression laisse une marque (`deletedAt`) au lieu
// d'effacer l'entrée. Sans cela, un autre appareil encore hors ligne pourrait
// ressusciter une marque-page supprimée. `mergeBookmarks` garde la version la
// plus récente de chaque entrée, marques de suppression comprises.

import Foundation

public enum Bookmark {

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
            lastUsedAt: previous?.lastUsedAt,
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

    public static func visible(_ state: AppState) -> [VerseBookmark] {
        (state.bookmarks ?? [:]).values
            .filter { $0.deletedAt == nil }
            .sorted { ($0.lastUsedAt ?? $0.updatedAt) > ($1.lastUsedAt ?? $1.updatedAt) }
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
