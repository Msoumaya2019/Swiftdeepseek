// PassageAudioExecutor.swift
// L'exécuteur des `PassageAudioEffect` — la seule couche qui parle à
// AVFoundation.
//
// CE FICHIER NE DÉCIDE DE RIEN
//   `Core/PassageAudio.swift` décide *quelle* position vient ensuite et
//   *combien de temps* attendre. `Core/PassageAudioEngine.swift` décide **ce
//   qu'on en fait**. Ce fichier-ci se contente de traduire : chaque
//   `PassageAudioEffect` devient un appel au lecteur, et rien de plus. Aucune
//   condition de ce fichier ne regarde un compte de répétitions, un mode, une
//   durée d'attente ou une borne de plage.
//
//   C'est ce qui rend la boucle éprouvable : la partie qui décide est couverte
//   par `Tests/PassageAudioTests.swift` et `Tests/PassageAudioEngineTests.swift`
//   — dont les valeurs attendues viennent du **vrai** TypeScript, empaqueté par
//   `_banc/oracle-audio.mjs`. Ce qui reste ici est précisément ce qu'on ne peut
//   pas éprouver sans appareil, et cela se réduit à une traduction.
//
// LES TROIS FINS DE LECTURE
//   `PassageAudioPlayer.tsx:213-216` conclut sur **trois** signaux distincts, et
//   s'y tromper ne lève aucune erreur — cela ne fait simplement jamais avancer
//   le passage :
//
//     1. `didJustFinish` — la notification de fin d'un `AVPlayerItem`.
//     2. `segmentFinished` — la fin du **segment horodaté**, coupée net avant le
//        mot suivant : c'est `armBoundary`, qui vise l'échéance exacte.
//     3. `fileFinished` — la position atteint la durée sans que la notification
//        soit venue. Certains fichiers rendus par le réseau rapportent seulement
//        la dernière position.
//
//   Les trois aboutissent à `reportEnded()`, et c'est le **même** garde qui les
//   rend inoffensives quand deux d'entre elles se déclenchent à quelques
//   millisecondes d'écart : la machine n'avance que si elle est encore en train
//   de jouer.
//
// CE QUI SE RECALE EN MÊME TEMPS QUE LE VERSET
//   `announce(_:)` publie le verset affiché **et** recale la fin de segment. Les
//   deux sont liés, et c'est le point qu'on ne devine pas : quand la machine
//   enchaîne deux versets d'une même piste horodatée, elle émet `resume` — sans
//   position. La source ne change pas, la lecture reprend après la pause, et
//   rien d'autre ne viendrait dire que le segment à surveiller a changé. Ne pas
//   recaler ici ferait disparaître la fin du verset suivant : la piste
//   continuerait jusqu'à la fin du fichier de la sourate, et le passage ne
//   s'arrêterait jamais. C'est ce que fait `resumeContinuous`
//   (`PassageAudioPlayer.tsx:106`) en recalant `segmentEndRef` avant de
//   reprendre.
//
//   Corollaire, et c'est un piège : la minuterie de segment ne doit **pas** être
//   réarmée sur `resume`. Dans l'enchaînement, `resume` précède `announceVerse`,
//   donc la fin de segment encore en place est celle du verset **précédent** —
//   déjà dépassée. L'armer là conclurait immédiatement sur une fin qui a déjà
//   eu lieu, et le passage avancerait de deux versets. C'est `announceVerse`
//   qui arme, après avoir recalé la borne, et `tick` qui réarme si la minuterie
//   a disparu (une pause l'annule).
//
// CE QUI N'EST PAS ICI, ET POURQUOI
//   `continuousAudioPosition` (`src/core/audio.ts:32`) n'est appelée **nulle
//   part** dans l'original : elle est définie et jamais utilisée. Le portage la
//   porte donc sans appelant, et `PassageAudioEngine.followContinuously(_:)`
//   reste sans appelant pour la même raison. Lui inventer ici un appel serait
//   ajouter au portage un comportement que l'application d'origine n'a pas.
//
// CE QUI RESTE À ÉPROUVER SUR UN APPAREIL
//   Que la lecture reprenne bien sans coupure audible entre deux versets d'une
//   même piste, que la coupure sur segment tombe avant le mot suivant, et que la
//   session audio tienne en arrière-plan. Aucun de ces trois points ne se mesure
//   sans appareil ; le reste de ce fichier se lit.

