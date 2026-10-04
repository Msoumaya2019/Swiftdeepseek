// PassageAudioEngine.swift
// La machine d'état de la boucle de répétition — portée de
// `src/PassageAudioPlayer.tsx`, sans AVFoundation.
//
// POURQUOI SÉPARER LA DÉCISION DE L'EFFET
//   `Core/PassageAudio.swift` décide *quelle* position vient ensuite et *combien
//   de temps* attendre. Ce fichier décide **ce qu'on en fait** : charger,
//   reprendre, mettre en pause, planifier l'attente, s'arrêter. Aucune des deux
//   ne joue de son. C'est délibéré : la partie qui décide se prouve par un banc
//   sur cette machine, et la partie qui joue se réduit à exécuter les effets
//   émis. Une boucle de lecture qu'on ne peut pas éprouver sans appareil devient
//   une boucle dont on éprouve toutes les transitions.
//
// LES QUATRE RÈGLES SILENCIEUSES DE LA BOUCLE
//   S'y tromper ne lève aucune erreur : cela répète un passage une fois de trop,
//   l'arrête une fois trop tôt, ou fait perdre le silence choisi.
//
//   1. `finish` ne conclut que sur `nil`. Tant que `next` rend une position, on
//      enchaîne — même si cette position est identique à la courante (mode
//      « verset par verset » avec un compte > 1).
//   2. Le silence choisi ne s'applique QUE sur un redémarrage de passage ou sur
//      un verset répété. Ailleurs, la marge technique de 200 ms est seule.
//   3. Un verset qui suit immédiatement le courant, DANS LA MÊME PISTE
//      horodatée, se **reprend** (`resume`) au lieu d'être rechargé : la lecture
//      ne s'interrompt pas entre deux versets d'une sourate.
//   4. Mettre en pause pendant l'attente **mémorise le temps restant**. Reprendre
//      ne rejoue pas l'attente entière.
//
// LES VALEURS ATTENDUES SONT MESURÉES
//   Les tables de `Tests/PassageAudioEngineTests.swift` viennent de
//   `_banc/oracle-audio.mjs`, qui charge le **vrai** `src/PassageAudioPlayer.tsx`
//   et `src/core/audio.ts` par empaquetage `esbuild`, et vérifie que les lignes
//   décisives de ce portage s'y trouvent **et dans l'ordre**.

import Foundation

/// L'état de la boucle. Un seul état à la fois : c'est ce qui remplace les cinq
/// références parallèles de l'original (`playing`, `loading`, `pendingRef`,
/// `timerRef`, `completedRef`), dont la cohérence mutuelle n'était garantie par
/// rien.
public enum PassageAudioPhase: Equatable, Sendable {
    /// Rien n'est chargé, rien n'est planifié.
    case idle
    /// Une source est en cours de résolution pour cette position.
    case loading(AudioPosition)
    /// La source joue.
    case playing(AudioPosition)
    /// La source est chargée mais arrêtée.
    case paused(AudioPosition)
    /// Le verset est fini, le suivant est planifié dans `milliseconds`.
    case waiting(next: AudioPosition, milliseconds: Int)
    /// Le passage est allé à son terme, ou le compte l'a arrêté.
    case completed(AudioPosition)

    /// La position que la boucle tient, quel que soit l'état — `positionRef`.
    public var position: AudioPosition? {
        switch self {
        case .idle: return nil
        case .loading(let position), .playing(let position),
             .paused(let position), .completed(let position):
            return position
        case .waiting(let next, _):
            return next
        }
    }
}

/// Ce que la machine demande de faire. C'est le **seul** couplage avec
/// AVFoundation : un exécuteur traduit ces effets en appels au lecteur.
public enum PassageAudioEffect: Equatable, Sendable {
    /// Résoudre la source de cette position, chercher le début du segment,
    /// puis jouer.
    case load(AudioPosition)
    /// Le lecteur est déjà sur la bonne source : reprendre sans recharger.
    case resume
    /// Arrêter le lecteur sans libérer la source.
    case pause
    /// Arrêter et libérer.
    case stop
    /// Planifier `next` dans `milliseconds`.
    case scheduleWait(milliseconds: Int, next: AudioPosition)
    /// Annuler l'attente planifiée.
    case cancelWait
    /// Appliquer la vitesse.
    case setRate(Double)
    /// Signaler le verset affiché — `nil` quand plus rien ne joue.
    case announceVerse(Int?)
    /// Signaler un refus, avec le message de l'original.
    case fail(String)
}

