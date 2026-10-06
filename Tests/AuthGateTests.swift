// AuthGateTests.swift
// La porte d'accueil : ses règles, et ce qui les distingue de la carte du profil.
//
// POURQUOI CES TESTS
//   L'application de référence porte DEUX surfaces d'authentification qui se
//   ressemblent et ne se comportent pas pareil. Le portage initial a écrit la
//   mauvaise règle sur la porte : il a réutilisé `ProfileOptions.canSignIn`,
//   qui n'exige pas d'arobase. C'est juste pour la CARTE DU PROFIL, et faux
//   pour la PORTE. Ces tests épinglent les deux, côte à côte, pour que la
//   distinction ne puisse plus se perdre.
//
//   La règle la plus silencieuse est la dépendance au MODE : `App.tsx:285`
//   écrit `mode==='signup'?password.length<6:!password`. Se connecter n'exige
//   donc qu'un mot de passe non vide ; créer un compte en exige six. Une porte
//   qui appliquerait six aux deux refuserait de connecter des comptes dont le
//   mot de passe est court — et ces comptes existent.

import XCTest
@testable import Swiftdeepseek

final class AuthGateTests: XCTestCase {

    // MARK: - Le seuil

    func testTheSignupThresholdIsSix() {
        XCTAssertEqual(AuthGateOptions.signUpMinimumPasswordLength, 6)
    }

    /// Le seuil de la porte est le **même nombre** que celui de la carte du
    /// profil — mais il est porté par un autre type, parce que la **règle** qui
    /// l'emploie n'est pas la même. Deux constantes, une seule valeur : si l'une
    /// bougeait sans l'autre, ce test le dirait.
    func testTheTwoSurfacesAgreeOnTheSignupLength() {
        XCTAssertEqual(
            AuthGateOptions.signUpMinimumPasswordLength,
            ProfileOptions.signUpMinimumPasswordLength
        )
    }

    // MARK: - L'arobase : ce qui distingue la porte de la carte du profil

    /// LA décision qui a été portée de travers. Sur la **porte**, « Se
    /// connecter » exige l'arobase (`App.tsx:285`, `!email.includes('@')`).
    func testTheGateRequiresAnArobaseEvenToSignIn() {
        XCTAssertFalse(
            AuthGateOptions.canSubmit(
                busy: false, email: "thomas", password: "secret", mode: .login
            ),
            "l'original n'arme pas le bouton sans arobase, même pour se connecter"
        )
        XCTAssertTrue(
            AuthGateOptions.canSubmit(
                busy: false, email: "thomas@", password: "secret", mode: .login
            ),
            "une arobase suffit — l'original ne valide pas l'adresse"
        )
    }

    /// Et sur la **carte du profil**, la même saisie arme le bouton. C'est la
    /// divergence mesurée : les deux surfaces ne lisent pas le même contrat.
    func testTheProfileCardAcceptsWhatTheGateRefuses() {
        let sansArobase = "thomas"
        // La carte du profil arme « Se connecter »…
        XCTAssertTrue(
            ProfileOptions.canSignIn(busy: false, email: sansArobase, password: "secret"),
            "la carte du profil n'exige que la non-vacuité"
        )
        // …et la porte refuse la même saisie.
        XCTAssertFalse(
            AuthGateOptions.canSubmit(
                busy: false, email: sansArobase, password: "secret", mode: .login
            ),
            "la porte exige l'arobase"
        )
    }

    // MARK: - La dépendance au mode

    /// Un mot de passe d'un seul caractère **connecte**.
    func testLoginAcceptsASingleCharacterPassword() {
        XCTAssertTrue(
            AuthGateOptions.canSubmit(busy: false, email: "a@b", password: "x", mode: .login)
        )
    }

    /// Le MÊME mot de passe **n'inscrit pas**.
    func testSignupRefusesWhatLoginAccepts() {
        XCTAssertFalse(
            AuthGateOptions.canSubmit(busy: false, email: "a@b", password: "x", mode: .signup)
        )
    }

    /// Cinq caractères n'inscrivent pas, six le font — la borne exacte.
    func testFiveCharactersDoNotSignUpAndSixDo() {
        XCTAssertFalse(
            AuthGateOptions.canSubmit(busy: false, email: "a@b", password: "12345", mode: .signup)
        )
        XCTAssertTrue(
            AuthGateOptions.canSubmit(busy: false, email: "a@b", password: "123456", mode: .signup)
        )
    }

    /// Un mot de passe vide ne connecte pas non plus : `!password` est bien un
    /// test, pas une absence de test.
    func testAnEmptyPasswordNeverArmsTheButton() {
        for mode in AuthGateOptions.Mode.allCases {
            XCTAssertFalse(
                AuthGateOptions.canSubmit(busy: false, email: "a@b", password: "", mode: mode),
                "aucun mode n'arme le bouton sur un mot de passe vide"
            )
        }
    }

