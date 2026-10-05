// ProfileTests.swift
// La page « Profil » : le prénom, le compte, la synchronisation.
//
// Deux tests portent l'essentiel, et ce sont les deux qui ont motivé ce
// fichier :
//
//   - `testAnEmojiCountsAsTwoUnits` : l'original mesure le prénom avec
//     `value.length`, donc en unités **UTF-16**. Le `count` de Swift compte les
//     **graphèmes**. Un prénom d'un seul emoji vaut 2 d'un côté et 1 de l'autre :
//     le porter avec `count` ferait refuser, ici, un prénom que l'application
//     React Native accepte. Le test compare les deux mesures pour que l'écart
//     soit visible, pas supposé.
//
//   - `testSignInDoesNotRequireAnAtSign` : « Se connecter » n'exige qu'un champ
//     non vide, là où les trois autres boutons exigent une arobase. C'est le
//     contrat de l'original, et un portage « cohérent » qui alignerait les
//     quatre casserait la parité.

import XCTest
@testable import Swiftdeepseek

final class ProfileTests: XCTestCase {

    // MARK: - Le prénom : les bornes

    func testTheBoundsAreTwoAndForty() {
        XCTAssertEqual(ProfileOptions.firstNameMinimumLength, 2)
        XCTAssertEqual(ProfileOptions.firstNameMaximumLength, 40)
    }

    func testTheBoundsAreInclusive() {
        XCTAssertNotNil(ProfileOptions.savedFirstName("Ab"), "deux unités passent")
        XCTAssertNotNil(ProfileOptions.savedFirstName(String(repeating: "a", count: 40)), "quarante passent")
        XCTAssertNil(ProfileOptions.savedFirstName("A"), "une unité ne passe pas")
        XCTAssertNil(ProfileOptions.savedFirstName(String(repeating: "a", count: 41)), "quarante et une ne passent pas")
    }

    func testTheNameIsTrimmedBeforeBeingMeasured() {
        XCTAssertEqual(ProfileOptions.savedFirstName("  Aïcha  "), "Aïcha")
        XCTAssertNil(ProfileOptions.savedFirstName("  A  "), "le blanc ne compte pas dans la mesure")
        XCTAssertNotNil(ProfileOptions.savedFirstName("  Ab  "))
    }

    // MARK: - Le prénom : la mesure en unités UTF-16

    /// Le cœur du portage. Un emoji hors BMP vaut **deux** unités UTF-16 et
    /// **un** graphème : c'est exactement l'écart que `count` introduirait.
    func testAnEmojiCountsAsTwoUnits() {
        let emoji = "\u{1F642}" // 🙂 — un seul graphème
        XCTAssertEqual(emoji.count, 1, "un seul graphème")
        XCTAssertEqual(ProfileOptions.firstNameLength(emoji), 2, "mais deux unités UTF-16")
        XCTAssertNotNil(
            ProfileOptions.savedFirstName(emoji),
            "donc accepté, comme l'original — un `count` l'aurait refusé"
        )
    }

    /// Et l'écart joue aussi dans l'autre sens, à la borne haute.
    func testFortyEmojiAreRefusedBecauseTheyCountEighty() {
        let forty = String(repeating: "\u{1F642}", count: 40)
        XCTAssertEqual(forty.count, 40, "quarante graphèmes")
        XCTAssertEqual(ProfileOptions.firstNameLength(forty), 80, "quatre-vingts unités UTF-16")
        XCTAssertNil(
            ProfileOptions.savedFirstName(forty),
            "l'original refuse : 80 > 40 — un `count` l'aurait accepté"
        )
    }

    /// Une lettre accentuée **composée** vaut aussi deux unités. C'est le cas
    /// qu'un clavier produit sans qu'on le sache.
    func testACombiningAccentCountsAsTwoUnits() {
        let compose = "e\u{0301}" // e + accent aigu combinant
        XCTAssertEqual(compose.count, 1, "un seul graphème perçu")
        XCTAssertEqual(ProfileOptions.firstNameLength(compose), 2, "deux unités UTF-16")
        XCTAssertNotNil(ProfileOptions.savedFirstName(compose))
    }

    // MARK: - Le prénom : l'écriture

