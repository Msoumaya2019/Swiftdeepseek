// AppViewModel.swift
// Chef d'orchestre de l'application : authentification, état, synchronisation.
//
// Correspondance : `src/App.tsx` côté React Native, qui tient le même rôle.
// Les vues ne parlent jamais directement à Supabase ni au stockage : elles
// passent par ici.

import Combine
import SwiftUI

@MainActor
public final class AppViewModel: ObservableObject {

    @Published public private(set) var state: AppState
    @Published public var selectedTab: MainTab = .home
    @Published public var notice: String?

    public let auth: AuthService
    public let repository: AppStateRepository
    public let sync: StateSyncService
    public let connectivity: ConnectivityService
    public let audio: AudioService
    public let sources: QuranSourceService
    public let social: SocialService

    private let store: LocalStore
    private let client: SupabaseRESTClient
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let client = SupabaseRESTClient(
            baseURL: AppConfig.supabaseURL,
            publishableKey: AppConfig.supabasePublishableKey
        )
        let store = LocalStore()
        let auth = AuthService(client: client)
        let repository = AppStateRepository(store: store)

        self.client = client
        self.store = store
        self.auth = auth
        self.repository = repository
        self.sync = StateSyncService(client: client, auth: auth, store: store, repository: repository)
        self.connectivity = ConnectivityService()
        self.audio = AudioService()
        self.sources = QuranSourceService()
        self.social = SocialService(client: client)
        self.state = repository.state

        // Les vues observent ce modèle ; on répercute les changements du dépôt.
        repository.$state
            .sink { [weak self] value in self?.state = value }
            .store(in: &cancellables)

        // Les services sont des objets observables SÉPARÉS du modèle. Sans ce
        // relais, une vue qui lit `model.audio.isPlaying` ou
        // `model.connectivity.isOffline` ne serait jamais réévaluée quand la
        // valeur change : le bouton lecture/pause du mini-lecteur resterait figé,
        // la mise en évidence du verset en cours de récitation ne suivrait pas,
        // et une bannière « hors ligne » n'apparaîtrait jamais. Le défaut est
        // silencieux — la vue s'affiche, simplement elle ne se met plus à jour.
        for publisher in [audio.objectWillChange, sync.objectWillChange, connectivity.objectWillChange] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
    }

    // MARK: Démarrage

    public func start() async {
        await auth.restore()
        connectivity.start { [weak self] in
            await self?.sync.flush()
        }
        if auth.userId != nil {
            await sync.syncOnSignIn()
            audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
        }
        await sync.refreshPendingCount()
    }

    /// Ouvre l'application sur la dernière page lue — comportement de reprise
    /// de l'application actuelle (`state.lastRead`).
    public var resumePage: Int {
        repository.state.lastRead?.page ?? 1
    }

    public var edition: QuranEdition {
        QuranEdition(rawValue: repository.state.reader?.mushaf ?? "") ?? .medine
    }

    // MARK: Connexion

    /// Jeton d'accès à jour pour les appels sociaux. Rafraîchit la session si
    /// elle est près d'expirer — l'application React Native fait de même
    /// (`supabase.auth.getSession()` avant chaque requête).
    public func socialAccessToken() async -> String? {
        try? await auth.validAccessToken()
    }

    public func signIn(email: String, password: String) async {
        do {
            _ = try await auth.signIn(email: email, password: password)
            await sync.syncOnSignIn()
            audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
        } catch {
            notice = error.localizedDescription
        }
    }

    public func signOut() async {
        await auth.signOut()
        await repository.load(userId: nil)
        selectedTab = .home
    }

    // MARK: Mutations

    /// Toute modification passe par ici : écriture locale immédiate, puis
    /// synchronisation en tâche de fond. C'est ce qui rend l'application
    /// utilisable sans réseau.
    public func update(_ transform: @escaping (AppState) -> AppState) {
        Task {
            await repository.mutate(transform)
            await sync.flush()
        }
    }

    /// Enregistre la page atteinte à la fermeture du lecteur.
    public func recordReading(page: Int) {
        let verseID = Quran.pageRange(page)?.start
        update { state in
            var next = state
            var readPages = next.readPages ?? []
            if !readPages.contains(page) { readPages.append(page) }
            next.readPages = readPages.sorted()
            next.lastRead = LastRead(
                page: page,
                verseId: verseID ?? state.lastRead?.verseId ?? 1,
                readAt: DateKeys.iso(Date())
            )
            if next.reader?.mushaf == "coranTest" {
                next.reader?.testPage = page
            }
            return next
        }
    }

    public func setEdition(_ edition: QuranEdition) {
        update { state in
            var next = state
            var reader = next.reader ?? ReaderPreferences(mushaf: edition.rawValue, followAudio: true)
            reader.mushaf = edition.rawValue
            next.reader = reader
            return next
        }
    }

    public func selectReciter(_ reciter: Reciter) {
        audio.select(reciter: reciter)
        update { state in
            var next = state
            next.audioPreferences = AudioPreferences(reciterId: reciter.id)
            return next
        }
    }

    // MARK: Indicateurs pour les vues

    public var progress: (quran: Double, goal: Double, goalKnown: Int, goalTotal: Int) {
        state.progress()
    }

    public var stats: WeeklyProgress.SessionStats {
        WeeklyProgress.stats(state)
    }

    public var weekly: WeeklyProgress.Summary {
        WeeklyProgress.weeklyProgress(state)
    }

    public var upcoming: [Session] {
        WeeklyProgress.upcomingSessions(state)
    }

    public var todaySessions: [Session] {
        let today = DateKeys.today()
        return state.sessions
            .filter { WeeklyProgress.scheduledDate($0) == today && $0.status == .todo }
            .sorted { $0.start < $1.start }
    }

    public var palette: Palette {
        var base = Theme.palette(named: state.theme)
        if let accentName = state.accent, let accent = Theme.accents[accentName] {
            base.green = accent.primary
            base.green2 = accent.primary
            base.selected = accent.soft
            base.surahBadge = accent.soft
            base.progress = accent.soft
        } else if state.theme == "white" || state.theme == nil {
            let accent = Theme.accents["prune"]!
            base.green = accent.primary
            base.green2 = accent.primary
            base.selected = accent.soft
            base.surahBadge = accent.soft
            base.progress = accent.soft
        }
        return base
    }
}
