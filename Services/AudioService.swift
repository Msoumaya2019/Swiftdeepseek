// AudioService.swift
// Lecture audio avec AVFoundation.
//
// Correspondance : `src/core/audio.ts`, `src/services/quranAudioTimeline.ts`,
// `src/services/verseAudioCache.ts` et `src/PassageAudioPlayer.tsx`.
//
// Les récitateurs et les URL sont ceux de l'application actuelle, pour que
// l'utilisateur retrouve les mêmes voix et que rien ne soit dupliqué côté
// serveur. Le cache local reprend la même politique : télécharger une fois,
// relire hors ligne.

import Foundation
import AVFoundation

public struct Reciter: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var arabic: String?
    public var bitrate: Int
    /// Certains récitateurs sont servis par everyayah, d'autres par
    /// islamic.network — exactement comme `verseAudioUrl()` côté React Native.
    public var verseFolder: String?

    public static let all: [Reciter] = [
        Reciter(id: "ar.husary", name: "Mahmoud Khalil Al-Husary", bitrate: 128),
        Reciter(id: "ar.alafasy", name: "Mishary Rashid Alafasy", bitrate: 128),
        Reciter(id: "ar.minshawi", name: "Mohammed Siddiq Al-Minshawi", bitrate: 128),
        Reciter(id: "ar.shaatree", name: "Abu Bakr Shatri", bitrate: 128),
        Reciter(id: "ar.ghamidi", name: "Saad Al Ghamidi", arabic: "سعد الغامدي",
                bitrate: 40, verseFolder: "Ghamadi_40kbps"),
        Reciter(id: "ar.dussary", name: "Yasser Al Dosari", arabic: "ياسر الدوسري",
                bitrate: 128, verseFolder: "Yasser_Ad-Dussary_128kbps"),
        Reciter(id: "ar.qatami", name: "Nasser Al Qatami", arabic: "ناصر القطامي",
                bitrate: 128, verseFolder: "Nasser_Alqatami_128kbps")
    ]

    /// L'application React Native prend `reciters[3]`, soit Abu Bakr Shatri.
    /// À noter : `LECTURE_MARQUES_PAGES.md` annonce Alafasy comme choix initial.
    /// Le code fait foi ici — mais c'est une divergence à trancher avec le
    /// propriétaire du produit (signalée dans SWIFT_MIGRATION.md).
    public static let `default` = all[3]

    public static func find(_ id: String?) -> Reciter {
        guard let id, let found = all.first(where: { $0.id == id }) else { return .default }
        return found
    }
}

public enum VerseAudio {

    /// Base des récitateurs servis par islamic.network.
    /// Source : `src/data/ipa-audio-source.json`.
    public static let baseURL = "https://cdn.islamic.network/quran/audio"

    /// `verseAudioUrl(id, reciter)` — `src/core/audio.ts:38`.
    public static func url(verseID: Int, reciter: Reciter = .default) -> URL? {
        if let folder = reciter.verseFolder {
            guard let verse = Quran.verses[safe: verseID - 1] else { return nil }
            let name = String(format: "%03d%03d.mp3", verse.surah, verse.ayah)
            return URL(string: "https://everyayah.com/data/\(folder)/\(name)")
        }
        return URL(string: "\(baseURL)/\(reciter.bitrate)/\(reciter.id)/\(verseID).mp3")
    }
}

/// Télécharge une fois puis relit hors ligne — même politique que
/// `verseAudioCache.ts` (cache sur disque, écriture atomique `.part`).
public actor VerseAudioCache {

    private let fileManager = FileManager.default
    private let directory: URL

    public init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("quran-verse-audio-v1", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func localURL(for remote: URL) -> URL {
        let name = remote.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return directory.appendingPathComponent(name + ".mp3")
    }

    /// Renvoie une URL locale si le fichier est déjà là, sinon la distante.
    public func cachedURL(for remote: URL) -> URL {
        let local = localURL(for: remote)
        return fileManager.fileExists(atPath: local.path) ? local : remote
    }

    /// Télécharge en tâche de fond sans jamais bloquer la lecture en cours.
    public func prefetch(_ remote: URL) async {
        let local = localURL(for: remote)
        guard !fileManager.fileExists(atPath: local.path) else { return }
        do {
            let (temporary, _) = try await URLSession.shared.download(from: remote)
            try? fileManager.removeItem(at: local)
            try fileManager.moveItem(at: temporary, to: local)
        } catch {
            // Un préchargement qui échoue n'est jamais une erreur visible :
            // la lecture reprendra depuis le réseau.
        }
    }
}

@MainActor
public final class AudioService: ObservableObject {

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentVerseID: Int?
    @Published public private(set) var reciter: Reciter = .default

    private var player: AVPlayer?
    private let cache = VerseAudioCache()
    private var preloaded = Set<String>()

    public init() {}

    /// `{playsInSilentMode: true, shouldPlayInBackground: true, interruptionMode: 'doNotMix'}`
    /// — `src/PassageAudioPlayer.tsx:186`.
    public func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    public func select(reciter: Reciter) {
        self.reciter = reciter
        preloaded.removeAll()
    }

    public func play(verseID: Int) {
        guard let remote = VerseAudio.url(verseID: verseID, reciter: reciter) else { return }
        configureSession()
        currentVerseID = verseID

        Task {
            let local = await cache.cachedURL(for: remote)
            let item = AVPlayerItem(url: local)
            if let player {
                player.replaceCurrentItem(with: item)
            } else {
                player = AVPlayer(playerItem: item)
            }
            player?.play()
            isPlaying = true
        }
        preloadUpcoming(from: verseID)
    }

    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    public func next(within range: VerseRange) {
        guard let current = currentVerseID, current < range.end else { return }
        play(verseID: current + 1)
    }

    public func previous(within range: VerseRange) {
        guard let current = currentVerseID, current > range.start else { return }
        play(verseID: current - 1)
    }

    /// Précharge les trois versets suivants — même profondeur que
    /// `src/PassageAudioPlayer.tsx:139`.
    private func preloadUpcoming(from verseID: Int) {
        let upcoming = (1...3).compactMap { offset -> URL? in
            guard let url = VerseAudio.url(verseID: verseID + offset, reciter: reciter) else { return nil }
            return url
        }
        Task { [cache, weak self] in
            for url in upcoming {
                let key = url.absoluteString
                guard await self?.preloaded.contains(key) != true else { continue }
                await self?.markPreloaded(key)
                await cache.prefetch(url)
            }
        }
    }

    private func markPreloaded(_ key: String) {
        preloaded.insert(key)
    }
}