import Foundation
import AVFoundation

@MainActor
public final class PassageAudioExecutor {

    // MARK: - État observable

    /// La machine. Publique en lecture seule : on peut la sonder sans pouvoir la
    /// faire avancer autrement que par les entrées ci-dessous.
    public private(set) var engine = PassageAudioEngine()

    /// Le verset affiché — `nil` quand plus rien ne joue.
    public var onVerseChange: ((Int?) -> Void)?
    /// L'état publié par `setPlaying(...)` de l'original.
    public var onPlayingChange: ((Bool) -> Void)?
    /// Le message d'un refus, repris **tel quel** de l'original.
    public var onError: ((String) -> Void)?
    /// Progression, publiée au plus quatre fois par seconde.
    public var onProgress: ((Double, Double) -> Void)?

    public var reciter: Reciter = .default

    // MARK: - État interne

    private let player = AVPlayer()
    private let cache = VerseAudioCache()
    private let store: LocalStore

    /// La chronologie de la sourate en cours de lecture. C'est la seule
    /// information que la machine ne peut pas déduire seule.
    ///
    /// Elle vaut `nil` dès que la source réellement jouée n'est **pas** la
    /// piste horodatée : `announce` la relirait pour poser une fin de segment
    /// sur un fichier par verset, qui n'en a pas.
    private var timeline: ChapterAudio?

    /// La fin du segment horodaté du verset affiché, en secondes. `nil` pour un
    /// verset servi fichier par fichier : il n'y a alors pas de borne à couper,
    /// c'est la fin du fichier qui conclut.
    private var segmentEnd: Double?

    /// La source chargée, pour reconnaître qu'un verset se rejoue **sans**
    /// changer de fichier (`sameSource`, `PassageAudioPlayer.tsx:152`).
    private var sourceURL: URL?

    /// Le compteur de demandes — `requestRef.current` de l'original. Une
    /// résolution de source est asynchrone ; une demande plus récente doit
    /// pouvoir périmer la précédente, sinon un verset abandonné finirait par
    /// jouer par-dessus celui qu'on écoute.
    private var generation = 0

    private var ticker: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var boundaryTask: Task<Void, Never>?

    private var preloaded = Set<String>()
    private var unavailableUntil: [String: Date] = [:]
    private var inflight: [String: Task<ChapterAudio?, Never>] = [:]
    private var progressTick = Date.distantPast

