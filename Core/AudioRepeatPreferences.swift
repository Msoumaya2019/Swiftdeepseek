// AudioRepeatPreferences.swift
// Les préférences de répétition audio — la partie PURE, sans AVFoundation.
//
// POURQUOI CE FICHIER
//   `PassageAudioPlayer.tsx` tient six réglages dans son état (`:55-56`) et les
//   persiste sous la clé `audio-repeat-preferences` (`:182` en lecture, `:184`
//   en écriture). Ce qui décide du comportement n'est pas ce que l'utilisateur
//   voit, mais ce que `:78-79` en dérive :
//
//       const count:RepeatCount = countChoice==='custom' ? Number(customCount) : countChoice;
//       settingsRef.current={count:count==='continuous'?count:Number.isInteger(count)&&count>0?count:1,
//                            mode:repeatMode,gap,autoStop,speed};
//
//   Trois règles y sont silencieuses, et s'y tromper ne lève aucune erreur :
//
//   1. `Number(customCount)` est le `Number()` de JavaScript, pas un entier
//      Swift : `'0x10'` vaut 16, `'1e3'` vaut 1000, `''` vaut 0, `'1,5'` ne vaut
//      rien — et tout ce qui n'est pas un entier strictement positif retombe
//      sur **1**. Le champ est un pavé numérique, mais le fichier relu, lui,
//      n'est pas forcément ce que le pavé numérique produit.
//   2. Le nombre NORMALISÉ n'est pas le nombre VALIDÉ. `:79` accepte n'importe
//      quel entier strictement positif ; `:176` refuse de **lancer** au-delà de
//      999. Un `customCount` de `'5000'` produit donc les deux à la fois : un
//      compte de 5000 dans les réglages, et un refus de lancement.
//   3. La validation au chargement (`:182`) est **champ par champ** et en
//      **égalité stricte** : `"3"` n'est pas `3`, et un champ invalide garde sa
//      valeur par défaut sans invalider les autres.
//
// CE QUI EST STOCKÉ N'EST PAS CE QUI EST AFFICHÉ
//   `autoStop` reste **vrai** quand on choisit `continuous` ; c'est l'affichage
//   qui le décoche (`:248` et `:268` : `selected={autoStop&&countChoice!=='continuous'}`).
//   Même chose pour le dénominateur `∞`, qui apparaît quand `countChoice` est
//   `continuous` **ou** quand `autoStop` est faux (`:256`, `:258`), alors que la
//   pastille de cycle rapide (`:241`) ne regarde que `count`. Ne jamais réécrire
//   le réglage pour se simplifier l'affichage.
//
// CES RÉGLAGES RESTENT LOCAUX
//   `LOCAL_DATA_MIGRATION.md` §4 a) a tranché : rien n'est ajouté à `user_state`,
//   les deux applications ne partagent pas ces préférences. Le fichier écrit ici
//   reprend malgré tout la **forme** de l'original — mêmes clés, mêmes types —
//   pour que les deux applications se comportent identiquement à choix égal, et
//   pour qu'un export éventuel n'ait rien à traduire.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Tous les nombres figés par `Tests/AudioRepeatPreferencesTests.swift` viennent
//   de la section 13 de `_banc/oracle-audio.mjs`. Le banc extrait TEXTUELLEMENT
//   ces expressions de `PassageAudioPlayer.tsx`, refuse de compter si leur forme
//   a changé, puis compare la formulation du portage à celle de l'original.

import Foundation

/// Les six réglages de `PassageAudioPlayer.tsx:55-56`, et ce qu'ils décident.
public struct AudioRepeatPreferences: Equatable, Sendable {

    /// `counts` — `PassageAudioPlayer.tsx:14` :
    /// `[1,2,3,5,10,'custom','continuous']`. `'custom'` n'est pas un nombre :
    /// c'est l'aveu que le nombre vient du champ libre.
    public enum CountChoice: Equatable, Sendable {
        case times(Int)
        case custom
        case continuous
    }

