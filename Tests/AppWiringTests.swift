// AppWiringTests.swift
// Le câblage de l'application : ce qui va de la configuration vers l'application,
// et des services vers les vues.
//
// POURQUOI CES TESTS
//   Deux défauts silencieux se cachent dans ce câblage, et aucun ne se voit à
//   l'écran :
//
//   1. `AppViewModel` expose `audio`, `sync` et `connectivity` comme des objets
//      observables SÉPARÉS de lui. SwiftUI ne réévalue une vue que pour les
//      objets qu'elle observe : sans relais explicite de leur `objectWillChange`,
//      une vue qui lit `model.audio.isPlaying` s'affiche correctement une fois,
//      puis ne se met plus jamais à jour.
//
//   2. Dans un `.xcconfig`, `//` commence un commentaire même au milieu d'une
//      valeur. Une URL écrite telle quelle devient `https:` — une valeur non
//      vide, donc considérée comme configurée, mais inutilisable.
//
//   Les deux se manifestent par « l'application s'affiche, mais ne fait rien ».

import Combine
import XCTest
@testable import Swiftdeepseek

@MainActor
final class AppWiringTests: XCTestCase {

    // MARK: Les changements des services atteignent les vues

    /// Le relais `audio.objectWillChange` → `AppViewModel.objectWillChange`.
    ///
    /// Falsifiable : retirer le relais dans `AppViewModel.init` fait échouer ce
    /// test, et c'est exactement le défaut — le bouton lecture/pause du
    /// mini-lecteur resterait figé, et la mise en évidence du verset en cours de
    /// récitation ne suivrait pas.
    ///
    /// Le récitateur choisi est **différent** du récitateur courant : le test ne
    /// dépend donc pas du fait que `@Published` annonce aussi une affectation
    /// sans changement de valeur.
    ///
    /// Attention à ne pas comparer `other` au récitateur APRÈS l'avoir affecté —
    /// les deux sont alors égaux par construction. C'est l'erreur qu'a commise la
    /// première version de ce test (échec #15) : elle échouait toujours, et pour
    /// une raison qui n'avait rien à voir avec le relais testé.
    func testChangesToTheAudioServiceAreRepublishedByTheViewModel() throws {
        let model = AppViewModel()

        var notifications = 0
        let token = model.objectWillChange.sink { _ in notifications += 1 }
        defer { token.cancel() }

        let before = model.audio.reciter
        let other = try XCTUnwrap(
            Reciter.all.first { $0 != before },
            "Il faut au moins deux récitateurs distincts pour que ce test ait un sens."
        )

        model.audio.select(reciter: other)

        XCTAssertEqual(model.audio.reciter, other, "La sélection doit avoir pris effet.")
        XCTAssertGreaterThan(
            notifications,
            0,
            "Un changement de l'audio doit être annoncé par le modèle : sans cela, aucune vue ne se réévalue."
        )
    }

    // MARK: La configuration arrive bien dans l'application

    /// Vérifie que `SLASH` a bien protégé l'URL dans `Secrets.xcconfig`.
    ///
    /// Écrit sans les secrets, l'URL vaut `https:` : non vide, donc
    /// `isConfigured` est vrai, mais l'hôte est absent. C'est précisément le
    /// piège que ce test attrape. Il est ignoré quand la configuration est
    /// absente — l'intégration continue compile aussi sans secrets.
    func testTheConfiguredURLIsUsableWhenTheSecretsArePresent() throws {
        try XCTSkipUnless(
            AppConfig.isConfigured,
            "Secrets absents : la compilation a lieu sans configuration, c'est un état supporté."
        )

        let url = AppConfig.supabaseURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(
            url.host?.hasSuffix(".supabase.co"),
            true,
            "Hôte inattendu (\(url.host ?? "aucun")) : l'URL a probablement été tronquée par un « // » pris pour un commentaire."
        )
        XCTAssertFalse(AppConfig.supabasePublishableKey.isEmpty)
    }

    /// La clé ne doit jamais être une clé `service_role` : elle contourne RLS et
    /// n'a rien à faire dans une application distribuée.
    func testTheEmbeddedKeyIsAPublishableKeyAndNeverAServiceRoleKey() throws {
        try XCTSkipUnless(AppConfig.isConfigured, "Secrets absents.")

        let key = AppConfig.supabasePublishableKey
        XCTAssertFalse(key.contains("service_role"), "Une clé service_role est présente dans l'application.")
        XCTAssertTrue(
            key.hasPrefix("sb_publishable_") || key.split(separator: ".").count == 3,
            "La clé embarquée n'est ni une clé publiante (`sb_publishable_…`) ni un JWT anon : \(key.prefix(12))…"
        )
    }
}
