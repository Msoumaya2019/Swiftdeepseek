// ProfileOptions.swift
// La page « Profil » — le prénom, le compte, la synchronisation.
//
// Correspondance : la carte « Mon prénom » de `src/App.tsx:322`, les textes de
// `src/services/sync.ts` et `src/services/avatars.ts`. C'est la première carte
// de la page « Profil » de l'original, qui n'existe pas encore ici.
//
// POURQUOI CE FICHIER
//   `Features/Settings/SettingsView.swift` énonce la règle du dossier : un écran
//   ne calcule rien. Cette carte porte six décisions qui, si elles vivaient
//   dans une vue, divergeraient en silence — et deux d'entre elles sont des
//   pièges :
//
//     1. LE PRÉNOM SE COMPTE EN UTF-16. L'original écrit
//        `value.length < 2 || value.length > 40`. En JavaScript, `.length`
//        compte les **unités UTF-16**, pas les caractères perçus : un seul emoji
//        vaut 2, une lettre accentuée composée en vaut 2 aussi. Le `count` de
//        Swift, lui, compte les **graphèmes**. Écrire `value.count` ici ferait
//        donc **refuser** un prénom d'un seul emoji que l'application React
//        Native accepte — et accepter, à 40, ce qu'elle refuse. Les deux
//        applications doivent trancher pareil : on compte `utf16.count`.
//
//     2. DEUX TESTS D'ADRESSE DIFFÉRENTS POUR LE MÊME CHAMP. « Se connecter »
//        n'exige que `!email` (non vide) ; « Créer un compte », « Renvoyer le
//        courriel » et « Recevoir un lien » exigent `email.includes('@')`. Ce
//        n'est pas une incohérence à corriger : c'est le contrat. Un bouton
//        « Se connecter » actif sur une saisie sans arobase est bien celui de
//        l'original.
//
//     3. LE PRÉNOM ÉCRIT UN SEXE PAR DÉFAUT. `App.tsx:309` :
//        `profile:{sex: state.profile?.sex ?? 'Homme', firstName: value}`. Sur un
//        profil absent — un état restauré d'une version ancienne — enregistrer
//        son prénom écrit aussi `sex: "Homme"`. Écrire `firstName` seul
//        laisserait le document dans un état que l'application React Native ne
//        produit jamais.
//
//     4. L'INSCRIPTION SANS SESSION N'EST PAS UNE ERREUR. `sync.ts:20` rend
//        `result.data.session ? result.data.user : null` : quand la confirmation
//        par courriel est exigée — et ce projet l'exige, `mailer_autoconfirm`
//        est faux — `signIn(register: true)` rend `null` sans lever. L'écran doit
//        donc dire « vérifie ton courriel », pas « connexion impossible ».
//
//     5. DEUX LIMITES DE TAILLE DIFFÉRENTES POUR LA MÊME PHOTO. Le sélecteur
//        refuse au-delà de `2_800_000` caractères base64 ; l'envoi refuse
//        au-delà de `2_097_152` octets. Deux nombres, deux unités, deux
//        endroits (`avatars.ts:15` et `avatars.ts:30`). Les confondre ferait
//        passer une photo que l'un refuse.
//
// CE QUI N'EST PAS ENCORE LÀ
//   L'envoi et le retrait de la photo demandent `friend-avatars`, un bucket de
//   stockage Supabase, et une écriture sur `friend_profiles.avatar_path` — donc
//   une vérification serveur que cette version ne fait pas. Les textes et les
//   bornes sont portés ici pour que rien ne se perde ; l'écran ne monte pas
//   encore les boutons de photo (voir `Features/Profile/ProfileView.swift`).
//   Même discipline que le bouton « Vérifier le jeton push » de §9.23 : on ne
//   monte pas un bouton qui ne peut rien faire.

import Foundation

public enum ProfileOptions {

    // MARK: - Les textes de la carte

