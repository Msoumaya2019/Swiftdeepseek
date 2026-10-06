// Reconcile.swift
// La RÉCONCILIATION : quelle version du document partagé l'emporte.
//
// Port de `reconcileState` et `accountState` — `src/core/program.ts:65-89`.
//
// CE QUE CE FICHIER FAIT, ET CE QU'IL NE FAIT PAS
//   `OfflineMerge` fusionne TROIS versions (base, local, remote) au moment où
//   une modification locale attend d'être poussée. `Reconcile` répond à l'autre
//   question, celle posée à la CONNEXION : le document du serveur et celui du
//   cache local ne sont pas les mêmes — lequel garde-t-on, et faut-il pousser ?
//   C'est aussi la SEULE fonction qui appelle `Bookmark.merge`, porté au bloc
//   des marques-pages et jamais appelé depuis, faute de ce fichier-ci.
//
// IL OPÈRE SUR LE JSON BRUT, ET CE N'EST PAS UN CHOIX DE STYLE
//   Sept règles de l'original distinguent une clé ABSENTE d'une clé valant
//   `null` : `uiFont === undefined`, `accent === undefined`,
//   `studyProgress === undefined`, `reviewCycle === undefined` (un ternaire
//   exprès, là où tout le reste de la même ligne emploie `??`),
//   `reviewConsolidations === undefined`, `reviewPriorityDue === undefined`, et
//   `reader.testPage === undefined`. Les structs de `AppState` écrasent cette
//   distinction : une clé absente et une clé `null` y décodent toutes deux en
//   `nil`. Un portage sur les structs rendrait donc `true` là où l'original
//   rend `false` — et ressusciterait, par exemple, un cycle de révision que
//   l'utilisateur a remis à `null`. Le document fait autorité sous forme de
//   `JSONValue` (voir l'en-tête de `JSONValue.swift`).
//
//   Second piège, du même endroit : en JavaScript, une clé valant `undefined`
//   DISPARAÎT à la sérialisation. Écrire `uiFont: undefined` ne produit pas
//   `"uiFont": null` mais AUCUNE clé. L'enrichissement écrit donc une clé
//   seulement quand sa valeur existe, et la RETIRE sinon — sans quoi cette
//   application ajouterait au document partagé des `null` que l'autre
//   n'écrit jamais, et les deux documents divergeraient à contenu égal.

import Foundation

public enum Reconcile {

    /// Le résultat d'une réconciliation : le document à adopter, et s'il faut le
    /// pousser. L'original rend `{state, shouldPush}` — `src/core/program.ts:65`.
    public struct Outcome: Equatable {
        public var document: JSONValue
        public var shouldPush: Bool

        public init(document: JSONValue, shouldPush: Bool) {
            self.document = document
            self.shouldPush = shouldPush
        }
    }

    // MARK: - Vérité à la JavaScript

