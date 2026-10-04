// Coran1441DownloadService.swift
// Téléchargement et installation des 9 060 bandes du Coran 1441.
//
// Correspondance : `src/services/quranDownload.ts` de l'application React
// Native, dont ce fichier reprend le déroulement, les contrôles et les
// messages.
//
// CE QUI EST TÉLÉCHARGÉ, ET POURQUOI CE N'EST PAS EMBARQUÉ
//   Une archive ZIP de 102 608 011 octets publiée par `files.quran.app`. Elle
//   n'est pas dans le paquet de l'application : 102 Mo ajoutés à chaque
//   installation, pour une édition que tout le monde n'utilise pas. Le Coran de
//   Médine, lui, est embarqué — c'est l'édition par défaut.
//
// LE DÉROULEMENT, ET L'ORDRE COMPTE
//   1. télécharger l'archive, en reprenant un téléchargement interrompu ;
//   2. vérifier qu'elle fait exactement la taille annoncée ;
//   3. écrire un témoin « téléchargement complet » ;
//   4. extraire les images, en validant chacune ;
//   5. exiger les 9 060 images ;
//   6. écrire `ready-v1.json` ;
//   7. supprimer l'archive et le témoin.
//
//   Le témoin de l'étape 3 évite de retélécharger 102 Mo quand seule
//   l'extraction a échoué. Le marqueur de l'étape 6 est écrit **en dernier** :
//   tant qu'il n'existe pas, l'installation est réputée incomplète, et une
//   interruption laisse un dossier qu'on peut reprendre au lieu d'un dossier
//   faussement déclaré prêt.
//
// CE QU'ON NE FAIT PAS
//   On ne réessaie pas indéfiniment. Un échec laisse l'application dans un état
//   où l'utilisateur peut relancer — avec un message qui dit quoi faire. Une
//   boucle de reprise automatique sur un réseau absent viderait la batterie sans
//   rien apporter.
//
//   On ne télécharge pas non plus en arrière-plan : l'application d'origine
//   utilise explicitement une session au premier plan
//   (`FileSystemSessionType.FOREGROUND`, `quranDownload.ts:57`), et son message
//   d'erreur le dit (« en gardant l'application ouverte »). Le mode
//   d'arrière-plan du paquet ne couvre que l'audio.

import Combine
import Foundation

@MainActor
public final class Coran1441DownloadService: ObservableObject {

    // MARK: État publié

    public enum Phase: String, Sendable, Equatable {
        case idle
        case downloading
        case extracting
        case ready
        case paused
        case failed

        /// L'installation travaille-t-elle en ce moment ?
        public var isBusy: Bool { self == .downloading || self == .extracting }
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        public var progress: Double
        public var message: String?

        public init(phase: Phase, progress: Double, message: String? = nil) {
            self.phase = phase
            self.progress = progress
            self.message = message
        }

        public static let idle = State(phase: .idle, progress: 0)
        public static let ready = State(phase: .ready, progress: 1)
    }

    /// Les échecs de l'installation.
    ///
    /// Déclarés dans `Coran1441Install`, qui porte les règles : ils décrivent
    /// *ce qui* a échoué, pas *qui* l'exécutait — et le code qui les lève n'est
    /// pas toujours sur le fil principal.
    public typealias Failure = Coran1441Install.Failure

    @Published public private(set) var state: State

    // MARK: Dépendances

    private let fileManager: FileManager
    private let directory: URL
    private let archiveURL: URL
    private let downloadCompleteURL: URL
    private let resumeURL: URL

    private var session: URLSession?
    private var transfer: Coran1441Transfer?
    private var task: URLSessionDownloadTask?
    private var installTask: Task<Void, Never>?
    private var extractionTask: Task<Int, Error>?
    private var pauseRequested = false

    // MARK: Construction

