// ChapterAudioCache.swift
// La **forme sur disque** de la chronologie d'une sourate — la partie PURE.
//
// POURQUOI CE FICHIER SÉPARÉ
//   `Core/PassageAudio.swift` décide si un document de chronologie est
//   *utilisable* (`isUsableCachedChapter`). Il ne dit pas sous quelle **forme**
//   on l'écrit. Ce fichier dit la forme, et rien d'autre : la clé de cache et
//   les deux conversions. Il reste donc sans AVFoundation, comme le reste de
//   `Core/`.
//
// LA FORME EST CELLE DE L'ORIGINAL, À LA LETTRE
//   `quranAudioTimeline.ts:23` écrit `JSON.stringify(result)`, où `result` est
//   un `ChapterAudio` : `{"url": "https://…", "verses": {"<verseId>":
//   {"start": s, "end": e}}}`. Les clés de `verses` sont des **chaînes**.
//
//   Ce n'est pas un détail de style : `[Int: Span]` confié à `JSONEncoder`
//   produit un **tableau** alternant clés et valeurs — relisible par cette
//   application, mais illisible par l'autre, et illisible par un humain qui
//   ouvrirait le fichier. Comme l'objectif est que les deux applications se
//   comportent identiquement, la forme écrite est celle de l'original.

import Foundation

public enum ChapterAudioCache {

    /// `quranAudioTimeline.ts:13` — `chapter-audio-v1:${resource}:${chapter}`.
    ///
    /// `resource` est l'identifiant de récitation de la sourate chez
    /// quran.com, pas l'identifiant du récitateur : voir
    /// `PassageAudio.chapterResourceID(for:)`.
    public static func key(resource: Int, chapter: Int) -> String {
        "chapter-audio-v1:\(resource):\(chapter)"
    }

    /// `quranAudioTimeline.ts:25` — `unavailableUntil.set(key, Date.now() +
    /// 5 * 60 * 1000)`.
    ///
    /// Une sourate dont la chronologie a échoué n'est pas redemandée pendant
    /// cinq minutes. Sans ce délai, chaque changement de verset relancerait une
    /// requête qui vient déjà d'échouer — et une connexion absente produirait
    /// une requête par verset écouté.
    public static let unavailableInterval: TimeInterval = 300
}

public extension ChapterAudio {

    /// La forme écrite dans le stockage local — celle de `JSON.stringify`.
    var encoded: JSONValue {
        var spans: [String: JSONValue] = [:]
        for (identifier, span) in verses {
            spans[String(identifier)] = .object([
                "start": .number(span.start),
                "end": .number(span.end)
            ])
        }
        return .object([
            "url": .string(url),
            "verses": .object(spans)
        ])
    }

    /// Relit la forme ci-dessus, ou rend `nil`.
    ///
    /// `nil` dès qu'**une** entrée est illisible : un document à moitié lu
    /// produirait une chronologie dont le nombre de versets ne correspond plus,
    /// et `PassageAudio.isUsableCachedChapter` la refuserait de toute façon —
    /// mais il la refuserait **après** qu'on l'a crue valide. Rendre `nil` ici
    /// garde la décision à un seul endroit.
    static func decode(_ document: JSONValue?) -> ChapterAudio? {
        guard let document, case .object(let fields) = document,
              let url = fields["url"]?.stringValue,
              let raw = fields["verses"]?.objectValue else { return nil }

        var spans: [Int: Span] = [:]
        for (key, value) in raw {
            guard let identifier = Int(key),
                  let start = value["start"]?.doubleValue,
                  let end = value["end"]?.doubleValue else { return nil }
            spans[identifier] = Span(start: start, end: end)
        }
        return ChapterAudio(url: url, verses: spans)
    }
}
