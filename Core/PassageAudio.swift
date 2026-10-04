// PassageAudio.swift
// Port de `src/core/audio.ts` — la partie PURE, sans AVFoundation.
//
// Ce fichier ne joue rien : il décide. Trois règles y sont silencieuses, et s'y
// tromper ne lève aucune erreur — cela répète seulement un passage une fois de
// trop, ou l'arrête une fois trop tôt.
//
//   1. Le nombre de répétitions est normalisé AILLEURS, dans
//      `PassageAudioPlayer.tsx:79` : `'continuous'` ou un entier strictement
//      positif, sinon `1`. Le `Math.max(1, Math.floor(count))` du fichier
//      d'origine est donc **inatteignable** depuis l'application — il ne
//      protège que l'appel direct. Les deux sont portés : la normalisation
//      comme fonction, le plancher comme garde.
//   2. En mode « passage », avancer d'un verset **conserve** le compteur de
//      répétition. Une répétition compte donc des **passages entiers**, pas des
//      versets.
//   3. En mode « verset par verset », `count == .continuous` ne fait **jamais**
//      avancer le verset : il répète indéfiniment le verset courant.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Toutes les valeurs figées par `Tests/PassageAudioTests.swift` viennent de
//   `_banc/oracle-audio.mjs`, qui charge le **vrai** `src/core/audio.ts` du
//   dépôt de référence — en retirant mécaniquement ses annotations de type — et
//   énumère sa table de décision. Les dériver du code testé reviendrait à
//   comparer le code à lui-même.

import Foundation

/// `RepeatMode` — `src/core/audio.ts:16`. Les valeurs brutes sont celles de
/// l'original, pour que les préférences locales restent lisibles si l'on veut
/// un jour les relire depuis l'application React Native.
public enum RepeatMode: String, CaseIterable, Sendable {
    case passage
    case eachVerse = "each-verse"
}

/// `RepeatCount` — `src/core/audio.ts:17`.
///
/// L'original accepte `number | 'continuous'`, donc aussi `0`, `-2` ou `2,7`.
/// Le portage **restreint à l'entier** : `PassageAudio.normalizedCount` rend
/// cet espace inatteignable depuis l'interface, et un type qui ne peut pas
/// porter une valeur impossible vaut mieux qu'une garde qu'on peut oublier.
public enum RepeatCount: Equatable, Sendable {
    case times(Int)
    case continuous
}

/// `AudioPosition` — `src/core/audio.ts:18`.
public struct AudioPosition: Equatable, Sendable {
    public var verseID: Int
    public var repetition: Int

    public init(verseID: Int, repetition: Int) {
        self.verseID = verseID
        self.repetition = repetition
    }
}

/// `ChapterAudio` — `src/core/audio.ts:19`. Les bornes sont en **secondes**
/// (l'original divise par 1000).
public struct ChapterAudio: Equatable, Sendable {

    public struct Span: Equatable, Sendable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    public var url: String
    public var verses: [Int: Span]

    public init(url: String, verses: [Int: Span]) {
        self.url = url
        self.verses = verses
    }
}

/// Les messages de l'original sont en français et sont repris **tels quels** :
/// ils remontent jusqu'à l'utilisateur (`PassageAudioPlayer.tsx:72`).
public struct PassageAudioError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

public enum PassageAudio {

    /// `DEFAULT_AYAH_GAP_MS` — `src/core/audio.ts:14`. C'est une marge
    /// **technique**, toujours active, distincte du silence choisi par
    /// l'utilisateur : voir `waitMilliseconds`.
    public static let defaultAyahGapMilliseconds = 200

    /// `chapterIds` de `src/services/quranAudioTimeline.ts:5` : seuls **quatre**
    /// récitateurs ont des horodatages de sourate. Abu Bakr Shatri — celui par
    /// défaut — en fait partie.
    public static let chapterResourceIDs: [String: Int] = [
        "ar.husary": 6,
        "ar.alafasy": 7,
        "ar.minshawi": 9,
        "ar.shaatree": 4
    ]