/// La boucle de répétition.
///
/// Elle est `mutating` : chaque entrée rend la liste des effets à exécuter, et
/// laisse l'objet dans son nouvel état. Rien n'est asynchrone ici — un exécuteur
/// rappelle `loadSucceeded()` ou `loadFailed(_:)` quand AVFoundation a fini.
public struct PassageAudioEngine: Sendable {

    public private(set) var phase: PassageAudioPhase = .idle
    public private(set) var range: VerseRange?
    public private(set) var preferences = AudioRepeatPreferences.defaults

    /// Le temps qui restait quand on a mis en pause **pendant** une attente.
    /// `nil` hors attente : c'est ce qui distingue « reprendre l'attente » de
    /// « relancer la lecture ».
    ///
    /// Une structure plutôt qu'un tuple : un tuple stocké n'est `Sendable` que
    /// par tolérance du compilateur, et cette tolérance se paie ailleurs.
    private struct PendingWait: Equatable, Sendable {
        var next: AudioPosition
        var milliseconds: Int
    }

    private var pendingWait: PendingWait?

    public init() {}

    // MARK: - Entrées

    /// `begin()` — `PassageAudioPlayer.tsx:175-179`.
    ///
    /// L'ordre compte : la plage est résolue **avant** le refus du compte. Une
    /// plage invalide l'emporte donc sur un champ libre invalide, et c'est ce que
    /// l'original fait. `launchError` porte déjà le refus de `:176`, et il est
    /// plus étroit que la normalisation de `:79` — `'1.5'` et `'5000'` sont
    /// refusés au lancement, alors que la normalisation en ferait 1 et 5000.
    public mutating func begin(range requested: VerseRange, preferences: AudioRepeatPreferences) -> [PassageAudioEffect] {
        do {
            let resolved = try PassageAudio.range(start: requested.start, end: requested.end)
            if let refusal = preferences.launchError {
                throw refusal
            }
            self.range = resolved
            self.preferences = preferences
            pendingWait = nil
            return start(at: AudioPosition(verseID: resolved.start, repetition: 1))
        } catch {
            let message = (error as? PassageAudioError)?.message ?? "Passage invalide."
            return [.fail(message)]
        }
    }

    /// Le verset courant est allé au bout de son segment.
    ///
    /// `timelineCoversNextVerse` dit si la **piste horodatée** de la sourate
    /// porte le verset suivant. C'est la seule information que la machine ne
    /// peut pas déduire seule, et elle décide entre `resume` et `load`.
    /// `PassageAudioPlayer.tsx:187-209`.
    public mutating func finish(timelineCoversNextVerse: Bool) -> [PassageAudioEffect] {
        guard let range, let current = phase.position else { return [] }

        let following: AudioPosition?
        do {
            following = try PassageAudio.next(
                range: range,
                current: current,
                mode: preferences.repeatMode,
                count: preferences.count,
                autoStop: preferences.autoStop
            )
        } catch {
            return [.fail((error as? PassageAudioError)?.message ?? "Position audio invalide.")]
        }

        // Règle 1 : `nil` est le SEUL cas où l'on conclut.
        guard let next = following else {
            phase = .completed(current)
            pendingWait = nil
            return [.pause, .cancelWait, .announceVerse(nil)]
        }

        // Règle 2 : le silence choisi ne s'applique qu'ici.
        let wait = PassageAudio.waitMilliseconds(
            from: current,
            to: next,
            range: range,
            mode: preferences.repeatMode,
            gapSeconds: preferences.gap
        )

        // Règle 3 : la reprise est réservée au verset qui suit immédiatement,
        // dans la même piste.
        let continuation = timelineCoversNextVerse
            && next.verseID == current.verseID + 1
            && next.verseID <= range.end

        phase = .waiting(next: next, milliseconds: wait)
        pendingWait = continuation ? PendingWait(next: next, milliseconds: wait) : nil
        // La piste horodatée doit s'arrêter net, avant le mot suivant : on met
        // en pause, puis on planifie.
        return [.pause, .scheduleWait(milliseconds: wait, next: next)]
    }