    /// « Mon prénom » — `App.tsx:322`.
    public static let firstNameTitle = "Mon prénom"
    /// « Compte et synchronisation » — `App.tsx:322`.
    public static let accountTitle = "Compte et synchronisation"
    /// « Ce prénom apparaît dans les invitations envoyées à tes amis. »
    public static let firstNameHint = "Ce prénom apparaît dans les invitations envoyées à tes amis."
    /// Le texte d'invite du champ — `App.tsx:322`.
    public static let firstNamePlaceholder = "Ton prénom"
    /// « Enregistrer mon prénom » — `App.tsx:322`.
    public static let firstNameSaveAction = "Enregistrer mon prénom"
    public static let emailPlaceholder = "Adresse e-mail"
    public static let passwordPlaceholder = "Mot de passe"
    public static let signInAction = "Se connecter"
    public static let createAccountAction = "Créer un compte"
    public static let resendConfirmationAction = "Renvoyer le courriel de confirmation"
    public static let passwordLinkAction = "Recevoir un lien pour créer ou changer mon mot de passe"
    public static let syncNowAction = "Synchroniser maintenant"
    public static let signOutAction = "Se déconnecter"
    public static let photoChooseAction = "Choisir ou modifier ma photo"
    public static let photoAddAction = "Ajouter une photo (facultatif)"
    public static let photoRemoveAction = "Supprimer ma photo"

    // MARK: - Les textes affichés

    /// « Ajoute l'URL et la clé publique de ton projet Supabase dans le fichier
    /// .env pour activer le compte. » — `App.tsx:322`, quand `syncConfigured`
    /// est faux.
    ///
    /// Le texte parle d'un fichier `.env`, qui n'existe pas dans cette
    /// application : les valeurs arrivent par `Secrets.xcconfig`. Le porter tel
    /// quel est un choix — le modifier ferait diverger les deux applications
    /// pour un détail de configuration qui n'appartient à aucune des deux.
    /// L'écran ne l'affiche que dans le cas où la configuration manque, ce qui
    /// n'arrive pas dans une compilation normale.
    public static let notConfiguredHint = "Ajoute l’URL et la clé publique de ton projet Supabase dans le fichier .env pour activer le compte."

    /// « Retrouve ta progression sur un autre téléphone. » — `App.tsx:322`.
    public static let signedOutHint = "Retrouve ta progression sur un autre téléphone."

    public static let firstNameInvalidNotice = "Saisis un prénom de 2 à 40 caractères."
    public static let firstNameSavedNotice = "Prénom enregistré pour ton profil et tes invitations."
    public static let syncedNotice = "Données synchronisées."
    public static let signedOutNotice = "Déconnecté. Les données de ce compte restent sauvegardées séparément sur ce téléphone."
    public static let retrievedNotice = "Tes données de ce compte ont été retrouvées."
    public static let accountCreatedNotice = "Compte créé. Configure ton nouvel apprentissage."
    public static let confirmEmailNotice = "Vérifie ton courriel pour confirmer le compte."
    public static let signInFailedNotice = "Connexion impossible."
    public static let confirmationResentNotice = "Nouveau courriel de confirmation envoyé. Ouvre ce nouveau lien sur le téléphone où l’application est installée."
    public static let passwordLinkSentNotice = "Un lien vient de t’être envoyé. Ouvre-le sur ce téléphone après avoir installé la nouvelle version de l’application."

    public static let photoSavedNotice = "Photo de profil enregistrée."
    public static let photoRemovedNotice = "Photo supprimée."
    public static let photoRemoveTitle = "Supprimer ta photo ?"
    public static let photoRemovePrompt = "Ton avatar affichera la première lettre de ton prénom."

    // MARK: - Les messages du service de synchronisation

    /// Les messages de `sync.ts`. Ils ne sont pas affichés par l'écran — il
    /// affiche `error.localizedDescription` — mais ils sont **portés** : ce sont
    /// eux que l'application React Native montre, et les deux doivent dire la
    /// même chose. Deux d'entre eux diffèrent d'un mot, et ce mot compte :
    /// `signIn` dit « non configurée » (`sync.ts:17`) tandis que `pushState` dit
    /// « indisponible » (`sync.ts:59`).
    public static let serviceNotConfigured = "Synchronisation non configurée"
    public static let serviceUnavailable = "Synchronisation indisponible"
    public static let serviceNeedsSignIn = "Connecte-toi pour synchroniser tes données."
    public static let serviceOtherAccount = "Ces données appartiennent à un autre compte."