    func testSavingWritesTheNameAndTheNotice() {
        let (next, notice) = ProfileOptions.savingFirstName(Program.defaultState(), "  Aïcha  ")
        XCTAssertEqual(next.profile?.firstName, "Aïcha")
        XCTAssertEqual(notice, ProfileOptions.firstNameSavedNotice)
    }

    /// `App.tsx:309` — `sex: state.profile?.sex ?? 'Homme'`.
    func testAnAbsentProfileReceivesTheDefaultSex() {
        var state = Program.defaultState()
        state.profile = nil
        let (next, _) = ProfileOptions.savingFirstName(state, "Aïcha")
        XCTAssertEqual(next.profile?.sex, ProfileOptions.defaultSex)
        XCTAssertEqual(ProfileOptions.defaultSex, "Homme")
    }

    func testAnExistingSexIsKept() {
        var state = Program.defaultState()
        state.profile = PersonalProfile(sex: "Femme", firstName: "X")
        let (next, _) = ProfileOptions.savingFirstName(state, "Aïcha")
        XCTAssertEqual(next.profile?.sex, "Femme", "le sexe existant n'est pas écrasé")
        XCTAssertEqual(next.profile?.firstName, "Aïcha")
    }

    func testARefusedNameLeavesTheStateUntouched() {
        let state = Program.defaultState()
        let (next, notice) = ProfileOptions.savingFirstName(state, "A")
        XCTAssertEqual(next, state, "l'original sort avant d'écrire")
        XCTAssertEqual(notice, ProfileOptions.firstNameInvalidNotice)
    }

    /// Les deux issues posent un texte, jamais aucune : un bouton muet laisse
    /// croire à un succès.
    func testBothOutcomesCarryANotice() {
        let state = Program.defaultState()
        XCTAssertFalse(ProfileOptions.savingFirstName(state, "A").notice.isEmpty)
        XCTAssertFalse(ProfileOptions.savingFirstName(state, "Aïcha").notice.isEmpty)
    }

    // MARK: - Les quatre conditions d'activation

    /// « Se connecter » n'exige **pas** d'arobase — `disabled={busy||!email||!password}`.
    func testSignInDoesNotRequireAnAtSign() {
        XCTAssertTrue(ProfileOptions.canSignIn(busy: false, email: "abc", password: "1"))
        XCTAssertFalse(ProfileOptions.canSignIn(busy: false, email: "", password: "1"))
        XCTAssertFalse(ProfileOptions.canSignIn(busy: false, email: "abc", password: ""))
        XCTAssertFalse(ProfileOptions.canSignIn(busy: true, email: "abc", password: "1"))
    }

    /// Les deux actions d'envoi, elles, exigent une arobase — et rien de plus.
    func testTheTwoEmailActionsRequireAnAtSign() {
        XCTAssertFalse(ProfileOptions.canSendEmail(busy: false, email: "abc"))
        XCTAssertTrue(ProfileOptions.canSendEmail(busy: false, email: "a@"), "« a@ » suffit à l'original")
        XCTAssertTrue(ProfileOptions.canSendEmail(busy: false, email: "@"))
        XCTAssertFalse(ProfileOptions.canSendEmail(busy: true, email: "a@b"))
    }

    func testCreatingAnAccountRequiresSixCharactersOfPassword() {
        XCTAssertEqual(ProfileOptions.signUpMinimumPasswordLength, 6)
        XCTAssertFalse(ProfileOptions.canCreateAccount(busy: false, email: "a@b", password: "12345"))
        XCTAssertTrue(ProfileOptions.canCreateAccount(busy: false, email: "a@b", password: "123456"))
        XCTAssertFalse(ProfileOptions.canCreateAccount(busy: false, email: "", password: "123456"))
        XCTAssertFalse(ProfileOptions.canCreateAccount(busy: true, email: "a@b", password: "123456"))
    }

    /// Le minimum du mot de passe se compte lui aussi en unités UTF-16, comme le
    /// prénom — et pour la même raison.
    func testThePasswordMinimumAlsoCountsUTF16() {
        let threeEmoji = String(repeating: "\u{1F642}", count: 3)
        XCTAssertEqual(threeEmoji.count, 3, "trois graphèmes")
        XCTAssertEqual(ProfileOptions.passwordLength(threeEmoji), 6, "six unités UTF-16")
        XCTAssertTrue(
            ProfileOptions.canCreateAccount(busy: false, email: "a@b", password: threeEmoji),
            "l'original accepte : six unités"
        )
    }

