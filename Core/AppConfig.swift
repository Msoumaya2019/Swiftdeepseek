// AppConfig.swift
// Configuration publique du client.
//
// SÉCURITÉ — deux règles non négociables :
//   1. La clé `service_role` n'a rien à faire ici. Elle contourne RLS et ne doit
//      jamais quitter le serveur. Cette application n'utilise que la clé
//      PUBLIABLE (`anon` / `publishable`), qui est faite pour être embarquée
//      dans un client : c'est RLS et Supabase Auth qui assurent la sécurité.
//   2. Aucun secret n'est committé. Les valeurs arrivent par `Secrets.xcconfig`
//      (ignoré par Git) et sont injectées dans Info.plist à la compilation.
//
// Robustesse : une configuration absente ne doit pas faire planter l'application
// au lancement. Les valeurs sont donc facultatives, et `configurationProblem`
// décrit ce qui manque pour que l'écran d'accueil puisse l'expliquer.

import Foundation

public enum AppConfig {

    private static let info = Bundle.main.infoDictionary ?? [:]

    /// URL du projet Supabase. C'est la MÊME instance que l'application
    /// React Native : les comptes et les données sont donc partagés.
    public static var supabaseURLString: String? {
        guard let raw = info["SUPABASE_URL"] as? String, !raw.isEmpty else { return nil }
        return raw
    }

    /// Clé PUBLIABLE uniquement. Jamais la clé `service_role`.
    public static var supabaseKey: String? {
        guard let raw = info["SUPABASE_ANON_KEY"] as? String, !raw.isEmpty else { return nil }
        return raw
    }

    /// Adresse de repli : jamais utilisée en pratique, elle n'existe que pour
    /// éviter un plantage lorsque la configuration manque. Les requêtes
    /// échoueront proprement, et l'écran de configuration l'expliquera.
    private static let placeholder = URL(string: "https://configuration-absente.invalid")!

    public static var supabaseURL: URL {
        guard let raw = supabaseURLString, let url = URL(string: raw) else { return placeholder }
        return url
    }

    public static var supabasePublishableKey: String { supabaseKey ?? "" }

    public static var isConfigured: Bool {
        supabaseURLString != nil && supabaseKey != nil
    }

    /// Ce qui manque, en clair, ou `nil` si tout est en place.
    public static var configurationProblem: String? {
        switch (supabaseURLString, supabaseKey) {
        case (nil, nil):
            return "Les réglages SUPABASE_URL et SUPABASE_ANON_KEY sont absents de l'application."
        case (nil, _):
            return "Le réglage SUPABASE_URL est absent de l'application."
        case (_, nil):
            return "Le réglage SUPABASE_ANON_KEY est absent de l'application."
        default:
            return nil
        }
    }

    /// Schéma d'URL propre à l'application. Volontairement DIFFÉRENT de celui de
    /// l'application React Native (`coranmemoire://`) : deux applications
    /// distinctes ne doivent pas se disputer le même schéma au niveau du
    /// système. Les liens de confirmation d'e-mail et de réinitialisation
    /// pointent vers ce schéma pour la nouvelle application.
    public static let urlScheme = "swiftdeepseek"
    public static let authRedirect = "swiftdeepseek://auth"

    /// Bundle identifier propre à la nouvelle application. Celui de
    /// l'application React Native (`fr.coranmemoire.app`) n'est pas touché.
    public static let bundleIdentifier = "fr.swiftdeepseek.app"

    /// Délai maximal d'une requête, aligné sur celui de l'application
    /// React Native (`sync.ts:10` — 8000 ms).
    public static let requestTimeout: TimeInterval = 8
}