    /// L'attente désarme les deux modes.
    func testBusyDisarmsBothModes() {
        for mode in AuthGateOptions.Mode.allCases {
            XCTAssertFalse(
                AuthGateOptions.canSubmit(busy: true, email: "a@b", password: "123456", mode: mode)
            )
        }
    }

    // MARK: - La longueur se compte en unités UTF-16

    /// Trois emoji valent six unités UTF-16, donc passent la borne d'inscription.
    /// Compter les **graphèmes** en trouverait trois et refuserait : c'est la
    /// règle du projet, mesurée ailleurs pour le prénom.
    func testThePasswordLengthCountsUTF16Units() {
        let troisEmoji = "🌙🌙🌙"
        XCTAssertEqual(troisEmoji.count, 3, "trois graphèmes")
        XCTAssertEqual(AuthGateOptions.passwordLength(troisEmoji), 6, "six unités UTF-16")
        XCTAssertTrue(
            AuthGateOptions.canSubmit(busy: false, email: "a@b", password: troisEmoji, mode: .signup)
        )
    }

    // MARK: - Les deux boutons conditionnels

    /// « Mot de passe oublié » n'existe qu'en **connexion**.
    func testThePasswordLinkBelongsToLoginOnly() {
        XCTAssertTrue(
            AuthGateOptions.canRequestPasswordLink(busy: false, email: "a@b", mode: .login)
        )
        XCTAssertFalse(
            AuthGateOptions.canRequestPasswordLink(busy: false, email: "a@b", mode: .signup),
            "l'original ne rend ce bouton qu'en mode connexion"
        )
    }

    /// « Renvoyer la confirmation » n'existe qu'en **inscription**, et seulement
    /// **après un premier message** (`App.tsx:287` : `mode==='signup'&&message&&…`).
    func testTheResendButtonNeedsSignupAndAMessage() {
        XCTAssertFalse(
            AuthGateOptions.canResendConfirmation(busy: false, email: "a@b", mode: .login, message: "peu importe"),
            "jamais en connexion, même avec un message"
        )
        XCTAssertFalse(
            AuthGateOptions.canResendConfirmation(busy: false, email: "a@b", mode: .signup, message: nil),
            "jamais sans message : le bouton apparaît après le premier"
        )
        XCTAssertFalse(
            AuthGateOptions.canResendConfirmation(busy: false, email: "a@b", mode: .signup, message: ""),
            "un message vide n'est pas un message"
        )
        XCTAssertTrue(
            AuthGateOptions.canResendConfirmation(
                busy: false, email: "a@b", mode: .signup, message: "Vérifie ton courriel."
            )
        )
    }

    /// Les deux boutons ne sont **jamais** armés ensemble : leurs modes
    /// s'excluent.
    func testTheTwoSecondaryButtonsNeverOverlap() {
        for mode in AuthGateOptions.Mode.allCases {
            let lien = AuthGateOptions.canRequestPasswordLink(busy: false, email: "a@b", mode: mode)
            let renvoi = AuthGateOptions.canResendConfirmation(
                busy: false, email: "a@b", mode: mode, message: "m"
            )
            XCTAssertFalse(lien && renvoi, "un seul des deux à la fois, en mode \(mode)")
        }
    }

    // MARK: - Les libellés

    func testTitlesFollowTheMode() {
        XCTAssertEqual(AuthGateOptions.title(for: .login), "Se connecter")
        XCTAssertEqual(AuthGateOptions.title(for: .signup), "Créer mon compte")
    }

    /// Pendant l'attente, **les deux** modes affichent « Connexion… » — y
    /// compris l'inscription, ce qu'un portage « cohérent » corrigerait.
    func testTheBusyLabelIsTheSameInBothModes() {
        XCTAssertEqual(AuthGateOptions.submitTitle(for: .login, busy: true), "Connexion…")
        XCTAssertEqual(AuthGateOptions.submitTitle(for: .signup, busy: true), "Connexion…")
        XCTAssertEqual(AuthGateOptions.submitTitle(for: .signup, busy: false), "Créer mon compte")
    }

    // MARK: - Le retour

    /// « Retour » ramène au choix **et efface le message** : les deux gestes,
    /// sans quoi l'erreur de l'autre mode réapparaîtrait.
    func testGoingBackClearsTheMessage() {
        let retour = AuthGateOptions.afterBack(message: "Connexion impossible.")
        XCTAssertNil(retour.mode, "on revient au choix")
        XCTAssertEqual(retour.message, "", "et le message est effacé")
        XCTAssertNil(AuthGateOptions.afterBack(message: nil).mode)
    }

    // MARK: - L'inventaire des modes

    /// Deux modes, ni plus ni moins : `App.tsx:260` déclare
    /// `'login'|'signup'|null`, et `nil` est l'état de choix.
    func testThereAreExactlyTwoModes() {
        XCTAssertEqual(AuthGateOptions.Mode.allCases.count, 2)
        XCTAssertEqual(Set(AuthGateOptions.Mode.allCases), [.login, .signup])
    }
}