    public var countChoice: CountChoice
    /// Le champ libre, gardé en **chaîne** : c'est ce que l'original stocke
    /// (`typeof prefs.customCount === 'string'`, `:182`), et c'est ce qui permet
    /// à `'1,5'` de rester affiché tel quel après avoir été refusé.
    public var customCount: String
    public var repeatMode: RepeatMode
    public var gap: Int
    public var speed: Double
    public var autoStop: Bool

    public init(
        countChoice: CountChoice = .times(3),
        customCount: String = "20",
        repeatMode: RepeatMode = .passage,
        gap: Int = 0,
        speed: Double = 1,
        autoStop: Bool = true
    ) {
        self.countChoice = countChoice
        self.customCount = customCount
        self.repeatMode = repeatMode
        self.gap = gap
        self.speed = speed
        self.autoStop = autoStop
    }

    /// `PassageAudioPlayer.tsx:55-56` — les valeurs de départ, **mesurées** :
    /// `countChoice = 3`, `customCount = '20'`, `repeatMode = 'passage'`,
    /// `gap = 0`, `speed = 1`, `autoStop = true`.
    public static let defaults = AudioRepeatPreferences()

    /// `PassageAudioPlayer.tsx:14` — l'ordre compte : il est celui des pastilles.
    public static let countChoices: [CountChoice] = [
        .times(1), .times(2), .times(3), .times(5), .times(10), .custom, .continuous
    ]

    /// `PassageAudioPlayer.tsx:241` — la pastille de cycle rapide, qui saute
    /// **`'custom'`** : `[1,2,3,5,10,'continuous']`. Six valeurs, pas sept.
    public static let quickCountChoices: [CountChoice] = [
        .times(1), .times(2), .times(3), .times(5), .times(10), .continuous
    ]

    /// `[0,2,5,10]` — `:182` (validation) et `:248` (pastilles).
    public static let gapChoices: [Int] = [0, 2, 5, 10]

    /// `[0.75,1,1.25]` — `:182` (validation) et `:248` (pastilles).
    public static let speedChoices: [Double] = [0.75, 1, 1.25]

    /// La borne du refus de lancement, `:176`. C'est la **seule** contrainte
    /// haute : `:79` n'en a aucune.
    public static let customCountRange = 1...999

    // MARK: - Le nombre qui décide