    /// - Parameter directory: le dossier où installer les images. Par défaut,
    ///   celui du dossier de téléchargement de l'application, sous
    ///   `coran_1441` — le même que celui que lit `QuranSourceService`.
    public init(directory: URL? = nil) {
        let fileManager = FileManager.default
        let base = directory ?? fileManager
            .urls(for: .documentDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("quran", isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let folder = base.appendingPathComponent(
            QuranSourceService.coran1441FolderName,
            isDirectory: true
        )

        self.fileManager = fileManager
        self.directory = folder
        self.archiveURL = folder.appendingPathComponent(Coran1441Install.archiveName)
        self.downloadCompleteURL = folder.appendingPathComponent(Coran1441Install.downloadCompleteName)
        self.resumeURL = folder.appendingPathComponent(Coran1441Install.resumeName)
        self.state = Coran1441Install.isReady(in: folder, fileManager: fileManager) ? .ready : .idle
    }

    // MARK: Ce que les vues demandent

    /// Le dossier d'installation, pour les tests et le diagnostic.
    public var installDirectory: URL { directory }

    /// L'installation est-elle complète ?
    public var isInstalled: Bool {
        Coran1441Install.isReady(in: directory, fileManager: fileManager)
    }

    /// Relit l'état depuis le disque — par exemple au retour au premier plan.
    public func refresh() {
        guard !state.phase.isBusy else { return }
        if isInstalled {
            state = .ready
        } else if state.phase == .ready {
            // Le marqueur a disparu depuis la dernière lecture : ne pas continuer
            // d'annoncer « prêt » sur un dossier amputé.
            state = .idle
        }
    }

    /// Lance l'installation, ou la reprend après une pause.
    ///
    /// Sans effet si une installation est déjà en cours, ou si tout est déjà
    /// installé.
    public func start() {
        guard !isInstalled else {
            state = .ready
            return
        }
        guard installTask == nil else { return }

        pauseRequested = false
        state = State(phase: .downloading, progress: 0)
        installTask = Task { [weak self] in
            await self?.run()
            self?.installTask = nil
        }
    }

    /// Demande l'arrêt. L'archive déjà téléchargée est conservée, et la reprise
    /// repart de là.
    ///
    /// Une pause pendant l'extraction annule l'extraction : les images déjà
    /// écrites restent, et la reprise les réécrira. C'est sans danger — chaque
    /// fichier est écrit de façon atomique, donc jamais à moitié.
    public func pause() {
        guard state.phase.isBusy else { return }
        pauseRequested = true
        extractionTask?.cancel()
        if let active = task {
            active.cancel(byProducingResumeData: { [weak self] data in
                guard let data else { return }
                Task { @MainActor in self?.storeResumeData(data) }
            })
        } else {
            installTask?.cancel()
        }
    }

    /// Efface l'installation et l'archive. Sert au diagnostic, et à libérer la
    /// place — 102 Mo d'archive plus les images.
    public func removeAll() {
        pause()
        installTask?.cancel()
        try? fileManager.removeItem(at: directory)
        state = .idle
    }

    // MARK: Déroulement

    private func run() async {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            if !archiveIsComplete() {
                try await downloadArchive()
            }

            state = State(phase: .extracting, progress: 0)
            let installed = try await extract()
            guard installed == Coran1441Install.requiredFileCount else {
                throw Failure.incomplete(count: installed)
            }

            try writeMarker(count: installed)
            try? fileManager.removeItem(at: archiveURL)
            try? fileManager.removeItem(at: downloadCompleteURL)
            try? fileManager.removeItem(at: resumeURL)
            state = .ready
        } catch {
            if pauseRequested {
                state = State(phase: .paused, progress: state.progress)
            } else if isCancellation(error) {
                // Annulation sans demande de pause : l'application se ferme.
                state = State(phase: .idle, progress: state.progress)
            } else {
                state = State(phase: .failed, progress: state.progress, message: Self.message(for: error))
            }
        }
    }

    /// Vrai quand le ZIP est là, complet, et que l'extraction a déjà été menée
    /// une fois à son terme au moins une fois.
    private func archiveIsComplete() -> Bool {
        guard fileManager.fileExists(atPath: downloadCompleteURL.path) else { return false }
        return fileSize(of: archiveURL) == Coran1441Install.archiveBytes
    }

    // MARK: Téléchargement

    private func downloadArchive() async throws {
        guard let url = Coran1441Install.archiveURL else { throw Failure.archiveMissing }

        state = State(phase: .downloading, progress: 0)

        let transfer = Coran1441Transfer(destination: archiveURL, fileManager: fileManager)
        self.transfer = transfer
        let session = URLSession(configuration: .default, delegate: transfer, delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
            self.transfer = nil
            self.task = nil
        }

        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL), !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }
        self.task = task