    /// `Boolean(v)` — la vérité JavaScript, pas celle de Swift.
    ///
    /// La différence n'est pas théorique ici : `scheduledDate` est testé par sa
    /// vérité (`s.scheduledDate ?`), donc une chaîne VIDE est remplacée comme si
    /// la clé manquait, et `onboardingDone` est testé par sa vérité aussi.
    static func truthy(_ value: JSONValue?) -> Bool {
        guard let value, !value.isNull else { return false }
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number != 0 && !number.isNaN
        case .string(let text): return !text.isEmpty
        case .array, .object: return true
        case .null: return false
        }
    }

    /// `a ?? b` : un repli déclenché par `null` ET par l'absence de la clé.
    ///
    /// À ne pas confondre avec `coalesce`, qui rend l'opérande DROIT tel quel :
    /// `undefined ?? null` vaut `null`, et cette valeur-là s'écrit.
    static func nullish(_ value: JSONValue?) -> JSONValue? {
        guard let value, !value.isNull else { return nil }
        return value
    }

    /// `a ?? b` exactement : l'opérande droit est rendu VERBATIM, même s'il vaut
    /// `null`. C'est ce qui distingue `remote.profile ?? local.profile` d'un
    /// simple `nullish` — et ce qui fait qu'un `profile: null` local s'écrit.
    static func coalesce(_ left: JSONValue?, _ right: JSONValue?) -> JSONValue? {
        if let value = nullish(left) { return value }
        return right
    }

    /// `Object.keys(v).length` — les clés d'un objet, les INDICES d'un tableau
    /// ou d'une chaîne, rien pour le reste.
    static func keyCount(_ value: JSONValue?) -> Int {
        guard let value, !value.isNull else { return 0 }
        switch value {
        case .object(let dictionary): return dictionary.count
        case .array(let values): return values.count
        case .string(let text): return text.utf16.count
        default: return 0
        }
    }

    /// `a < b` sur deux chaînes JavaScript : comparaison par UNITÉS UTF-16,
    /// code par code, et non par graphèmes.
    ///
    /// `String.<` de Swift compare des formes normalisées : deux chaînes
    /// canoniquement équivalentes y sont égales là où JavaScript les distingue,
    /// et l'ordre peut différer au-delà de l'ASCII. Ce n'est pas un détail : ce
    /// fichier compare deux `updatedAt` par `<`, et c'est cette comparaison qui
    /// décide laquelle des deux applications gagne.
    static func utf16Compare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.utf16)
        let right = Array(rhs.utf16)
        var index = 0
        while index < left.count, index < right.count {
            if left[index] != right[index] { return left[index] < right[index] ? -1 : 1 }
            index += 1
        }
        if left.count == right.count { return 0 }
        return left.count < right.count ? -1 : 1
    }

    // MARK: - Migration du lecteur, sur le document brut

    private static let legacyMushafs: Set<String> = [
        "tawjeed_test_2", "tajweed_test_2", "medine_test"
    ]

    /// `migrateReaderState` sur le document BRUT — `src/core/program.ts:59`.
    ///
    /// Rend aussi « a-t-il changé quelque chose » : `accountState` s'en sert
    /// pour décider s'il faut pousser (`safeRemote !== remote`). L'original
    /// compare deux RÉFÉRENCES, et la migration construit un objet neuf dès
    /// qu'elle touche au lecteur : `changed` est donc vrai exactement quand
    /// l'original rendrait un objet différent.
    public static func migrateRaw(_ document: JSONValue) -> (document: JSONValue, changed: Bool) {
        guard var object = document.objectValue else { return (document, false) }
        var changed = false

        // 1. Les anciennes clés de source restent lisibles, sinon les
        //    préférences et les marques-pages déjà enregistrés se perdraient.
        if var reader = object["reader"]?.objectValue,
           let mushaf = reader["mushaf"]?.stringValue,
           legacyMushafs.contains(mushaf) {
            reader["mushaf"] = .string("coran_1441")
            object["reader"] = .object(reader)
            changed = true
        }

        // 2. `scheduledDate` est la date PRÉVUE : une séance qui n'en porte pas
        //    prend sa propre date. Le test est celui de la VÉRITÉ, pas de la
        //    présence — une chaîne vide est donc remplacée.
        if let sessions = object["sessions"]?.arrayValue,
           sessions.contains(where: { !truthy($0["scheduledDate"]) }) {
            object["sessions"] = .array(sessions.map { session in
                guard var row = session.objectValue, !truthy(row["scheduledDate"]) else {
                    return session
                }
                if let date = row["date"] {
                    row["scheduledDate"] = date
                } else {
                    row.removeValue(forKey: "scheduledDate")
                }
                return .object(row)
            })
            changed = true
        }

        // 3. Un mushaf renseigné qui n'est pas `tajweedPages` est laissé tel
        //    quel — c'est le cas de `coranTest` et de `coran_1441`. Tout le
        //    reste (clé absente, `null`, chaîne vide, `tajweedPages`) retombe
        //    sur `coranTest`, avec `followAudio` ramené à `true` sauf s'il
        //    valait EXACTEMENT `false`.
        if let mushaf = object["reader"]?["mushaf"], truthy(mushaf),
           mushaf.stringValue != "tajweedPages" {
            return (.object(object), changed)
        }
        var reader = object["reader"]?.objectValue ?? [:]
        reader["mushaf"] = .string("coranTest")
        reader["followAudio"] = .bool(reader["followAudio"] != .bool(false))
        object["reader"] = .object(reader)
        return (.object(object), true)
    }

    // MARK: - Marques-pages

    /// `mergeBookmarks` — `src/core/bookmarks.ts:20`.
    ///
    /// Deux règles, et la seconde est une garantie de données : le côté gauche
    /// absent rend le droit, et pour chaque verset la version de `updatedAt` le
    /// plus GRAND l'emporte — **marque de suppression comprise**. C'est ce qui
    /// empêche un appareil encore hors ligne de ressusciter un verset supprimé.
    ///
    /// La comparaison est celle de JavaScript : `item.updatedAt > merged[id].updatedAt`
    /// rend `false` dès que l'un des deux n'est pas une chaîne, donc une entrée
    /// sans `updatedAt` n'écrase jamais rien.
    static func mergeBookmarksRaw(_ first: JSONValue?, _ second: JSONValue?) -> JSONValue? {
        guard let left = nullish(first) else { return second }
        guard let right = nullish(second) else { return first }
        guard var merged = left.objectValue, let incoming = right.objectValue else { return first }
        for (key, item) in incoming {
            guard let existing = merged[key] else {
                merged[key] = item
                continue
            }
            guard let existingAt = existing["updatedAt"]?.stringValue,
                  let incomingAt = item["updatedAt"]?.stringValue,
                  utf16Compare(existingAt, incomingAt) < 0 else { continue }
            merged[key] = item
        }
        return .object(merged)
    }

    // MARK: - Listes de pages

    /// `readPages ?? []`, réduit à un tableau de valeurs. Une clé absente, un
    /// `null` ou une valeur qui n'est pas un tableau donnent `[]` — c'est ce que
    /// fait `?? []` suivi de l'étalement.
    static func pages(_ value: JSONValue?) -> [JSONValue] {
        guard let value, case .array(let values) = value else { return [] }
        return values
    }

    /// `Array.from(new Set(values))` : l'ordre de PREMIÈRE apparition.
    ///
    /// La déduplication se fait par représentation canonique. Les valeurs ici
    /// sont des numéros de page ; pour des objets, `Set` de JavaScript compare
    /// des références là où cette fonction compare des contenus — un écart qui
    /// n'est pas atteignable avec les données réelles, et qui est dit.
    static func distinctInOrder(_ values: [JSONValue]) -> [JSONValue] {
        var seen = Set<String>()
        var result: [JSONValue] = []
        for value in values where seen.insert(value.canonical).inserted {
            result.append(value)
        }
        return result
    }

    // MARK: - Réconciliation

    /// `reconcileState(local, remote)` — `src/core/program.ts:65`.
    public static func reconcile(local input: JSONValue, remote remoteInput: JSONValue?) -> Outcome {
        let local = migrateRaw(input).document
        guard let remoteInput else {
            // Pas de document distant : le local fait foi, et il faut le pousser.
            return Outcome(document: local, shouldPush: true)
        }
        let remote = migrateRaw(remoteInput).document

        guard var remoteObject = remote.objectValue,
              let localObject = local.objectValue else {
            // Un document qui n'est pas un objet n'atteint jamais l'original :
            // `loadAccountState` et `pullState` exigent `schema === 1`. On
            // traite ce cas comme « pas de distant » plutôt que d'inventer une
            // fusion sur une valeur qui n'a pas de clés.
            return Outcome(document: local, shouldPush: true)
        }

        let remoteBookmarks = remoteObject["bookmarks"]
        let bookmarks = mergeBookmarksRaw(localObject["bookmarks"], remoteBookmarks)

        let remotePages = pages(remoteObject["readPages"])
        let unionPages = distinctInOrder(remotePages + pages(localObject["readPages"]))

        // Ces trois drapeaux disent qu'une MÉTADONNÉE a été récupérée du local
        // parce que le distant ne la portait pas. Ils forcent une poussée même
        // si le document distant semble à jour : sans eux, la métadonnée
        // récupérée ne quitterait jamais cet appareil.
        //
        // Ils se calculent AVANT l'enrichissement qui suit — après, la clé
        // existerait toujours et la question n'aurait plus de sens.
        let appearanceMetadataRecovered =
            (remoteObject["uiFont"] == nil && localObject["uiFont"] != nil)
            || (remoteObject["accent"] == nil && localObject["accent"] != nil)
            || JSONValue.array(unionPages) != JSONValue.array(remotePages)
        let studyMetadataRecovered =
            remoteObject["studyProgress"] == nil && keyCount(localObject["studyProgress"]) > 0

        // Premier enrichissement. `readPages` est TOUJOURS écrit — c'est une
        // union, jamais un `undefined` — et `studyProgress` retombe sur `{}`.
        recover("uiFont", into: &remoteObject, from: localObject)
        recover("accent", into: &remoteObject, from: localObject)
        remoteObject["readPages"] = .array(unionPages)
        recover("reviewCycleHistory", into: &remoteObject, from: localObject)
        recover("consolidationHistory", into: &remoteObject, from: localObject)
        remoteObject["studyProgress"] = nullish(remoteObject["studyProgress"])
            ?? nullish(localObject["studyProgress"])
            ?? .object([:])

        let reviewMetadataRecovered =
            (remoteObject["reviewCycle"] == nil && truthy(localObject["reviewCycle"]))
            || (remoteObject["reviewConsolidations"] == nil
                && keyCount(localObject["reviewConsolidations"]) > 0)
            || (remoteObject["reviewPriorityDue"] == nil
                && keyCount(localObject["reviewPriorityDue"]) > 0)

        recover("reviewModelStartedAt", into: &remoteObject, from: localObject)

        // `reviewCycle` est le SEUL de la famille à tester `=== undefined` au
        // lieu d'employer `??`. La différence tient sur une seule valeur : un
        // `reviewCycle` distant valant `null` est CONSERVÉ, là où `??` l'aurait
        // remplacé par le cycle local. `defaultState()` écrit ce `null` ; le
        // confondre avec une clé absente ferait revivre un cycle supprimé.
        if remoteObject["reviewCycle"] == nil {
            if let localCycle = localObject["reviewCycle"] {
                remoteObject["reviewCycle"] = localCycle
            } else {
                remoteObject.removeValue(forKey: "reviewCycle")
            }
        }
        recover("reviewConsolidations", into: &remoteObject, from: localObject)
        recover("reviewPriorityDue", into: &remoteObject, from: localObject)

        let audioPreferences = coalesce(remoteObject["audioPreferences"], localObject["audioPreferences"])

        // Premier retour anticipé : le distant n'est pas plus récent, donc le
        // LOCAL gagne — mais les marques-pages, elles, sont toujours fusionnées.
        // L'exception est l'onboarding fait ailleurs : elle fait tomber ce
        // retour pour que le distant soit adopté.
        let remoteUpdatedAt = remoteObject["updatedAt"]?.stringValue
        let localUpdatedAt = localObject["updatedAt"]?.stringValue
        let remoteIsNotNewer = remoteUpdatedAt != nil && localUpdatedAt != nil
            && utf16Compare(remoteUpdatedAt!, localUpdatedAt!) <= 0
        let onboardedElsewhere = truthy(remoteObject["onboardingDone"])
            && !truthy(localObject["onboardingDone"])
        if remoteIsNotNewer, !onboardedElsewhere {
            var adopted = localObject
            assign("bookmarks", bookmarks, into: &adopted)
            return Outcome(document: .object(adopted), shouldPush: true)
        }

        let profile = coalesce(remoteObject["profile"], localObject["profile"])
        let theme = coalesce(remoteObject["theme"], localObject["theme"])
        let notifications = coalesce(remoteObject["notifications"], localObject["notifications"])
        let lastRead = coalesce(remoteObject["lastRead"], localObject["lastRead"])
        let memorizedAt = coalesce(remoteObject["memorizedAt"], localObject["memorizedAt"])
        let reviewSettings = coalesce(remoteObject["reviewSettings"], localObject["reviewSettings"])
        let reviewHistory = coalesce(remoteObject["reviewHistory"], localObject["reviewHistory"])
        let reviewDue = coalesce(remoteObject["reviewDue"], localObject["reviewDue"])
        let difficultyMarkers = coalesce(remoteObject["difficultyMarkers"], localObject["difficultyMarkers"])
        let difficultyHistory = coalesce(remoteObject["difficultyHistory"], localObject["difficultyHistory"])

        // `reader` a sa propre règle : `testPage` est récupéré du local quand —
        // et seulement quand — le distant ne porte pas la clé. Un distant qui
        // écrit `testPage: 5` garde la main, même si le local en a un autre.
        let reader: JSONValue?
        if let remoteReader = remoteObject["reader"]?.objectValue {
            if remoteReader["testPage"] == nil,
               let localReader = localObject["reader"]?.objectValue,
               let testPage = localReader["testPage"] {
                var merged = remoteReader
                merged["testPage"] = testPage
                reader = .object(merged)
            } else {
                reader = .object(remoteReader)
            }
        } else {
            // Un `reader` distant valant `null` est une VALEUR, pas une absence :
            // il s'écrit tel quel, comme le fait `{...remote, reader}`.
            reader = localObject["reader"]
        }

        // Second retour anticipé, le seul qui ne pousse RIEN : si aucune
        // métadonnée n'a été récupérée et que tous les champs repris du local
        // sont en fait ceux du distant, alors le distant est déjà complet.
        //
        // Les quinze comparaisons de l'original sont des comparaisons de
        // RÉFÉRENCES ; l'égalité de valeur rend la même DÉCISION dans les six
        // cas possibles — c'est elle qui est portée ici, et c'est elle qui est
        // éprouvée.
        let unchanged =
            !appearanceMetadataRecovered && !studyMetadataRecovered && !reviewMetadataRecovered
            && audioPreferences == remoteObject["audioPreferences"]
            && bookmarks == remoteBookmarks
            && profile == remoteObject["profile"]
            && theme == remoteObject["theme"]
            && notifications == remoteObject["notifications"]
            && reader == remoteObject["reader"]
            && lastRead == remoteObject["lastRead"]
            && memorizedAt == remoteObject["memorizedAt"]
            && reviewSettings == remoteObject["reviewSettings"]
            && reviewHistory == remoteObject["reviewHistory"]
            && reviewDue == remoteObject["reviewDue"]
            && difficultyMarkers == remoteObject["difficultyMarkers"]
            && difficultyHistory == remoteObject["difficultyHistory"]
        if unchanged {
            return Outcome(document: .object(remoteObject), shouldPush: false)
        }

        // Dernier cas : le distant gagne, enrichi de ce que le local avait en
        // plus, et l'horodatage est avancé au-delà des deux.
        //
        // DIVERGENCE ASSUMÉE : l'original fait `Date.parse(remote.updatedAt)` et
        // lève un `RangeError` si la clé manque — `Math.max(now, NaN)` vaut NaN
        // et `new Date(NaN).toISOString()` lève. Ici un horodatage illisible est
        // simplement ignoré, ce qui laisse l'autre côté décider. Les documents
        // des deux applications portent toujours `updatedAt`, donc ce chemin
        // n'est pas atteignable ; il vaut mieux ne rien écrire que de lever.
        let updatedAt = DateKeys.maxISO([
            remoteUpdatedAt.flatMap(DateKeys.parseISO),
            localUpdatedAt.flatMap(DateKeys.parseISO)
        ])

        var result = remoteObject
        assign("bookmarks", bookmarks, into: &result)
        assign("audioPreferences", audioPreferences, into: &result)
        assign("profile", profile, into: &result)
        assign("theme", theme, into: &result)
        assign("notifications", notifications, into: &result)
        assign("reader", reader, into: &result)
        assign("lastRead", lastRead, into: &result)
        assign("memorizedAt", memorizedAt, into: &result)
        assign("reviewSettings", reviewSettings, into: &result)
        assign("reviewHistory", reviewHistory, into: &result)
        assign("reviewDue", reviewDue, into: &result)
        assign("difficultyMarkers", difficultyMarkers, into: &result)
        assign("difficultyHistory", difficultyHistory, into: &result)
        result["updatedAt"] = .string(updatedAt)
        return Outcome(document: .object(result), shouldPush: true)
    }

    // MARK: - Le compte

    /// `accountState(userId, cached, remote)` — `src/core/program.ts:82`.
    ///
    /// Trois protections, dans cet ordre :
    ///   - un cache qui appartient à un AUTRE compte n'est pas un état local :
    ///     on repart du document par défaut ;
    ///   - un document distant marqué d'un AUTRE `userId` n'est pas adopté — il
    ///     est traité comme absent ;
    ///   - le `userId` du compte est écrit dans tous les cas, et un document qui
    ///     ne le portait pas est poussé.
    public static func accountState(
        userId: String,
        cache: JSONValue?,
        remote: JSONValue?
    ) -> Outcome {
        let cachedIsOurs = cache?["userId"]?.stringValue == userId
        let local = cachedIsOurs ? (cache ?? defaultDocument()) : defaultDocument()

        let foreignRemote = truthy(remote?["userId"]) && remote?["userId"]?.stringValue != userId
        let migrated = remote.map { migrateRaw($0) }
        let safeRemote: JSONValue? = foreignRemote ? nil : migrated?.document
        let remoteWasMigrated = migrated?.changed ?? false

        if !cachedIsOurs, let safeRemote {
            var adopted = safeRemote
            if case .object(var object) = adopted {
                object["userId"] = .string(userId)
                adopted = .object(object)
            }
            let shouldPush = safeRemote["userId"]?.stringValue != userId || remoteWasMigrated
            return Outcome(document: adopted, shouldPush: shouldPush)
        }

        let result = reconcile(local: local, remote: safeRemote)
        var owned = result.document
        if case .object(var object) = owned {
            object["userId"] = .string(userId)
            owned = .object(object)
        }
        let shouldPush = result.shouldPush
            || result.document["userId"]?.stringValue != userId
            || remoteWasMigrated
        return Outcome(document: owned, shouldPush: shouldPush)
    }

    // MARK: - Document par défaut

    /// `defaultState()` — `src/core/program.ts:57`, sur le document BRUT.
    ///
    /// Il n'est PAS la sérialisation de `Program.defaultState()` : celle-ci
    /// écrit une dizaine de clés supplémentaires valant `null` (`onboardingStep`,
    /// `userId`, `profile`, `uiFont`, `accent`, `audioPreferences`, `bookmarks`,
    /// `readPages`, `lastRead`, `reviewModelStartedAt`), que l'original ne
    /// produit pas. La différence n'est pas cosmétique : `accountState` part de
    /// ce document quand le cache appartient à un autre compte, et une clé
    /// `uiFont` valant `null` y répondrait `true` là où l'original répond
    /// `false` à `remote.uiFont === undefined && local.uiFont !== undefined`.
    ///
    /// Les vingt-quatre clés, et leurs valeurs, sont celles de l'original.
    public static func defaultDocument() -> JSONValue {
        .object([
            "schema": .number(1),
            "onboardingDone": .bool(false),
            "updatedAt": .string("1970-01-01T00:00:00.000Z"),
            "knowledge": .object([:]),
            "goal": .object([
                "label": .string("Juz’ ‘Amma"),
                "ranges": .array([
                    .object(["start": .number(5673), "end": .number(6236)])
                ])
            ]),
            "pace": .string("verse3"),
            "learningDays": .array([1, 2, 3, 4, 5].map { JSONValue.number(Double($0)) }),
            "sessions": .array([]),
            "revisions": .array([]),
            "memorizedAt": .object([:]),
            "reviewSettings": .object(["enabled": .bool(true), "cycleDays": .number(7)]),
            "reviewHistory": .array([]),
            "reviewDue": .object([:]),
            "difficultyMarkers": .object([:]),
            "difficultyHistory": .array([]),
            "reviewCycle": .null,
            "reviewConsolidations": .object([:]),
            "reviewPriorityDue": .object([:]),
            "reviewCycleHistory": .array([]),
            "consolidationHistory": .array([]),
            "studyProgress": .object([:]),
            "theme": .string("white"),
            "notifications": .object(["messages": .bool(true), "learning": .bool(false)]),
            "reader": .object(["mushaf": .string("coranTest"), "followAudio": .bool(true)])
        ])
    }

    // MARK: - Écriture d'une clé

    /// Écrit une clé — ou la RETIRE quand la valeur est absente, parce qu'une
    /// clé valant `undefined` ne se sérialise pas en JavaScript. Écrire
    /// `.null` ici produirait un document différent de celui de l'autre
    /// application, à contenu égal.
    private static func assign(_ key: String, _ value: JSONValue?, into object: inout [String: JSONValue]) {
        if let value {
            object[key] = value
        } else {
            object.removeValue(forKey: key)
        }
    }

    /// `remote.clé = remote.clé ?? local.clé`, avec l'omission décrite ci-dessus.
    private static func recover(
        _ key: String,
        into remote: inout [String: JSONValue],
        from local: [String: JSONValue]
    ) {
        assign(key, coalesce(remote[key], local[key]), into: &remote)
    }
}