    // MARK: - L'issue d'une connexion

    /// `sync.ts:20` rend `null` quand il n'y a pas de session : une inscription
    /// sans session n'est pas une erreur, c'est une confirmation en attente.
    func testAnAccountWithoutSessionAsksForEmailConfirmation() {
        XCTAssertEqual(ProfileOptions.outcome(register: true, hasSession: false), .confirmEmail)
        XCTAssertEqual(ProfileOptions.outcome(register: false, hasSession: false), .confirmEmail)
        XCTAssertEqual(ProfileOptions.outcome(register: true, hasSession: true), .created)
        XCTAssertEqual(ProfileOptions.outcome(register: false, hasSession: true), .retrieved)
    }

    func testEachOutcomeHasItsOwnNotice() {
        XCTAssertEqual(ProfileOptions.notice(for: .retrieved), ProfileOptions.retrievedNotice)
        XCTAssertEqual(ProfileOptions.notice(for: .created), ProfileOptions.accountCreatedNotice)
        XCTAssertEqual(ProfileOptions.notice(for: .confirmEmail), ProfileOptions.confirmEmailNotice)
        XCTAssertEqual(ProfileOptions.notice(for: .failed), ProfileOptions.signInFailedNotice)
        XCTAssertEqual(
            Set([
                ProfileOptions.notice(for: .retrieved),
                ProfileOptions.notice(for: .created),
                ProfileOptions.notice(for: .confirmEmail),
                ProfileOptions.notice(for: .failed)
            ]).count,
            4,
            "les quatre textes sont distincts"
        )
    }

    /// `e.message ?? 'Connexion impossible.'` — le repli porte aussi sur la
    /// chaîne vide : une erreur sans message ne doit pas laisser l'écran muet.
    func testAFailureWithoutAMessageStillSaysSomething() {
        XCTAssertEqual(ProfileOptions.failedNotice(nil), ProfileOptions.signInFailedNotice)
        XCTAssertEqual(ProfileOptions.failedNotice(""), ProfileOptions.signInFailedNotice)
        XCTAssertEqual(ProfileOptions.failedNotice("Adresse déjà utilisée."), "Adresse déjà utilisée.")
    }

    // MARK: - L'avatar

    /// Deux limites, deux unités, deux endroits — les confondre ferait passer
    /// une photo que l'un refuse.
    func testTheTwoPhotoLimitsAreDifferentNumbers() {
        XCTAssertEqual(ProfileOptions.avatarMaximumBase64Length, 2_800_000)
        XCTAssertEqual(ProfileOptions.avatarMaximumBytes, 2_097_152)
        XCTAssertNotEqual(
            ProfileOptions.avatarMaximumBase64Length,
            ProfileOptions.avatarMaximumBytes,
            "deux nombres distincts, pour deux unités distinctes"
        )
    }

    func testBothPhotoLimitsAreInclusive() {
        XCTAssertTrue(ProfileOptions.pickerAccepts(base64Length: 2_800_000))
        XCTAssertFalse(ProfileOptions.pickerAccepts(base64Length: 2_800_001))
        XCTAssertTrue(ProfileOptions.uploadAccepts(byteCount: 2_097_152))
        XCTAssertFalse(ProfileOptions.uploadAccepts(byteCount: 2_097_153))
    }

    /// Le chemin est toujours un JPEG sous l'identifiant, quelle que soit la
    /// source — `avatars.ts:29`.
    func testTheAvatarPathIsAlwaysAJpegUnderTheUserId() {
        XCTAssertEqual(ProfileOptions.avatarPath(userID: "abc-123"), "abc-123/avatar.jpg")
        XCTAssertEqual(ProfileOptions.avatarBucket, "friend-avatars")
    }

    // MARK: - Les textes, épinglés

