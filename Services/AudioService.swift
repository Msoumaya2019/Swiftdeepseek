// AudioService.swift
// Le catalogue des récitateurs, les URL des versets, le cache disque — et la
// façade observable du lecteur.
//
// Correspondance : `src/core/audio.ts`, `src/services/quranAudioTimeline.ts`,
// `src/services/verseAudioCache.ts` et `src/PassageAudioPlayer.tsx`.
//
// Les récitateurs et les URL sont ceux de l'application actuelle, pour que
// l'utilisateur retrouve les mêmes voix et que rien ne soit dupliqué côté
// serveur. Le cache local reprend la même politique : télécharger une fois,
// relire hors ligne.
//
// Ce fichier ne parle plus à AVFoundation. La traduction des effets en appels
// au lecteur vit dans `Services/PassageAudioExecutor.swift` : ici ne restent
// que ce qui se relit (un catalogue, des URL, une politique de cache) et ce que
// les vues observent. C'est ce qui évite de mêler ce qui se vérifie à ce qui ne
// se vérifie que sur un appareil.

import Foundation

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
            // Bornes vérifiées explicitement : le paquet ne définit aucun
            // subscript « sûr », et un identifiant hors bornes doit rendre
            // `nil` plutôt que de faire tomber l'application.
            guard verseID >= 1, verseID <= Quran.verses.count else { return nil }
            let verse = Quran.verses[verseID - 1]
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

/// La façade observable du lecteur audio.
///
/// ELLE NE JOUE PLUS RIEN ELLE-MÊME
///   Elle tenait autrefois un `AVPlayer` et savait lire **un** verset : ni
///   boucle de répétition, ni silence, ni reprise enchaînée, et rien qui
///   signale la fin d'un fichier — un verset terminé laissait `isPlaying` à
///   vrai pour toujours. Tout cela vit maintenant dans
///   `Services/PassageAudioExecutor.swift`, qui exécute les effets décidés par
///   `Core/PassageAudioEngine.swift`.
///
///   Il ne reste ici que ce que les vues observent : trois valeurs publiées et
///   les gestes qui les font changer. La surface publique n'a pas bougé —
///   `ReaderView` et `AudioRepeatSettingsView` n'ont pas eu à être modifiées.
@MainActor
public final class AudioService: ObservableObject {

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentVerseID: Int?
    @Published public private(set) var reciter: Reciter = .default

    /// Le dernier message d'échec, tel que l'original le remonte
    /// (`PassageAudioPlayer.tsx:72`). `nil` tant qu'aucun lancement n'a échoué.
    @Published public private(set) var lastError: String?

    private let passage: PassageAudioExecutor
    /// Les réglages courants, pour que « écouter ce verset » conserve le
    /// silence et la vitesse choisis — l'original recopie `settingsRef.current`.
    private var preferences: AudioRepeatPreferences = .defaults

    public init(store: LocalStore) {
        passage = PassageAudioExecutor(store: store)
        passage.onVerseChange = { [weak self] identifier in self?.currentVerseID = identifier }
        passage.onPlayingChange = { [weak self] playing in self?.isPlaying = playing }
        passage.onError = { [weak self] message in self?.lastError = message }
        passage.reciter = reciter
    }

    /// `{playsInSilentMode: true, shouldPlayInBackground: true, interruptionMode: 'doNotMix'}`
    /// — `src/PassageAudioPlayer.tsx:186`.
    public func configureSession() {
        passage.configureSession()
    }

    public func select(reciter: Reciter) {
        self.reciter = reciter
        passage.select(reciter: reciter)
    }

    /// `action === 'listen'` — le verset affiché, une écoute.
    ///
    /// C'est le geste du lecteur : appuyer sur « Écouter » fait entendre le
    /// verset affiché **une fois**, puis s'arrête. C'est ce que fait l'original
    /// (`countChoice = 1`, mode « passage », arrêt automatique armé), et c'est
    /// aussi ce qui corrige un défaut de la version précédente : un verset
    /// arrivé à son terme laissait `isPlaying` à vrai, faute de conclusion.
    public func play(verseID: Int) {
        lastError = nil
        passage.listen(verseID: verseID, preferences: preferences)
    }

    /// « Lancer ce passage » — la boucle complète, avec les réglages choisis.
    public func playPassage(_ range: VerseRange, preferences: AudioRepeatPreferences) {
        lastError = nil
        passage.begin(range: range, preferences: preferences)
    }

    /// Les réglages changent : la vitesse s'applique à la lecture en cours, et
    /// le silence est retenu pour le prochain lancement.
    public func setPreferences(_ updated: AudioRepeatPreferences) {
        preferences = updated
        passage.setPreferences(updated)
    }

    public func togglePlayPause() {
        lastError = nil
        passage.playPause()
    }

    public func stop() {
        passage.stop()
    }

    public func next() {
        passage.jump(1)
    }

    public func previous() {
        passage.jump(-1)
    }
}
