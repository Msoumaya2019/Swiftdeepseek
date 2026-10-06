// AuthGateOptions.swift
// La porte d'accueil — « Bienvenue », avant toute navigation.
//
// Correspondance : le composant `AccountWelcome` de `src/App.tsx:260-288`, monté
// à la racine de l'interface tant que `accountIntro === 'show'`. C'est le tout
// premier écran d'une installation neuve, et c'est lui qui décide si l'on entre
// ou non.
//
// POURQUOI CE FICHIER EXISTE SÉPARÉMENT DE `ProfileOptions`
//   La référence porte DEUX surfaces d'authentification, et **elles n'ont pas les
//   mêmes règles**. Le confondre est le piège que ce fichier existe pour fermer :
//
//     - la CARTE DU PROFIL (`App.tsx:322`) : « Se connecter » n'exige que
//       `!email` (non vide), « Créer un compte » exige `email.includes('@')` et
//       six caractères. C'est ce que porte `ProfileOptions.canSignIn` /
//       `canCreateAccount`, et c'est juste — pour la carte du profil ;
//
//     - la PORTE D'ACCUEIL (`App.tsx:285`), objet de ce fichier :
//       `disabled={busy||!email.includes('@')||(mode==='signup'?password.length<6:!password)}`.
//       Une seule expression, deux conséquences qu'un portage « propre » perdrait :
//
//         1. L'AROBASE EST EXIGÉE MÊME POUR SE CONNECTER. Sur la carte du profil,
//            « Se connecter » s'active sans arobase ; **ici, non**. Les deux
//            écrans se ressemblent et ne se comportent pas pareil. Un portage qui
//            réutiliserait `ProfileOptions.canSignIn` pour la porte accepterait
//            `thomas` sans domaine, là où l'original refuse d'armer le bouton.
//
//         2. LE MOT DE PASSE EST TESTÉ DIFFÉREMMENT SELON LE MODE. Se connecter
//            n'exige qu'un mot de passe **non vide** (`!password`) ; créer un
//            compte en exige **six**. La longueur est donc une propriété du
//            *mode*, pas du champ. C'est la règle la plus silencieuse des deux :
//            une porte qui appliquerait `length >= 6` aux deux modes refuserait
//            de connecter un compte dont le mot de passe est court — et ces
//            comptes existent, la référence n'ayant jamais imposé six caractères
//            à la connexion.
//
//   La longueur se compte en **unités UTF-16**, comme partout dans ce projet
//   (`ProfileOptions.passwordLength`) : l'original écrit `password.length`, qui
//   compte les unités UTF-16 et non les graphèmes. Un mot de passe de trois
//   emoji vaut six et passe la borne d'inscription — c'est le contrat.
//
// CE QUI EST DÉLIBÉRÉMENT ÉCARTÉ
//   `AccountWelcome` monte, en mode inscription, un sélecteur de photo
//   (`chooseAvatar`) qui **met la photo de côté** (`stageAvatar`) avant l'envoi.
//   Cette mise de côté écrit sur un bucket de stockage Supabase, hors du
//   périmètre de ce portage (voir `ProfileOptions`, « CE QUI N'EST PAS ENCORE
//   LÀ »). La porte ne monte donc pas ce bouton : on ne monte pas un bouton qui
//   ne peut rien faire. La règle des deux autres boutons, elle, est portée.

import Foundation

public enum AuthGateOptions {

    /// Le seuil d'inscription — six caractères, en unités UTF-16.
    /// `App.tsx:285` : `mode==='signup'?password.length<6:!password`.
    public static let signUpMinimumPasswordLength = 6

    /// L'état de la porte : le choix, ou l'un des deux formulaires.
    ///
    /// `App.tsx:260` : `const [mode,setMode]=useState<'login'|'signup'|null>(null)`.
    /// L'état initial est `nil` — la porte **s'ouvre sur un choix**, pas sur un
    /// formulaire. Un portage qui irait droit au formulaire ferait disparaître
    /// le troisième bouton, « Réessayer la restauration de ma session ».
    public enum Mode: String, Equatable, Sendable, CaseIterable {
        case login
        case signup
    }

    /// Le titre du formulaire, selon le mode.
    /// `App.tsx:281` : `{mode==='signup'?'Créer mon compte':'Se connecter'}`.
    public static func title(for mode: Mode) -> String {
        mode == .signup ? "Créer mon compte" : "Se connecter"
    }

    /// Le libellé du bouton principal — le même que le titre, sauf pendant
    /// l'attente, où il devient « Connexion… » **dans les deux modes**.
    /// `App.tsx:285` : `{busy?'Connexion…':mode==='signup'?'Créer mon compte':'Se connecter'}`.
    public static func submitTitle(for mode: Mode, busy: Bool) -> String {
        busy ? "Connexion…" : title(for: mode)
    }

    /// Le mot de passe se compte en **unités UTF-16**, jamais en graphèmes.
    /// Même règle et même raison que `ProfileOptions.passwordLength`.
    public static func passwordLength(_ password: String) -> Int {
        password.utf16.count
    }

    /// La règle du bouton principal de la porte.
    ///
    /// `disabled={busy||!email.includes('@')||(mode==='signup'?password.length<6:!password)}`
    /// — `App.tsx:285`, mot pour mot. Trois conjoints, et le troisième dépend du
    /// mode : c'est **la** décision de ce fichier.
    public static func canSubmit(
        busy: Bool,
        email: String,
        password: String,
        mode: Mode
    ) -> Bool {
        if busy { return false }
        guard email.contains("@") else { return false }
        switch mode {
        case .signup:
            return passwordLength(password) >= signUpMinimumPasswordLength
        case .login:
            return !password.isEmpty
        }
    }

    /// « Mot de passe oublié » n'existe **qu'en mode connexion**.
    /// `App.tsx:286` : `{mode==='login'&&<Button secondary small …>}`.
    /// Et il exige l'arobase : `disabled={busy||!email.includes('@')}`.
    public static func canRequestPasswordLink(busy: Bool, email: String, mode: Mode) -> Bool {
        mode == .login && !busy && email.contains("@")
    }

    /// « Renvoyer la confirmation » n'existe **qu'en mode inscription**.
    /// `App.tsx:287` : `{mode==='signup'&&message&&<Button …>}` — il n'apparaît
    /// donc qu'**après un premier message**, ce qu'un portage pressé oublierait.
    /// Sa condition d'armement est la même que celle du lien : l'arobase.
    public static func canResendConfirmation(
        busy: Bool,
        email: String,
        mode: Mode,
        message: String?
    ) -> Bool {
        guard mode == .signup else { return false }
        guard let message, !message.isEmpty else { return false }
        return !busy && email.contains("@")
    }

    /// « Retour » ramène au choix — et **efface le message**.
    /// `App.tsx:288` : `onPress={()=>{setMode(null);setMessage('');}}`.
    /// Oublier le second geste ferait réapparaître l'ancienne erreur au retour
    /// dans l'autre mode.
    public static func afterBack(message: String?) -> (mode: Mode?, message: String) {
        (nil, "")
    }
}