    func testTheCardTextsAreThoseOfTheReference() {
        XCTAssertEqual(ProfileOptions.firstNameTitle, "Mon prénom")
        XCTAssertEqual(ProfileOptions.accountTitle, "Compte et synchronisation")
        XCTAssertEqual(ProfileOptions.firstNameHint, "Ce prénom apparaît dans les invitations envoyées à tes amis.")
        XCTAssertEqual(ProfileOptions.firstNameSaveAction, "Enregistrer mon prénom")
        XCTAssertEqual(ProfileOptions.firstNameInvalidNotice, "Saisis un prénom de 2 à 40 caractères.")
        XCTAssertEqual(ProfileOptions.firstNameSavedNotice, "Prénom enregistré pour ton profil et tes invitations.")
        XCTAssertEqual(ProfileOptions.signedOutHint, "Retrouve ta progression sur un autre téléphone.")
    }

    /// TROIS textes portent une apostrophe courbe FERMANTE (U+2019), là où le
    /// reste du fichier écrit des apostrophes droites. C'est la référence.
    ///
    /// Ce test s'appelait `testTwoTextsCarry...` et c'était FAUX : compté, et
    /// non supposé, `confirmationResentNotice` porte lui aussi U+2019
    /// (« l’application »). Trois constantes sur soixante-et-une. Et aucune
    /// U+2018 dans ce fichier, contrairement à `QuranSourcesCard` où « rub‘ »
    /// en porte une — les deux modules ne se ressemblent pas, et c'est voulu.
    func testThreeTextsCarryATypographicApostrophe() {
        XCTAssertTrue(ProfileOptions.notConfiguredHint.contains("l\u{2019}URL"))
        XCTAssertTrue(ProfileOptions.passwordLinkSentNotice.contains("t\u{2019}être"))
        XCTAssertTrue(ProfileOptions.confirmationResentNotice.contains("l\u{2019}application"))
        XCTAssertFalse(ProfileOptions.notConfiguredHint.contains("l'URL"), "l'original n'écrit pas l'apostrophe droite")
    }

    /// Les deux messages du service diffèrent d'**un mot**, et ce mot compte.
    func testTheTwoServiceMessagesDifferByOneWord() {
        XCTAssertEqual(ProfileOptions.serviceNotConfigured, "Synchronisation non configurée")
        XCTAssertEqual(ProfileOptions.serviceUnavailable, "Synchronisation indisponible")
        XCTAssertNotEqual(ProfileOptions.serviceNotConfigured, ProfileOptions.serviceUnavailable)
    }

    /// Les six libelles d'action du compte. Aucun ecran ne les monte
    /// encore : ils sont portes parce que la reference les porte, et geles
    /// ici pour qu'ils ne derivent pas avant d'arriver a l'ecran.
    /// (`firstNameSaveAction` est deja pin par `testTheCardTextsAreThoseOfTheReference`.)
    func testTheSixActionLabelsAreThoseOfTheReference() {
        XCTAssertEqual(ProfileOptions.signInAction, "Se connecter")
        XCTAssertEqual(ProfileOptions.createAccountAction, "Créer un compte")
        XCTAssertEqual(ProfileOptions.resendConfirmationAction, "Renvoyer le courriel de confirmation")
        XCTAssertEqual(ProfileOptions.passwordLinkAction, "Recevoir un lien pour créer ou changer mon mot de passe")
        XCTAssertEqual(ProfileOptions.syncNowAction, "Synchroniser maintenant")
        XCTAssertEqual(ProfileOptions.signOutAction, "Se déconnecter")
    }

    /// Les trois invites de saisie, telles quelles.
    func testTheThreePlaceholdersAreThoseOfTheReference() {
        XCTAssertEqual(ProfileOptions.firstNamePlaceholder, "Ton prénom")
        XCTAssertEqual(ProfileOptions.emailPlaceholder, "Adresse e-mail")
        XCTAssertEqual(ProfileOptions.passwordPlaceholder, "Mot de passe")
    }

    /// Trois avis qui n'etaient pins nulle part. `confirmationResentNotice`
    /// porte l'apostrophe courbe U+2019 (« l'application ») — c'est le
    /// troisieme texte dans ce cas, voir le test dedie plus haut.
    func testTheThreeNoticesAreThoseOfTheReference() {
        XCTAssertEqual(ProfileOptions.syncedNotice, "Données synchronisées.")
        XCTAssertEqual(ProfileOptions.signedOutNotice, "Déconnecté. Les données de ce compte restent sauvegardées séparément sur ce téléphone.")
        XCTAssertEqual(ProfileOptions.confirmationResentNotice, "Nouveau courriel de confirmation envoyé. Ouvre ce nouveau lien sur le téléphone où l’application est installée.")
    }