    public init(store: LocalStore) {
        self.store = store
        // La notification de fin est enregistrée une fois pour toutes : elle ne
        // vise aucun item en particulier (`object: nil`), parce que les items
        // sont remplacés au fil des versets. Le jeton rendu n'est **pas**
        // conservé, et c'est délibéré : le bloc capture `self` faiblement, donc
        // il ne peut pas maintenir en vie un exécuteur disparu, et l'exécuteur
        // vit aussi longtemps que l'application.
        _ = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reportEnded() }
        }
        player.actionAtItemEnd = .pause
    }

    // MARK: - Entrées
    //
    // Aucune ne décide : elles transmettent à la machine, puis exécutent ce
    // qu'elle rend.

    /// « Lancer ce passage » — la boucle complète, avec les réglages choisis.
    public func begin(range: VerseRange, preferences: AudioRepeatPreferences) {
        apply(engine.begin(range: range, preferences: preferences))
    }

    /// `action === 'listen'` — `PassageAudioPlayer.tsx:229` : le verset affiché,
    /// **une** écoute, en mode « passage », arrêt automatique armé.
    ///
    /// Le silence et la vitesse sont conservés : l'original recopie
    /// `settingsRef.current` avant de n'en changer que trois.
    ///
    /// Le choix est forcé sur `.times(1)` et non sur `.custom` — et ce n'est pas
    /// un détail : `launchError` ne refuse que le champ **libre**, si bien qu'un
    /// « Autre » invalide resté dans les réglages refuserait ce lancement alors
    /// qu'aucun champ libre n'est utilisé ici.
    public func listen(verseID: Int, preferences: AudioRepeatPreferences) {
        var single = preferences
        single.countChoice = .times(1)
        single.repeatMode = .passage
        single.autoStop = true
        begin(range: VerseRange(start: verseID, end: verseID), preferences: single)
    }

    /// `playPause()` — `PassageAudioPlayer.tsx:231`.
    public func playPause() {
        apply(engine.playPause())
    }

    /// `jump(direction)` — `PassageAudioPlayer.tsx:229`.
    public func jump(_ direction: Int) {
        apply(engine.jump(direction))
    }

    /// `stop()` — `PassageAudioPlayer.tsx:102`.
    public func stop() {
        apply(engine.stop())
        stopTicker()
    }

    /// `setPlaybackRate` — `PassageAudioPlayer.tsx:227`. La vitesse est aussi
    /// retenue par la machine : c'est elle qui divise le délai de la coupure sur
    /// segment.
    public func setPreferences(_ updated: AudioRepeatPreferences) {
        apply(engine.setPreferences(updated))
    }

    public func select(reciter: Reciter) {
        self.reciter = reciter
        preloaded.removeAll()
    }

    /// `{playsInSilentMode: true, shouldPlayInBackground: true, interruptionMode:
    /// 'doNotMix'}` — `src/PassageAudioPlayer.tsx:186`.
    ///
    /// La catégorie `.playback` est celle qui autorise la lecture en arrière-plan
    /// (déclarée dans `Info.plist`), et `.spokenAudio` dit au système qu'il
    /// s'agit de parole — c'est ce qui donne aux commandes de l'écran verrouillé
    /// le comportement attendu pour une récitation.
    public func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: - Traduction des effets
    //
    // Le **seul** `switch` sur `PassageAudioEffect`. Il est volontairement sans
    // `default` : le jour où un effet est ajouté à l'énumération, la compilation
    // s'arrête ici. Un `default` l'avalerait en silence, et l'effet ne serait
    // exécuté nulle part — sans erreur, sans journal, sans symptôme autre qu'un
    // lecteur qui ne fait pas ce qu'on attend.

    /// Exécute les effets émis par la machine, puis republie l'état observable.
    private func apply(_ effects: [PassageAudioEffect]) {
        for effect in effects {
            perform(effect)
        }
        onPlayingChange?(isActive)
    }

    private func perform(_ effect: PassageAudioEffect) {
        switch effect {
        case .load(let position):
            load(position)
        case .resume:
            player.play()
        case .pause:
            player.pause()
        case .stop:
            releasePlayer()
        case .scheduleWait(let milliseconds, _):
            schedule(milliseconds: milliseconds)
        case .cancelWait:
            cancelWait()
        case .setRate(let speed):
            applyRate(speed)
        case .announceVerse(let identifier):
            announce(identifier)
        case .fail(let message):
            onError?(message)
        }
    }

    /// Vrai pendant le chargement **et** pendant la lecture.
    ///
    /// C'est ce que l'original publie : `startAt` fait `setPlaying(true)` avant
    /// même d'avoir résolu la source, si bien que le bouton lecture/pause du
    /// mini-lecteur affiche « pause » dès le premier appui. Et c'est faux pendant
    /// une attente : `finishBoundary` fait `isPlayingRef.current=false` avant de
    /// planifier.
    private var isActive: Bool {
        switch engine.phase {
        case .playing, .loading:
            return true
        case .idle, .paused, .waiting, .completed:
            return false
        }
    }

    // MARK: - Les effets, un par un

    /// `.load` — résoudre la source, la mettre en place, chercher le début du
    /// segment, puis jouer.
    private func load(_ position: AudioPosition) {
        startTicker()
        generation += 1
        let request = generation
        let reciter = self.reciter
        cancelBoundary()

        // `Quran.verseAt` **piège** hors bornes (`precondition`), là où
        // `VerseAudio.url` rend `nil`. On ne l'appelle donc qu'après la borne.
        guard position.verseID >= 1, position.verseID <= Quran.verses.count else {
            apply(engine.loadFailed(Self.unreachableMessage))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let source = await self.resolve(verseID: position.verseID, reciter: reciter)
            // Une demande plus récente a pris la main : celle-ci est périmée.
            guard self.generation == request else { return }
            guard let source else {
                self.apply(self.engine.loadFailed(Self.unreachableMessage))
                return
            }
            await self.start(source, position: position, request: request)
        }
    }

    /// `PassageAudioPlayer.tsx:141-153` — la piste horodatée d'abord, les
    /// fichiers par verset ensuite.
    private func resolve(verseID: Int, reciter: Reciter) async -> Source? {
        let chapter = Quran.verseAt(verseID).surah
        let fetched = await chapterTimeline(chapter: chapter, verseID: verseID, reciter: reciter)

        if let fetched, let span = fetched.verses[verseID], let url = URL(string: fetched.url) {
            timeline = fetched
            return Source(url: url, start: span.start, usesTimeline: true)
        }

        // La chronologie n'est **pas** retenue quand elle n'est pas utilisée :
        // `announce` la relirait pour poser une fin de segment sur un fichier
        // par verset, qui n'en a pas — et la coupure tomberait alors à un
        // horodatage de sourate sur un fichier d'un seul verset.
        timeline = nil
        guard let remote = VerseAudio.url(verseID: verseID, reciter: reciter) else { return nil }
        let local = await cache.cachedURL(for: remote)
        return Source(url: local, start: nil, usesTimeline: false)
    }

    /// La chronologie d'une sourate, du stockage local ou de quran.com.
    ///
    /// `quranAudioTimeline.ts:8-27` : un récitateur sans identifiant de récitation
    /// de sourate n'en a pas — `chapterResourceID` rend alors `nil` et l'appelant
    /// retombe sur les fichiers par verset. Une chronologie dont le
    /// téléchargement a échoué n'est pas redemandée pendant cinq minutes.
    private func chapterTimeline(chapter: Int, verseID: Int, reciter: Reciter) async -> ChapterAudio? {
        guard let resource = PassageAudio.chapterResourceID(for: reciter.id) else { return nil }
        let key = ChapterAudioCache.key(resource: resource, chapter: chapter)

        if let until = unavailableUntil[key], until > Date() { return nil }
        // Une seule requête en vol par sourate : trois versets préchargés ne
        // doivent pas produire trois téléchargements du même document.
        if let running = inflight[key] { return await running.value }

        let task = Task { [weak self] () -> ChapterAudio? in
            guard let self else { return nil }
            return await self.fetchTimeline(key: key, resource: resource, chapter: chapter, verseID: verseID)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if result == nil {
            unavailableUntil[key] = Date().addingTimeInterval(ChapterAudioCache.unavailableInterval)
        }
        return result
    }

    private func fetchTimeline(key: String, resource: Int, chapter: Int, verseID: Int) async -> ChapterAudio? {
        // Le cache n'est relu que s'il est **utilisable** : une seule borne
        // fausse le fait jeter et recharger (`quranAudioTimeline.ts:17`).
        if let cached = await store.loadChapterAudio(key),
           PassageAudio.isUsableCachedChapter(cached, verseID: verseID, chapterNumber: chapter) {
            return cached
        }
        guard let url = URL(string:
            "https://api.quran.com/api/v4/chapter_recitations/\(resource)/\(chapter)?segments=true"
        ) else { return nil }

        var request = URLRequest(url: url)
        // `quranAudioTimeline.ts:18` — `setTimeout(() => controller.abort(), 10000)`.
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            let root = try JSONDecoder().decode(JSONValue.self, from: data)
            let parsed = try PassageAudio.parse(file: root["audio_file"], chapter: chapter)
            try? await store.saveChapterAudio(parsed, key: key)
            return parsed
        } catch {
            // Un échec n'est jamais visible : la lecture continue avec les
            // fichiers par verset, exactement comme dans l'original.
            return nil
        }
    }

    /// Met la source en place et joue — `PassageAudioPlayer.tsx:155-172`.
    private func start(_ source: Source, position: AudioPosition, request: Int) async {
        guard generation == request else { return }
        configureSession()

        let sameSource = sourceURL == source.url
        if !sameSource {
            player.replaceCurrentItem(with: AVPlayerItem(url: source.url))
            sourceURL = source.url
        }
        applyRate(engine.preferences.speed)

        // L'original cherche dès que la source est la même **ou** qu'un début de
        // segment existe : un lecteur arrivé à la fin du fichier reste à la fin,
        // et il faut le rembobiner même quand la répétition suivante utilise
        // exactement le même verset et la même URL.
        if sameSource || source.start != nil {
            // Tolérance nulle : quelques centièmes de seconde de décalage
            // suffiraient à faire entendre la fin du verset précédent.
            _ = await player.seek(
                to: CMTime(seconds: source.start ?? 0, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        guard generation == request else { return }

        player.play()
        apply(engine.loadSucceeded())

        // La piste horodatée d'une sourate est **un seul** fichier : il n'y a
        // rien à précharger verset par verset.
        if !source.usesTimeline {
            prefetch(from: position.verseID)
        }
    }

    /// `PassageAudioPlayer.tsx:139` — les trois versets suivants, en tâche de
    /// fond, sans jamais faire attendre la lecture en cours.
    private func prefetch(from verseID: Int) {
        let reciter = self.reciter
        let urls = (1...3).compactMap { offset in
            VerseAudio.url(verseID: verseID + offset, reciter: reciter)
        }
        Task { [weak self] in
            for url in urls {
                let key = url.absoluteString
                guard let self else { return }
                guard !self.preloaded.contains(key) else { continue }
                self.preloaded.insert(key)
                await self.cache.prefetch(url)
            }
        }
    }

    /// `.scheduleWait` — le délai est celui que la machine a calculé, et c'est
    /// elle qui décide au réveil s'il s'agit d'une reprise enchaînée ou d'un
    /// rechargement (`waitElapsed`). La position n'est donc pas transmise : la
    /// machine la tient déjà dans sa phase.
    private func schedule(milliseconds: Int) {
        cancelWait()
        let request = generation
        let delay = max(0, milliseconds)
        waitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            guard let self, !Task.isCancelled, self.generation == request else { return }
            self.apply(self.engine.waitElapsed())
        }
    }

    private func cancelWait() {
        waitTask?.cancel()
        waitTask = nil
    }

    /// La fin d'un **segment horodaté** doit couper net, avant le mot suivant.
    ///
    /// `PassageAudioPlayer.tsx:82-95` arme pour cela une minuterie visant
    /// l'échéance exacte, calculée sur l'horloge **native** du lecteur et divisée
    /// par la vitesse — pas sur la position du dernier événement de statut, qui
    /// arrive en retard.
    private func armBoundary() {
        cancelBoundary()
        guard let end = segmentEnd, case .playing = engine.phase else { return }
        let speed = engine.preferences.speed
        guard speed > 0 else { return }

        let remaining = (end - player.currentTime().seconds) * 1000 / speed
        // Une échéance absurde n'a pas à être planifiée : `tick` la rattrapera au
        // quart de seconde. Le garde évite surtout de convertir en `UInt64` une
        // valeur qui déborderait.
        guard remaining.isFinite, remaining <= 86_400_000 else { return }
        if remaining <= 0 {
            reportEnded()
            return
        }

        let request = generation
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining.rounded(.up)) * 1_000_000)
            guard let self, !Task.isCancelled, self.generation == request else { return }
            guard case .playing = self.engine.phase else { return }
            // Une mise en mémoire tampon a pu arrêter l'horloge avant l'échéance :
            // on réarme au lieu de conclure.
            if self.player.currentTime().seconds < end {
                self.armBoundary()
                return
            }
            self.reportEnded()
        }
    }

    private func cancelBoundary() {
        boundaryTask?.cancel()
        boundaryTask = nil
    }

    /// `.announceVerse` — publier le verset affiché, **et** recaler la fin de
    /// segment. Voir l'en-tête : c'est le point qu'on ne devine pas.
    private func announce(_ identifier: Int?) {
        if let identifier {
            segmentEnd = timeline?.verses[identifier]?.end
        } else {
            segmentEnd = nil
        }
        onVerseChange?(identifier)
        armBoundary()
    }

    /// `player.setPlaybackRate(speed)` — `PassageAudioPlayer.tsx:157`.
    ///
    /// `AVPlayer.rate` **démarre** la lecture dès qu'il devient positif : le
    /// poser sur un lecteur en pause relancerait la lecture. `defaultRate` est
    /// donc la vitesse retenue pour le prochain `play()`, et `rate` n'est
    /// réécrit que si le lecteur joue déjà.
    private func applyRate(_ speed: Double) {
        guard speed.isFinite, speed > 0 else { return }
        let value = Float(speed)
        player.defaultRate = value
        if player.timeControlStatus == .playing {
            player.rate = value
        }
    }

    /// `.stop` — arrêter **et libérer**.
    private func releasePlayer() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        sourceURL = nil
        segmentEnd = nil
        timeline = nil
    }

    // MARK: - Ce qu'AVFoundation rapporte

    /// Les trois fins de lecture aboutissent ici — `PassageAudioPlayer.tsx:213`.
    ///
    /// Le garde est celui de l'original (`!isPlayingRef.current`) : une fin
    /// signalée alors que la machine ne joue plus — une attente est déjà
    /// planifiée — ne doit **pas** faire avancer le passage une deuxième fois.
    /// C'est aussi ce qui rend inoffensif le fait que la minuterie de segment et
    /// l'horloge périodique puissent constater la même fin à quelques
    /// millisecondes d'écart.
    private func reportEnded() {
        guard case .playing = engine.phase else { return }
        cancelBoundary()
        apply(engine.finish(timelineCoversNextVerse: timelineCoversNextVerse()))
    }

    /// Ce que la machine ne peut pas déduire seule : la piste horodatée de la
    /// sourate porte-t-elle le verset suivant ?
    ///
    /// C'est une **lecture** de la chronologie, pas une décision — l'original
    /// fait la même lecture pour `pendingContinuationRef`
    /// (`PassageAudioPlayer.tsx:196`). La machine y ajoute ses propres
    /// conditions : le verset suivant doit être exactement le suivant, et rester
    /// dans la plage.
    private func timelineCoversNextVerse() -> Bool {
        guard let timeline, let current = engine.phase.position else { return false }
        return timeline.verses[current.verseID + 1] != nil
    }

    // MARK: - L'horloge

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Quatre fois par seconde. Elle sert à quatre choses, et à rien d'autre :
    /// publier la progression, constater une source en échec — le `status.error`
    /// de l'original, `PassageAudioPlayer.tsx:210` —, réarmer la coupure sur
    /// segment quand une pause l'a annulée, et rattraper une fin de lecture que
    /// la notification n'a pas signalée (`fileFinished`, `:214`).
    ///
    /// La finesse n'a pas besoin d'être meilleure : la fin de **segment** est
    /// surveillée par `armBoundary`, qui vise l'échéance exacte.
    private func tick() {
        guard isActive else { return }

        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? 0

        if Date().timeIntervalSince(progressTick) > 0.25 {
            progressTick = Date()
            onProgress?(max(0, seconds), duration.isFinite && duration > 0 ? duration : 0)
        }

        if player.currentItem?.status == .failed {
            // Une source en échec est terminale dans les deux états, mais la
            // machine n'a d'entrée que pour l'échec d'un **chargement**. On
            // conclut donc par `stop()`, qui la ramène au repos et libère le
            // lecteur, puis on rapporte le message de l'original. Sans cela,
            // `tick` rappellerait `loadFailed` quatre fois par seconde et le
            // passage resterait suspendu, en silence.
            let message = Self.unreachableMessage
            if case .loading = engine.phase {
                player.pause()
                apply(engine.loadFailed(message))
            } else {
                apply(engine.stop())
                onError?(message)
            }
            return
        }

        // Les deux fins qui se mesurent sur l'horloge. `didJustFinish`, la
        // troisième, arrive par notification.
        guard case .playing = engine.phase else { return }
        // Une pause annule la minuterie : on la réarme ici plutôt que sur
        // `resume`, où la borne encore en place serait celle du verset
        // précédent — voir l'en-tête.
        if boundaryTask == nil { armBoundary() }

        if let segmentEnd, seconds >= segmentEnd {
            reportEnded()
            return
        }
        if duration.isFinite, duration > 0, seconds >= duration {
            reportEnded()
        }
    }

    // MARK: - Types internes

    /// Une source prête à jouer : l'URL, et — pour une piste horodatée — le
    /// début du verset dans cette piste.
    ///
    /// La **fin** du segment n'est pas portée ici : elle est posée par
    /// `announce`, à partir de la chronologie retenue, parce que c'est aussi par
    /// là que passe l'enchaînement d'un verset au suivant, qui ne recharge
    /// aucune source.
    private struct Source {
        var url: URL
        var start: Double?
        var usesTimeline: Bool
    }

    /// `PassageAudioPlayer.tsx:173` et `:211` — le message de l'original quand
    /// une source n'a pas pu être obtenue.
    private static let unreachableMessage = "Lecture indisponible. Vérifie ta connexion."
}