        // Les tailles attendues servent au contrôle de progression : quand le
        // serveur annonce la taille, elle est plus juste que la constante ; quand
        // il ne l'annonce pas (-1), la constante prend le relais.
        let announced = Coran1441Install.archiveBytes

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            transfer.onProgress = { [weak self] written, expected in
                let total = expected > 0 ? expected : Int64(announced)
                Task { @MainActor in self?.reportDownload(written: written, total: total) }
            }
            transfer.onCompletion = { result in
                continuation.resume(with: result)
            }
            task.resume()
        }

        let found = fileSize(of: archiveURL)
        guard found == Coran1441Install.archiveBytes else {
            // Une archive de mauvaise taille ne doit pas être conservée : la
            // reprise repartirait d'un fichier faux, et l'échec se reproduirait
            // à l'identique à chaque tentative.
            try? fileManager.removeItem(at: archiveURL)
            try? fileManager.removeItem(at: resumeURL)
            throw Failure.archiveSizeMismatch(expected: Coran1441Install.archiveBytes, found: found)
        }

        try Data().write(to: downloadCompleteURL)
        try? fileManager.removeItem(at: resumeURL)
    }

    private func reportDownload(written: Int64, total: Int64) {
        guard state.phase == .downloading, total > 0 else { return }
        let ratio = Double(written) / Double(total)
        state = State(phase: .downloading, progress: min(max(ratio, 0), 1))
    }

    private func storeResumeData(_ data: Data) {
        try? data.write(to: resumeURL, options: .atomic)
    }

    // MARK: Extraction

    /// Extrait les images, **hors du fil principal**.
    ///
    /// 9 060 décompressions DEFLATE ne sont pas un travail d'interface : les
    /// faire sur le fil principal figerait l'écran pendant toute l'extraction,
    /// et l'application paraîtrait plantée alors qu'elle travaille.
    ///
    /// La tâche est détachée — et non héritée — parce que le fil principal est
    /// précisément ce qu'on veut éviter ; elle est donc conservée pour pouvoir
    /// l'annuler, `Task.detached` n'héritant pas de l'annulation de son parent.
    private func extract() async throws -> Int {
        let archive = archiveURL
        let folder = directory
        let total = Coran1441Install.requiredFileCount

        // La closure de progression est construite ICI, sur le fil principal,
        // puis passée telle quelle : la tâche détachée n'a donc pas à connaître
        // le service, et il n'y a qu'une seule capture faible à raisonner.
        let report: @Sendable (Int) -> Void = { [weak self] done in
            Task { @MainActor in
                self?.reportExtraction(done: done, total: total)
            }
        }

        let work = Task.detached(priority: .utility) {
            try Self.extractEntries(from: archive, into: folder, total: total, progress: report)
        }
        extractionTask = work
        defer { extractionTask = nil }
        return try await work.value
    }

    private func reportExtraction(done: Int, total: Int) {
        guard state.phase == .extracting, total > 0 else { return }
        state = State(phase: .extracting, progress: min(max(Double(done) / Double(total), 0), 1))
    }

    /// Le travail d'extraction, sans état ni acteur : éprouvable seul.
    ///
    /// - Returns: le nombre d'images écrites.
    nonisolated static func extractEntries(
        from archive: URL,
        into directory: URL,
        total: Int,
        progress: @Sendable (Int) -> Void
    ) throws -> Int {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }

        let size = Int(try handle.seekToEnd())

        // Lit exactement `length` octets, en insistant si le système en rend
        // moins : `read(upToCount:)` peut rendre une lecture partielle, et s'en
        // contenter produirait un en-tête tronqué — donc un décalage faux, donc
        // des images corrompues sans qu'aucune erreur ne soit levée.
        let read: Coran1441Archive.Reader = { offset, length in
            guard length > 0 else { return Data() }
            try handle.seek(toOffset: UInt64(offset))
            var buffer = Data()
            buffer.reserveCapacity(length)
            while buffer.count < length {
                guard let chunk = try handle.read(upToCount: length - buffer.count),
                      !chunk.isEmpty else { break }
                buffer.append(chunk)
            }
            return buffer
        }

        let tailLength = min(Coran1441Archive.tailLength, size)
        let tail = try read(size - tailLength, tailLength)
        let central = try Coran1441Archive.centralDirectory(fileSize: size, tail: tail)
        let directoryData = try read(central.offset, central.size)
        let entries = try Coran1441Archive.entries(
            centralDirectory: directoryData,
            count: central.count
        )

        var installed = 0
        // Les écritures sont groupées par paquets pour ne pas inonder le fil
        // principal : 9 060 annonces de progression seraient 9 060 réévaluations
        // de vue, pour un affichage qui ne distingue pas deux images sur mille.
        let stride = max(1, total / 200)

        for entry in entries {
            try Task.checkCancellation()

            // Tout ce qui ne s'appelle pas `width_1440/<page>/<ligne>.png` est
            // ignoré, sans erreur : une archive peut légitimement contenir autre
            // chose, et l'original refuse explicitement d'en extraire les autres
            // chemins (`quranDownload.ts:82`).
            guard let location = Coran1441Install.location(inArchivePath: entry.name) else { continue }

            // Le nom correspond au motif, mais désigne une page hors bornes :
            // c'est le signe que l'archive n'est pas celle attendue. L'original
            // s'arrête là aussi (`:84`).
            guard let name = Coran1441Install.fileName(page: location.page, line: location.line) else {
                throw Failure.pageOutOfRange(entry.name)
            }

            // La taille annoncée est connue avant de décompresser : la vérifier
            // d'abord évite d'allouer 2 Mo pour une entrée qui n'a rien à faire
            // là.
            guard entry.uncompressedSize <= Coran1441Install.maximumImageBytes else {
                throw Failure.imageTooLarge(name)
            }

            let data = try Coran1441Archive.contents(of: entry, read: read)
            guard Coran1441Install.isValidPageImage(data) else {
                throw Failure.invalidImage(name)
            }

            // Écriture atomique : une image n'est jamais visible à moitié
            // écrite. `QuranSourceService.imageURLs` se fie à l'existence du
            // fichier pour décider qu'une bande est là ; un fichier tronqué
            // serait donc rendu comme une bande valide.
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)

            installed += 1
            if installed % stride == 0 { progress(installed) }
        }

        progress(installed)
        return installed
    }

    // MARK: Marqueur

    private func writeMarker(count: Int) throws {
        let marker = Coran1441Install.Ready(
            version: Coran1441Install.markerVersion,
            files: count,
            installedAt: DateKeys.iso(Date())
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(to: directory.appendingPathComponent(Coran1441Install.markerName), options: .atomic)
    }

    // MARK: Aides

    private func fileSize(of url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// Le message montré à l'utilisateur.
    ///
    /// L'application d'origine choisit son message en cherchant des mots dans le
    /// texte de l'erreur (`/space|disk|ENOSPC|storage/i`,
    /// `quranDownload.ts:35-37`). Ici, la décision se prend sur le **domaine et
    /// le code** de l'erreur — une information que le système fournit, au lieu
    /// d'une chaîne traduite qui change avec la version d'iOS. Les deux messages
    /// finaux sont ceux de l'original, mot pour mot.
    static func message(for error: Error) -> String {
        if let described = error as? LocalizedError, let text = described.errorDescription {
            return text
        }

        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, CocoaError.Code.fileWriteOutOfSpace.rawValue),
             (NSCocoaErrorDomain, CocoaError.Code.fileWriteVolumeReadOnly.rawValue):
            return "Espace de stockage insuffisant. Libère de la place puis réessaie."
        case (NSURLErrorDomain, _):
            return "Le téléchargement a été interrompu. Vérifie ta connexion et réessaie en gardant l'application ouverte."
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Le transfert

/// Reçoit les événements d'une `URLSession` de téléchargement.
///
/// Une classe à part, et non le service : les rappels du délégué arrivent sur une
/// file d'attente du système, pas sur le fil principal. Les garder hors du
/// service évite d'y faire entrer une concurrence qui n'a rien à y faire.
final class Coran1441Transfer: NSObject, URLSessionDownloadDelegate {

    private let destination: URL
    private let fileManager: FileManager

    var onProgress: ((Int64, Int64) -> Void)?
    var onCompletion: ((Result<URL, Error>) -> Void)?

    init(destination: URL, fileManager: FileManager) {
        self.destination = destination
        self.fileManager = fileManager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    /// Le fichier temporaire est supprimé **dès le retour de cette méthode** :
    /// le déplacement doit donc être fait ici, de façon synchrone. Le confier à
    /// une tâche différée trouverait un fichier déjà effacé.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            onCompletion?(.success(destination))
        } catch {
            onCompletion?(.failure(error))
        }
    }

    /// Appelé **après** `didFinishDownloadingTo`, y compris en cas de succès —
    /// avec une erreur nulle. Ne rien signaler dans ce cas : la continuation
    /// aurait été reprise deux fois, ce qui arrête le programme.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        onCompletion?(.failure(error))
    }
}