    /// LES DEUX GARDES ORDONNEES DE `pushState` — `sync.ts`.
    ///
    /// La poussee recupere d'abord l'utilisateur, puis refuse dans cet ordre :
    ///   - pas de session  -> « Connecte-toi pour synchroniser tes donnees. »
    ///   - autre compte    -> « Ces donnees appartiennent a un autre compte. »
    ///
    /// Elles ne doivent PAS etre confondues avec les deux refus de `signIn`
    /// (« Synchronisation non configuree » / « Synchronisation indisponible »),
    /// qui sont un autre couple, pin plus bas. Le portage porte les quatre :
    /// quatre textes, deux situations, et un seul mot les separe deux a deux.
    func testTheTwoOrderedGuardsOfThePushArePinned() {
        XCTAssertEqual(ProfileOptions.serviceNeedsSignIn, "Connecte-toi pour synchroniser tes données.")
        XCTAssertEqual(ProfileOptions.serviceOtherAccount, "Ces données appartiennent à un autre compte.")
    }

    /// Les quatre messages de photo. Aucun bouton de photo n'est monte
    /// (le bucket `friend-avatars` attend une verification cote serveur) :
    /// les textes sont portes et geles, comme le bouton « Verifier le jeton
    /// push » de §9.23 — on ne monte pas un bouton qui ne peut rien faire.
    ///
    /// `avatarTooLarge` dit « moins de 2 Mo » et c'est un ARRONDI : la borne
    /// reelle est `avatarMaximumBytes` = 2 097 152 octets, soit exactement
    /// 2 Mio. Le texte parle a l'utilisateur, la garde compte des octets.
    func testTheFourAvatarMessagesArePinned() {
        XCTAssertEqual(ProfileOptions.avatarUnreadable, "La photo sélectionnée ne peut pas être lue.")
        XCTAssertEqual(ProfileOptions.avatarTooLarge, "Choisis une photo de moins de 2 Mo.")
        XCTAssertEqual(ProfileOptions.avatarNeedsSignIn, "Connecte-toi pour enregistrer ta photo.")
        XCTAssertEqual(ProfileOptions.avatarNeedsConnection, "Connexion requise.")
    }

    /// Le reste du bloc photo : deux libelles de choix, un retrait, deux
    /// avis et la confirmation de retrait. Meme raison que ci-dessus.
    func testThePhotoBlockTextsArePinned() {
        XCTAssertEqual(ProfileOptions.photoChooseAction, "Choisir ou modifier ma photo")
        XCTAssertEqual(ProfileOptions.photoAddAction, "Ajouter une photo (facultatif)")
        XCTAssertEqual(ProfileOptions.photoRemoveAction, "Supprimer ma photo")
        XCTAssertEqual(ProfileOptions.photoSavedNotice, "Photo de profil enregistrée.")
        XCTAssertEqual(ProfileOptions.photoRemovedNotice, "Photo supprimée.")
        XCTAssertEqual(ProfileOptions.photoRemoveTitle, "Supprimer ta photo ?")
        XCTAssertEqual(ProfileOptions.photoRemovePrompt, "Ton avatar affichera la première lettre de ton prénom.")
    }

    /// `settingFirstName` ECRIT, il ne garde pas — la validation vit dans
    /// `savingFirstName`. C'est le contrat de `touch({...state, profile:
    /// {sex: state.profile?.sex ?? 'Homme', firstName: value}})`, qui ecrit
    /// `value` tel quel et laisse l'appelant verifier.
    ///
    /// Ce test gele la frontiere : un ecran qui appellerait l'ecriture
    /// directement poserait un prenom d'un seul caractere, et le modele ne
    /// l'empecherait pas.
    func testSettingFirstNameDoesNotValidate() {
        let depart = Program.defaultState()
        let ecrit = ProfileOptions.settingFirstName(depart, "a")
        XCTAssertEqual(ecrit.profile?.firstName, "a", "ecrit tel quel, sans passer par les bornes")
        XCTAssertEqual(ecrit.profile?.sex, ProfileOptions.defaultSex, "et pose le sexe par defaut")
        XCTAssertNil(ProfileOptions.savedFirstName("a"), "alors que la garde, elle, refuse")
    }
}