    /// `null` quand le récitateur n'a pas de fichier de sourate : l'original
    /// retombe alors sur les fichiers par verset.
    public static func chapterResourceID(for reciterID: String) -> Int? {
        chapterResourceIDs[reciterID]
    }

    /// `audioRange` — `src/core/audio.ts:50`.
    @discardableResult
    public static func range(start: Int, end: Int) throws -> VerseRange {
        guard start >= 1, end <= Quran.verses.count, start <= end else {
            throw PassageAudioError(message: "Choisis une plage de versets valide.")
        }
        return VerseRange(start: start, end: end)
    }

    /// `PassageAudioPlayer.tsx:79` — le contrat RÉEL du nombre de répétitions.
    ///
    /// C'est cette fonction, et non le plancher interne de `next`, qui décide ce
    /// que l'application peut produire : `'continuous'`, ou un entier
    /// strictement positif, ou `1`.
    public static func normalizedCount(_ count: RepeatCount) -> RepeatCount {
        switch count {
        case .continuous:
            return .continuous
        case .times(let value):
            return value > 0 ? .times(value) : .times(1)
        }
    }

    /// `nextAudioPosition` — `src/core/audio.ts:55`.
    ///
    /// Rend `nil` quand la lecture doit **s'arrêter** : c'est le seul cas où
    /// l'appelant doit conclure, et non enchaîner.
    public static func next(
        range: VerseRange,
        current: AudioPosition,
        mode: RepeatMode,
        count: RepeatCount,
        autoStop: Bool = true
    ) throws -> AudioPosition? {
        try self.range(start: range.start, end: range.end)
        guard current.verseID >= range.start, current.verseID <= range.end,
              current.repetition >= 1 else {
            throw PassageAudioError(message: "Position audio invalide.")
        }

        let unlimited = count == .continuous || !autoStop
        var limit = 1
        if case .times(let value) = count {
            limit = max(1, value)
        }

        switch mode {
        case .eachVerse:
            if count == .continuous {
                return AudioPosition(verseID: current.verseID, repetition: current.repetition + 1)
            }
            if current.repetition < limit {
                return AudioPosition(verseID: current.verseID, repetition: current.repetition + 1)
            }
            if current.verseID < range.end {
                return AudioPosition(verseID: current.verseID + 1, repetition: 1)
            }
            return unlimited ? AudioPosition(verseID: range.start, repetition: 1) : nil

        case .passage:
            if current.verseID < range.end {
                return AudioPosition(verseID: current.verseID + 1, repetition: current.repetition)
            }
            if unlimited || current.repetition < limit {
                return AudioPosition(verseID: range.start, repetition: current.repetition + 1)
            }
            return nil
        }
    }

    /// `PassageAudioPlayer.tsx:194-196` — l'attente avant de rejouer.
    ///
    /// La marge technique de 200 ms est un **plancher** ; le silence choisi par
    /// l'utilisateur ne s'y ajoute que sur un **redémarrage** de passage ou sur
    /// un **verset répété**. Entre deux versets qui s'enchaînent, il ne
    /// s'applique pas — c'est le point qu'on ne devine pas.
    public static func waitMilliseconds(
        from current: AudioPosition,
        to next: AudioPosition,
        range: VerseRange,
        mode: RepeatMode,
        gapSeconds: Int
    ) -> Int {
        let restart = next.verseID == range.start && current.verseID == range.end
        let repeatedVerse = mode == .eachVerse
            && next.verseID == current.verseID
            && next.repetition > current.repetition
        let chosen = (restart || repeatedVerse) ? gapSeconds * 1000 : 0
        return max(defaultAyahGapMilliseconds, chosen)
    }