    /// `Number(customCount)` de JavaScript, réduit à ce que l'application en
    /// fait. Rend `nil` là où JavaScript rend `NaN`.
    ///
    /// Le portage est fidèle sur quatre points que `Double(_:)` seul ne couvre
    /// pas : le blanc de la spécification (qui inclut `U+00A0` et `U+FEFF`, pas
    /// seulement l'espace ASCII), la chaîne vide qui vaut **0**, les littéraux
    /// entiers non décimaux (`0x10` vaut 16, `0b101` vaut 5), et les formes
    /// décimales que JavaScript accepte (`'1.'`, `'.5'`, `'1.e3'`) — que
    /// `Double(_:)` refuse ou accepte selon les cas, sans règle commune.
    public static func jsNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: jsWhitespace)
        if trimmed.isEmpty { return 0 }

        let scalars = Array(trimmed.unicodeScalars)

        // `Infinity` — et rien d'autre : `Number('inf')` vaut NaN, alors que
        // `Double('inf')` vaut l'infini. D'où la comparaison sur le texte.
        if trimmed == "Infinity" || trimmed == "+Infinity" { return Double.infinity }
        if trimmed == "-Infinity" { return -Double.infinity }

        // Littéraux entiers non décimaux, SANS signe : `Number('-0x10')` est NaN.
        if scalars.count > 2, scalars[0].value == 48 {
            let marker = scalars[1].value
            let radix: Int?
            switch marker {
            case 120, 88: radix = 16     // x X
            case 111, 79: radix = 8      // o O
            case 98, 66: radix = 2       // b B
            default: radix = nil
            }
            if let radix {
                var value: Double = 0
                for scalar in scalars.dropFirst(2) {
                    guard let digit = digitValue(scalar), digit < radix else { return nil }
                    // Accumulé en `Double` : `Int(_:radix:)` rendrait `nil` sur
                    // débordement là où JavaScript, lui, arrondit.
                    value = value * Double(radix) + Double(digit)
                }
                return value
            }
        }

        guard isDecimalLiteral(scalars) else { return nil }
        // La grammaire est vérifiée, mais `Double(_:)` refuse encore `'1.'`,
        // `'.5'` et `'1.e3'` — que JavaScript accepte. On remet donc le littéral
        // sous une forme canonique avant de le lui donner : ce qui reste non
        // prouvé se réduit alors à « `Double` lit un littéral décimal ordinaire ».
        guard let canonical = canonicalDecimal(trimmed) else { return nil }
        return Double(canonical)
    }

    /// `'1.'` → `'1'`, `'.5'` → `'0.5'`, `'1.e3'` → `'1e3'`. Appelée seulement
    /// après `isDecimalLiteral`, donc l'entrée est déjà bien formée.
    private static func canonicalDecimal(_ text: String) -> String? {
        var body = Substring(text)
        var exponent = ""
        if let index = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            body = text[text.startIndex..<index]
            exponent = String(text[text.index(after: index)...])
        }
        var mantissa = String(body)
        var sign = ""
        if mantissa.hasPrefix("+") || mantissa.hasPrefix("-") {
            sign = String(mantissa.removeFirst())
        }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        if mantissa.isEmpty { return nil }
        if mantissa.hasPrefix(".") { mantissa = "0" + mantissa }
        return sign + mantissa + (exponent.isEmpty ? "" : "e" + exponent)
    }

    /// `Number.isInteger(count) && count > 0 ? count : 1` — `PassageAudioPlayer.tsx:79`.
    ///
    /// C'est la normalisation réelle du compte : `nil` (NaN), `0`, un négatif,
    /// `2.5` et `Infinity` valent tous **1**, sans erreur.
    public static func isPositiveInteger(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value == value.rounded() && value > 0
    }

    /// Le seul usage que l'application fait du champ libre : un entier
    /// strictement positif, exactement représentable.
    ///
    /// La borne haute est `2^53`, au-delà de laquelle un `Double` ne porte plus
    /// les entiers un à un — et au-delà de laquelle `Int(value)` piégerait. Ce
    /// n'est pas une règle de l'original : c'est la limite du type qui la porte.
    /// Aucun pavé numérique ne la produit, et le fichier écrit par l'application
    /// ne la contient pas.
    public static func customInteger(_ text: String) -> Int? {
        guard let value = jsNumber(text),
              value.isFinite,
              value == value.rounded(),
              value >= 1,
              value <= 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }

    /// `PassageAudioPlayer.tsx:78` puis `:79` — le compte tel que le moteur le
    /// reçoit. Le mode `passage` / `each-verse` ne change rien ici : le compte
    /// est le même pour les deux.
    ///
    /// `Self.` n'est pas décoratif : un membre **statique** référencé depuis un
    /// contexte d'instance doit être qualifié, sinon le compilateur répond
    /// « static member cannot be used on instance of type ». Mesuré — c'est le
    /// seul défaut que la compilation du run #39 a relevé.
    public var count: RepeatCount {
        switch countChoice {
        case .continuous:
            return .continuous
        case .times(let value):
            return value > 0 ? .times(value) : .times(1)
        case .custom:
            guard let value = Self.customInteger(customCount) else { return .times(1) }
            return .times(value)
        }
    }

    /// `PassageAudioPlayer.tsx:176` — le refus de **lancer**, et son message.
    ///
    /// Il ne porte que sur `'custom'` : les autres choix sont des valeurs de la
    /// liste, donc valides par construction. Et il est plus étroit que la
    /// normalisation : `'1.5'` est refusé (non entier) et `'5000'` aussi (trop
    /// grand), alors que `:79` les aurait normalisés en 1 et 5000.
    public var launchError: PassageAudioError? {
        guard countChoice == .custom else { return nil }
        // Comparé en `Double` : `Int(value)` piégerait sur `'1e300'`, qui est un
        // entier fini pour JavaScript — et que l'original refuse, justement.
        guard let value = Self.jsNumber(customCount),
              value.isFinite,
              value == value.rounded(),
              value >= Double(Self.customCountRange.lowerBound),
              value <= Double(Self.customCountRange.upperBound) else {
            return PassageAudioError(message: "Choisis entre 1 et 999 écoutes.")
        }
        return nil
    }

    // MARK: - Ce qui s'affiche

    /// `PassageAudioPlayer.tsx:15` — `'∞'`, `'Autre'`, ou le nombre.
    public static func countLabel(_ choice: CountChoice) -> String {
        switch choice {
        case .continuous: return "∞"
        case .custom: return "Autre"
        case .times(let value): return String(value)
        }
    }

    /// `PassageAudioPlayer.tsx:240` et `:241` — `count==='continuous'?'∞':count`.
    public static func countText(_ count: RepeatCount) -> String {
        switch count {
        case .continuous: return "∞"
        case .times(let value): return String(value)
        }
    }

    /// `PassageAudioPlayer.tsx:256` et `:258` —
    /// `countChoice==='continuous'||!autoStop?'∞':count`.
    ///
    /// Deux causes distinctes au même `∞` : le choix « en continu », et
    /// l'arrêt automatique décoché — qui fait tourner le passage sans fin sans
    /// que le compte change.
    public var displaysUnlimitedRepetition: Bool {
        countChoice == .continuous || !autoStop
    }

    /// `PassageAudioPlayer.tsx:248` et `:268` —
    /// `selected={autoStop&&countChoice!=='continuous'}`.
    ///
    /// La case se **décoche** sur « en continu » sans que `autoStop` soit
    /// réécrit : décocher pour de vrai est un geste distinct, et il survit au
    /// retour en arrière.
    public var showsAutoStopSelected: Bool {
        autoStop && countChoice != .continuous
    }

    /// `PassageAudioPlayer.tsx:241` — la pastille de cycle rapide :
    /// `values[(values.indexOf(count)+1)%values.length]`, avec
    /// `values=[1,2,3,5,10,'continuous']`.
    ///
    /// Un compte absent de la liste — un « Autre » de 4, ou de 5000 — donne
    /// `indexOf` = -1, donc `(0)%6` = 0, donc **1**. C'est le comportement de
    /// l'original, et il n'est pas devinable.
    public static func nextQuickCount(after count: RepeatCount) -> CountChoice {
        let found = quickCountChoices.firstIndex { candidate in
            switch (candidate, count) {
            case (.continuous, .continuous): return true
            case (.times(let left), .times(let right)): return left == right
            default: return false
            }
        } ?? -1
        let size = quickCountChoices.count
        return quickCountChoices[((found + 1) % size + size) % size]
    }

    // MARK: - Le fichier local

    /// `PassageAudioPlayer.tsx:184` — `JSON.stringify({countChoice,customCount,repeatMode,gap,speed,autoStop})`.
    public var encoded: JSONValue {
        .object([
            "countChoice": countChoice.encoded,
            "customCount": .string(customCount),
            "repeatMode": .string(repeatMode.rawValue),
            "gap": .number(Double(gap)),
            "speed": .number(speed),
            "autoStop": .bool(autoStop)
        ])
    }

    /// `PassageAudioPlayer.tsx:182` — la relecture, **champ par champ**.
    ///
    /// Chaque champ est validé isolément et en égalité stricte ; un champ absent,
    /// d'un autre type, ou hors de sa liste garde sa valeur par défaut. Un
    /// document qui n'est pas un objet — `null`, un nombre, une chaîne, un
    /// tableau — rend les valeurs par défaut : c'est ce que fait l'original, où
    /// `prefs.countChoice` vaut alors `undefined`, ce que `counts.includes`
    /// refuse.
    public static func decode(_ document: JSONValue?) -> AudioRepeatPreferences {
        var preferences = defaults
        guard let document, case .object(let fields) = document else { return preferences }

        if let raw = fields["countChoice"] {
            if case .string("custom") = raw {
                preferences.countChoice = .custom
            } else if case .string("continuous") = raw {
                preferences.countChoice = .continuous
            } else if let value = raw.doubleValue, let choice = fixedCountChoice(value) {
                preferences.countChoice = choice
            }
        }
        if let raw = fields["customCount"], case .string(let text) = raw {
            preferences.customCount = text
        }
        if let raw = fields["repeatMode"], case .string(let text) = raw,
           let mode = RepeatMode(rawValue: text) {
            preferences.repeatMode = mode
        }
        if let raw = fields["gap"], let value = raw.doubleValue,
           gapChoices.contains(where: { Double($0) == value }) {
            preferences.gap = Int(value)
        }
        if let raw = fields["speed"], let value = raw.doubleValue,
           speedChoices.contains(value) {
            preferences.speed = value
        }
        if let raw = fields["autoStop"], case .bool(let value) = raw {
            preferences.autoStop = value
        }
        return preferences
    }

    /// `counts.includes(value)` pour la partie numérique de la liste, qui est en
    /// **égalité stricte** : `3.5` n'y est pas, et `"3"` non plus.
    private static func fixedCountChoice(_ value: Double) -> CountChoice? {
        for choice in countChoices {
            if case .times(let number) = choice, Double(number) == value { return choice }
        }
        return nil
    }

    // MARK: - Le blanc et les chiffres de JavaScript

    /// `StrWhiteSpaceChar` de la spécification. Plus large que
    /// `CharacterSet.whitespacesAndNewlines` : ni `U+FEFF` (sans chasse, classe
    /// `Cf`) ni `U+200B` n'y figurent côté Foundation, alors que JavaScript élague
    /// le premier.
    private static let jsWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}"
        + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}"
        + "\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

    /// `StrDecimalLiteral` : `[+|-] ( chiffres [. chiffres?]? | . chiffres ) ( [eE] [+|-]? chiffres )?`.
    ///
    /// Vérifié avant d'appeler `Double(_:)`, qui est plus permissif sur d'autres
    /// formes (`'inf'`, `'nan'`) et plus strict sur celles-ci (`'1.'`, `'.5e2'`).
    private static func isDecimalLiteral(_ scalars: [UnicodeScalar]) -> Bool {
        var index = 0
        func current() -> UnicodeScalar? { index < scalars.count ? scalars[index] : nil }
        func takeDigits() -> Int {
            var count = 0
            while let scalar = current(), (48...57).contains(scalar.value) { index += 1; count += 1 }
            return count
        }

        if let sign = current(), sign.value == 43 || sign.value == 45 { index += 1 }

        let whole = takeDigits()
        if let point = current(), point.value == 46 {
            index += 1
            let fraction = takeDigits()
            if whole == 0 && fraction == 0 { return false }
        } else if whole == 0 {
            return false
        }

        if let exponent = current(), exponent.value == 101 || exponent.value == 69 {
            index += 1
            if let sign = current(), sign.value == 43 || sign.value == 45 { index += 1 }
            if takeDigits() == 0 { return false }
        }
        return index == scalars.count
    }

    private static func digitValue(_ scalar: UnicodeScalar) -> Int? {
        switch scalar.value {
        case 48...57: return Int(scalar.value - 48)     // 0-9
        case 65...70: return Int(scalar.value - 55)     // A-F
        case 97...102: return Int(scalar.value - 87)    // a-f
        default: return nil
        }
    }
}

public extension AudioRepeatPreferences.CountChoice {
    /// La forme écrite dans le fichier local : un nombre, ou l'un des deux mots.
    var encoded: JSONValue {
        switch self {
        case .custom: return .string("custom")
        case .continuous: return .string("continuous")
        case .times(let value): return .number(Double(value))
        }
    }
}