    /// L'attente planifiée est arrivée à son terme.
    public mutating func waitElapsed() -> [PassageAudioEffect] {
        guard case .waiting(let next, _) = phase else { return [] }
        // Règle 4 : `pendingWait` non nul = c'était une reprise enchaînée.
        let wasContinuation = pendingWait?.next == next
        pendingWait = nil
        if wasContinuation {
            phase = .playing(next)
            return [.resume, .announceVerse(next.verseID)]
        }
        return start(at: next)
    }

    /// La source est prête : la lecture commence.
    public mutating func loadSucceeded() -> [PassageAudioEffect] {
        guard case .loading(let position) = phase else { return [] }
        phase = .playing(position)
        return [.announceVerse(position.verseID)]
    }

    /// La source n'a pas pu être chargée — `PassageAudioPlayer.tsx:173`.
    public mutating func loadFailed(_ message: String) -> [PassageAudioEffect] {
        guard case .loading(let position) = phase else { return [] }
        phase = .completed(position)
        pendingWait = nil
        return [.fail(message), .announceVerse(nil)]
    }

    /// `playPause()` — `PassageAudioPlayer.tsx:231`.
    ///
    /// Cinq branches, et l'ordre compte : un chargement en cours s'annule, une
    /// attente se suspend en gardant son temps restant, un état terminé
    /// **relance** le passage au lieu de reprendre.
    public mutating func playPause() -> [PassageAudioEffect] {
        switch phase {
        case .idle:
            return [.fail("Aucun passage sélectionné.")]

        case .loading(let position):
            // Un chargement qu'on interrompt n'est pas une erreur : on revient
            // à la position, en pause.
            phase = .paused(position)
            return [.pause, .cancelWait]

        case .playing(let position):
            phase = .paused(position)
            return [.pause, .cancelWait]

        case .waiting(let next, let milliseconds):
            // Règle 4 : on mémorise ce qui restait, on ne le rejoue pas.
            pendingWait = PendingWait(next: next, milliseconds: milliseconds)
            phase = .paused(next)
            return [.pause, .cancelWait]

        case .paused(let position):
            if let pending = pendingWait {
                // Le temps restant est celui de l'attente, pas sa durée totale.
                phase = .waiting(next: pending.next, milliseconds: pending.milliseconds)
                pendingWait = nil
                return [.scheduleWait(milliseconds: pending.milliseconds, next: pending.next)]
            }
            phase = .playing(position)
            return [.resume]

        case .completed:
            guard let range else { return [] }
            pendingWait = nil
            return start(at: AudioPosition(verseID: range.start, repetition: 1))
        }
    }

    /// `stop()` — `PassageAudioPlayer.tsx:102`.
    public mutating func stop() -> [PassageAudioEffect] {
        let hadSource = phase != .idle
        phase = .idle
        range = nil
        pendingWait = nil
        return hadSource ? [.stop, .cancelWait, .announceVerse(nil)] : []
    }

    /// `jump(direction)` — `PassageAudioPlayer.tsx:229`.
    ///
    /// La borne est **clampée** dans la plage : au premier verset, « précédent »
    /// relance le premier verset au lieu de sortir du passage.
    public mutating func jump(_ direction: Int) -> [PassageAudioEffect] {
        guard let range, let current = phase.position else { return [] }
        let target = max(range.start, min(range.end, current.verseID + direction))
        pendingWait = nil
        return start(at: AudioPosition(verseID: target, repetition: 1))
    }

    /// `PassageAudioPlayer.tsx:227` — changer la vitesse pendant la lecture
    /// réarme la borne, sans changer de verset.
    public mutating func setPreferences(_ updated: AudioRepeatPreferences) -> [PassageAudioEffect] {
        let previous = preferences
        preferences = updated
        guard updated.speed != previous.speed else { return [] }
        switch phase {
        case .playing, .waiting:
            return [.setRate(updated.speed)]
        default:
            return []
        }
    }

    /// La position affichée avance dans la piste sans changer de répétition —
    /// `continuousAudioPosition`. La machine ne joue rien : elle recale son état.
    public mutating func followContinuously(_ position: AudioPosition) -> [PassageAudioEffect] {
        switch phase {
        case .playing(let current):
            guard position != current else { return [] }
            phase = .playing(position)
            return [.announceVerse(position.verseID)]
        default:
            return []
        }
    }

    // MARK: - Interne

    private mutating func start(at position: AudioPosition) -> [PassageAudioEffect] {
        pendingWait = nil
        phase = .loading(position)
        return [.load(position)]
    }
}