    /// Les messages d'`avatars.ts`.
    public static let avatarUnreadable = "La photo sélectionnée ne peut pas être lue."
    public static let avatarTooLarge = "Choisis une photo de moins de 2 Mo."
    public static let avatarNeedsSignIn = "Connecte-toi pour enregistrer ta photo."
    public static let avatarNeedsConnection = "Connexion requise."

    // MARK: - Les bornes

    /// `value.length < 2` — `App.tsx:309`.
    public static let firstNameMinimumLength = 2
    /// `value.length > 40` — `App.tsx:309`.
    public static let firstNameMaximumLength = 40
    /// `password.length < 6` — `App.tsx:322`, sur « Créer un compte ».
    public static let signUpMinimumPasswordLength = 6

    // MARK: - L'initiale du bouton de profil

    /// La lettre du rond de la barre de titre — `ProfileHeaderButton.tsx:6` :
    ///
    ///     Array.from(firstName?.trim() ?? '')[0]?.toLocaleUpperCase('fr-FR')
    ///
    /// `nil` quand il n'y a pas de prénom, ou quand il est vide : l'original
    /// affiche alors un bonhomme, pas un rond vide.
    ///
    /// DIVERGENCE MESURÉE — `Array.from` itère par **point de code**, le `first`
    /// de Swift par **graphème**. Sur une séquence ZWJ (un emoji composé, du type
    /// famille), l'original rend le premier point de code — un caractère
    /// invisible et sans sens — là où Swift rend la séquence entière. Un prénom
    /// saisi au clavier commence par une lettre : le cas n'est pas atteignable, et
    /// rendre le graphème entier est le plus juste. On garde `first`, et on
    /// l'écrit.
    ///
    /// La casse, elle, ne diverge pas : `toLocaleUpperCase('fr-FR')` et
    /// `uppercased()` rendent la même chose pour les lettres latines d'un prénom.
    public static func avatarInitial(_ name: String?) -> String? {
        guard let letter = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(letter).uppercased()
    }

    // MARK: - Le prénom : la mesure, puis l'écriture

    /// Le nombre que l'original compare — `value.length`.
    ///
    /// **Unités UTF-16**, et non graphèmes : voir l'en-tête. Un seul emoji vaut
    /// `2` ici, et `1` en `count` — assez pour qu'un prénom d'un emoji soit
    /// accepté d'un côté et refusé de l'autre.
    public static func firstNameLength(_ value: String) -> Int {
        value.utf16.count
    }