    /// `parseChapterAudio` — `src/core/audio.ts:20`.
    ///
    /// L'entrée est le fichier `audio_file` de l'API quran.com. Elle est reçue
    /// en `JSONValue` parce que l'original la lit comme un objet **libre** : il
    /// en vérifie la forme avant de s'en servir. Un type `Decodable` strict
    /// déplacerait ces refus dans le décodeur, avec d'autres messages et un
    /// autre ordre — donc un autre comportement observable.
    public static func parse(file: JSONValue?, chapter: Int) throws -> ChapterAudio {
        guard let url = file?["audio_url"]?.stringValue, url.hasPrefix("https://"),
              let timestamps = file?["timestamps"]?.arrayValue,
              chapter >= 1, chapter <= Quran.surahs.count else {
            throw PassageAudioError(message: "Timestamps audio absents.")
        }

        var timings: [Int: ChapterAudio.Span] = [:]
        var previous: Double = 0

        for entry in timestamps {
            // `String(t.verse_key).split(':')` puis déstructuration `[s, a]` :
            // les composantes AU-DELÀ de la deuxième sont ignorées, et une clé
            // qui n'en porte pas deux ne désigne aucun verset. Les deux sont
            // reproduits — `parts[1]` n'existe pas si `parts.count < 2`.
            //
            // Les cinq refus de l'original (mauvaise sourate, verset hors
            // bornes, clé dupliquée, bornes non finies, bornes incohérentes)
            // portent TOUS le même message : les fondre en une seule garde ne
            // change donc rien d'observable, et évite un déroulement forcé.
            let parts = (entry["verse_key"]?.stringValue ?? "")
                .split(separator: ":", omittingEmptySubsequences: false)
            let from = entry["timestamp_from"]?.doubleValue
            let to = entry["timestamp_to"]?.doubleValue

            guard parts.count >= 2,
                  let surah = Int(parts[0]), surah == chapter,
                  let ayah = Int(parts[1]),
                  let identifier = Quran.verseID(surah: surah, ayah: ayah),
                  timings[identifier] == nil,
                  let from, let to,
                  from >= previous, to > from else {
                throw PassageAudioError(message: "Timestamps audio invalides.")
            }

            timings[identifier] = ChapterAudio.Span(start: from / 1000, end: to / 1000)
            previous = to
        }

        guard timings.count == Quran.surahs[chapter - 1].count else {
            throw PassageAudioError(message: "Timestamps incomplets.")
        }
        return ChapterAudio(url: url, verses: timings)
    }

    /// `continuousAudioPosition` — `src/core/audio.ts:32`.
    ///
    /// Avance l'**affichage** seulement : elle ne recule jamais, ne cherche
    /// jamais dans la source, et s'arrête au bout de la plage ou dès que le
    /// verset suivant n'est pas dans les horodatages.
    public static func continuous(
        timeline: ChapterAudio,
        range: VerseRange,
        position: AudioPosition,
        time: Double
    ) -> AudioPosition {
        var identifier = position.verseID
        while identifier < range.end,
              let following = timeline.verses[identifier + 1],
              time >= following.start {
            identifier += 1
        }
        return AudioPosition(verseID: identifier, repetition: position.repetition)
    }

    /// `quranAudioTimeline.ts:17` — la validité d'un fichier de sourate **déjà
    /// en cache**.
    ///
    /// Un cache dont une seule borne est fausse est jeté et rechargé : c'est
    /// cette condition, et non la seule présence du fichier, qui décide.
    public static func isUsableCachedChapter(
        _ chapter: ChapterAudio?,
        verseID: Int,
        chapterNumber: Int
    ) -> Bool {
        guard let chapter,
              chapter.url.hasPrefix("https://"),
              chapter.verses[verseID] != nil,
              chapterNumber >= 1, chapterNumber <= Quran.surahs.count else { return false }
        guard chapter.verses.count == Quran.surahs[chapterNumber - 1].count else { return false }
        return chapter.verses.values.allSatisfy {
            $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
        }
    }

    /// `verseAudioLabel` — `src/core/audio.ts:71`.
    ///
    /// Rend `nil` hors bornes, là où l'original produirait
    /// « sourate undefined, verset undefined » : un libellé qui ment est pire
    /// qu'un libellé absent.
    public static func label(_ verseID: Int) -> String? {
        guard verseID >= 1, verseID <= Quran.verses.count else { return nil }
        let verse = Quran.verseAt(verseID)
        return "sourate \(verse.surah), verset \(verse.ayah)"
    }
}