    /// Le prénom retenu, ou `nil` si la saisie est refusée.
    ///
    /// `String.prototype.trim()` de JavaScript et
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` ne retirent pas
    /// exactement le même ensemble — mais les deux retirent l'espace, la
    /// tabulation, le saut de ligne et l'espace insécable, qui sont les seuls
    /// cas qu'une saisie produit. L'écart restant n'est pas atteignable au
    /// clavier.
    public static func savedFirstName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = firstNameLength(value)
        guard length >= firstNameMinimumLength, length <= firstNameMaximumLength else { return nil }
        return value
    }

    /// L'écriture du profil — `App.tsx:309` :
    ///
    ///     touch({...state, profile:{sex: state.profile?.sex ?? 'Homme',
    ///                                 firstName: value}})
    ///
    /// Le défaut `"Homme"` n'est pas décoratif : sur un profil **absent**, il
    /// crée le sexe que l'application React Native créerait. Le `touch` n'est
    /// pas refait ici — toute écriture passe par `AppStateRepository.mutate`,
    /// qui l'applique (voir `QuranDisplayOptions.settingEdition`).
    public static func settingFirstName(_ state: AppState, _ value: String) -> AppState {
        var next = state
        next.profile = PersonalProfile(
            sex: state.profile?.sex ?? defaultSex,
            firstName: value
        )
        return next
    }

    /// Le sexe écrit quand le profil est absent — `App.tsx:309`, `?? 'Homme'`.
    public static let defaultSex = "Homme"

    /// L'enregistrement complet : le nouvel état **et** le texte à afficher.
    ///
    /// Rend l'état **inchangé** quand la saisie est refusée — l'original sort
    /// avant d'écrire. Les deux issues posent un texte, jamais aucune : un
    /// bouton qui ne dit rien laisse croire à un succès.
    public static func savingFirstName(_ state: AppState, _ raw: String) -> (state: AppState, notice: String) {
        guard let value = savedFirstName(raw) else {
            return (state, firstNameInvalidNotice)
        }
        return (settingFirstName(state, value), firstNameSavedNotice)
    }

    // MARK: - Les conditions d'activation des quatre boutons

    /// « Se connecter » — `disabled={busy||!email||!password}`.
    ///
    /// **Pas** de test d'arobase ici, contrairement aux trois autres : c'est le
    /// contrat de l'original, pas un oubli de sa part ni du portage.
    public static func canSignIn(busy: Bool, email: String, password: String) -> Bool {
        !busy && !email.isEmpty && !password.isEmpty
    }

    /// « Créer un compte » — `disabled={busy||!email||password.length<6}`.
    ///
    /// La longueur du mot de passe se compte en unités UTF-16, comme le prénom
    /// et pour la même raison. Elle n'est **pas** bornée par le haut : c'est un
    /// minimum, et rien d'autre.
    public static func canCreateAccount(busy: Bool, email: String, password: String) -> Bool {
        !busy && !email.isEmpty && passwordLength(password) >= signUpMinimumPasswordLength
    }

    /// « Renvoyer le courriel de confirmation » et « Recevoir un lien » —
    /// `disabled={busy||!email.includes('@')}`.
    ///
    /// L'original teste **la présence d'une arobase**, pas la validité de
    /// l'adresse : `a@` active le bouton. On ne « corrige » pas en validant
    /// l'adresse — le serveur, lui, la refusera, et les deux applications
    /// doivent réagir au même moment.
    public static func canSendEmail(busy: Bool, email: String) -> Bool {
        !busy && email.contains("@")
    }

    /// `password.length` — unités UTF-16, comme `firstNameLength`.
    public static func passwordLength(_ value: String) -> Int {
        value.utf16.count
    }

    // MARK: - L'issue d'une connexion

    /// Ce qu'une tentative de connexion ou d'inscription produit.
    ///
    /// Quatre cas, et non deux : « pas de session » n'est pas une erreur quand
    /// on vient de créer un compte — c'est une confirmation par courriel en
    /// attente (`sync.ts:20`).
    public enum AuthOutcome: Equatable, Sendable {
        /// Connexion réussie : les données du compte ont été retrouvées.
        case retrieved
        /// Compte créé, session ouverte.
        case created
        /// Compte créé, **pas de session** : le courriel doit être confirmé.
        case confirmEmail
        /// Le service a refusé. Le texte vient de l'erreur, pas d'ici.
        case failed
    }

    /// La décision, isolée de ses effets.
    public static func outcome(register: Bool, hasSession: Bool) -> AuthOutcome {
        guard hasSession else { return .confirmEmail }
        return register ? .created : .retrieved
    }

    /// Le texte d'une issue.
    ///
    /// `failed` n'a **pas** de texte propre : l'original affiche
    /// `e.message ?? 'Connexion impossible.'`, donc le message du service quand
    /// il existe, et ce repli sinon. La vue appelle `failedNotice(_:)`.
    public static func notice(for outcome: AuthOutcome) -> String {
        switch outcome {
        case .retrieved: return retrievedNotice
        case .created: return accountCreatedNotice
        case .confirmEmail: return confirmEmailNotice
        case .failed: return signInFailedNotice
        }
    }

    /// Le texte d'un échec — `e.message ?? 'Connexion impossible.'`.
    ///
    /// Le repli porte sur la chaîne **vide** autant que sur l'absence : une
    /// erreur sans message ne doit pas laisser l'écran muet.
    public static func failedNotice(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return signInFailedNotice }
        return message
    }

    // MARK: - L'avatar : les bornes et l'emplacement

    /// Le bucket de stockage — `avatars.ts:6`.
    public static let avatarBucket = "friend-avatars"

    /// L'emplacement de l'objet — `avatars.ts:29`, `` `${user.id}/avatar.jpg` ``.
    ///
    /// Toujours un `.jpg`, quel que soit le format choisi : le sélecteur écrit
    /// les octets en JPEG (`avatars.ts:17`, `quality:0.65`), et l'envoi déclare
    /// `image/jpeg`. Le chemin ne dépend pas de la source.
    public static func avatarPath(userID: String) -> String {
        "\(userID)/avatar.jpg"
    }

    /// La limite du **sélecteur** — `avatars.ts:15`, sur la longueur base64.
    public static let avatarMaximumBase64Length = 2_800_000
    /// La limite de l'**envoi** — `avatars.ts:30`, sur les octets.
    public static let avatarMaximumBytes = 2_097_152

    /// La photo est-elle acceptable à la sélection ? — `avatars.ts:15`.
    public static func pickerAccepts(base64Length: Int) -> Bool {
        base64Length <= avatarMaximumBase64Length
    }

    /// La photo est-elle acceptable à l'envoi ? — `avatars.ts:30`.
    public static func uploadAccepts(byteCount: Int) -> Bool {
        byteCount <= avatarMaximumBytes
    }

    // MARK: - Les trois cartes de la page « Profil »

    /// « Connaissances » — `App.tsx:325`.
    ///
    /// La carte n'existe **qu'ici** dans l'application React Native : le relevé
    /// des occurrences de « Connaissances » et de « Modifier mes connaissances »
    /// dans `src/` ne rend que cette ligne. `SettingsView` l'affichait à titre
    /// provisoire, tant que la page « Profil » n'existait pas (son en-tête le
    /// disait) ; elle est retournée à sa place.
    public static let knowledgeTitle = "Connaissances"
    public static let knowledgeDetail = "Modifier les sourates, juz’, hizb et passages déjà appris."
    public static let knowledgeAction = "Modifier mes connaissances"

    /// « Objectif et rythme » — `App.tsx:326`.
    public static let goalTitle = "Objectif et rythme"
    public static let goalAction = "Modifier mon programme"

    /// La ligne de la carte « Objectif et rythme » — `App.tsx:326` :
    ///
    ///     {state.goal.label} · {paceLabels[state.pace]}
    ///
    /// Le séparateur est un point médian entouré d'espaces, exactement comme
    /// l'original. Il est composé ici plutôt que dans la vue pour la même raison
    /// que les autres textes : deux écrans qui le composent séparément peuvent
    /// diverger d'une espace.
    ///
    /// Le libellé du rythme vient de `Pace.displayed(_:)`, jamais d'une table
    /// locale — c'est le quatrième appelant de cet idiome, et c'est ce qui a
    /// décidé de l'extraire.
    public static func goalAndPace(goalLabel: String, pace: String) -> String {
        "\(goalLabel) · \(Pace.displayed(pace))"
    }

    /// « Apprentissage » — `App.tsx:327`.
    public static let learningTitle = "Apprentissage"
    /// L'étiquette de l'interrupteur — `App.tsx:327`, `accessibilityLabel` inclus.
    public static let reviewsToggleLabel = "Activer l’espace Révisions"
    /// Le titre de la rangée de cycles — `App.tsx:327`.
    public static let reviewCycleHeading = "Tout revoir sur un cycle de"
    /// Le libellé d'un bouton de cycle — `App.tsx:327`, `` `${days} j` ``.
    ///
    /// L'unité est un « j » minuscule suivi d'une espace, et non « jours » : les
    /// quatre boutons de l'original sont étroits, et « 30 j » tient là où
    /// « 30 jours » ne tiendrait pas.
    public static func cycleLabel(_ days: Int) -> String {
        "\(days) j"
    }
}
