// OfflineMerge.swift
// Port fidèle de `src/core/offlineMerge.ts`.
//
// C'EST LE FICHIER LE PLUS IMPORTANT DU PROJET POUR LA COMPATIBILITÉ.
// Les deux applications écrivent le même document `user_state.data`. Quand un
// appareil était hors ligne, il faut réconcilier trois versions :
//   base   = la dernière version dont on savait qu'elle était synchronisée
//   local  = ce que cet appareil a modifié hors ligne
//   remote = ce que le serveur contient maintenant
//
// Règle : un champ inchangé localement hérite du serveur ; une modification
// locale explicite (y compris une suppression) l'emporte sur un conflit de même
// champ. Les identifiants préservent l'historique.
//
// Le raisonnement est identique à celui de React Native, opération par
// opération. Toute divergence ferait perdre des données à l'un des deux clients.

import Foundation

public enum OfflineMerge {

    // MARK: Prédicats

    private static func objectValue(_ value: JSONValue?) -> [String: JSONValue]? {
        guard let value, case .object(let dictionary) = value else { return nil }
        return dictionary
    }

    private static func numberValue(_ value: JSONValue?) -> Double? {
        value?.doubleValue
    }

    /// `JSON.stringify(a) === JSON.stringify(b)`.
    /// `nil` représente `undefined` : `same(undefined, undefined)` est vrai.
    private static func same(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (lhs?, rhs?): return lhs.canonical == rhs.canonical
        }
    }

    private static func dedupeNumbers(_ values: [JSONValue]) -> [JSONValue] {
        var seen = Set<Double>()
        var out: [JSONValue] = []
        for value in values {
            guard let number = value.doubleValue else { continue }
            if seen.insert(number).inserted { out.append(value) }
        }
        return out.sorted { ($0.doubleValue ?? 0) < ($1.doubleValue ?? 0) }
    }

    /// Déduplication par valeur JSON, en conservant l'ordre de première
    /// apparition (comme `new Map([...]).values()`).
    private static func dedupeValues(_ values: [JSONValue]) -> [JSONValue] {
        var seen = Set<String>()
        var out: [JSONValue] = []
        for value in values where seen.insert(value.canonical).inserted {
            out.append(value)
        }
        return out
    }

    // MARK: Fusion récursive

    static func merge(
        base: JSONValue?,
        local: JSONValue?,
        remote: JSONValue?,
        path: String
    ) -> JSONValue? {
        if same(local, base) { return remote }
        if same(remote, base) || same(local, remote) { return local }

        if let localArray = local?.arrayValue, let remoteArray = remote?.arrayValue {
            // Tableaux d'objets portant un `id` : fusion par identifiant.
            let combined = localArray + remoteArray
            let allIdentified = combined.allSatisfy { value in
                objectValue(value)?["id"]?.stringValue != nil
            }
            if allIdentified {
                func keyed(_ rows: [JSONValue]) -> [String: JSONValue] {
                    var out: [String: JSONValue] = [:]
                    for row in rows {
                        if let id = objectValue(row)?["id"]?.stringValue { out[id] = row }
                    }
                    return out
                }
                let baseKeyed = keyed(base?.arrayValue ?? [])
                let localKeyed = keyed(localArray)
                let remoteKeyed = keyed(remoteArray)

                var keys: [String] = []
                for key in localKeyed.keys where !keys.contains(key) { keys.append(key) }
                for key in remoteKeyed.keys where !keys.contains(key) { keys.append(key) }

                var result: [JSONValue] = []
                for key in keys {
                    let value: JSONValue?
                    if localKeyed[key] == nil,
                       objectValue(remoteKeyed[key])?["status"]?.stringValue == "done" {
                        value = remoteKeyed[key]
                    } else {
                        value = merge(
                            base: baseKeyed[key],
                            local: localKeyed[key],
                            remote: remoteKeyed[key],
                            path: path + "." + key
                        )
                    }
                    if let value { result.append(value) }
                }
                return .array(result)
            }

            // Journaux de validation et historiques : union sans doublon.
            if path.hasSuffix("validations") || path.hasSuffix("History") {
                return .array(dedupeValues(remoteArray + localArray))
            }
            if path.hasSuffix("readPages") {
                return .array(dedupeNumbers(localArray + remoteArray))
            }
            if path.hasSuffix("completed"), combined.allSatisfy({ $0.doubleValue != nil }) {
                return .array(dedupeNumbers(localArray + remoteArray))
            }
            return local
        }

        if objectValue(remote) != nil,
           objectValue(local) != nil || (local == nil && objectValue(base) != nil) {
            let localObject = objectValue(local) ?? [:]
            let baseObject = objectValue(base) ?? [:]
            let remoteObject = objectValue(remote) ?? [:]

            var keys: [String] = []
            for key in baseObject.keys where !keys.contains(key) { keys.append(key) }
            for key in localObject.keys where !keys.contains(key) { keys.append(key) }
            for key in remoteObject.keys where !keys.contains(key) { keys.append(key) }

            var result: [String: JSONValue] = [:]
            for key in keys {
                if let value = merge(
                    base: baseObject[key],
                    local: localObject[key],
                    remote: remoteObject[key],
                    path: path + "." + key
                ) {
                    result[key] = value
                }
            }
            // Recalcule l'avancement d'une tâche d'étude d'après son point d'arrêt.
            if let through = result["through"]?.doubleValue,
               let end = result["end"]?.doubleValue {
                result["status"] = .string(through >= end ? "completed" : "partial")
            }
            return .object(result)
        }

        if path.hasSuffix(".through"),
           let localNumber = numberValue(local),
           let remoteNumber = numberValue(remote) {
            return .number(max(localNumber, remoteNumber))
        }
        if path.hasSuffix(".status"),
           local?.stringValue == "done" || remote?.stringValue == "done" {
            return .string("done")
        }
        return local
    }

    // MARK: Point d'entrée

    /// `mergeOfflineState(base, local, remote)` — `src/core/offlineMerge.ts:28`.
    public static func mergeOfflineState(
        base: JSONValue?,
        local: JSONValue,
        remote: JSONValue?
    ) -> JSONValue {
        guard let remote else { return local }
        guard let base else { return local }
        let localUser = local["userId"]?.stringValue
        let baseUser = base["userId"]?.stringValue
        let remoteUser = remote["userId"]?.stringValue
        guard baseUser == localUser, remoteUser == localUser else { return local }
        // Réinitialisation explicite : l'utilisateur a remis sa progression à zéro.
        if base["onboardingDone"]?.boolValue == true,
           local["onboardingDone"]?.boolValue != true {
            return local
        }
        guard var merged = merge(base: base, local: local, remote: remote, path: "") else {
            return local
        }
        merged["userId"] = local["userId"]
        merged["updatedAt"] = .string(DateKeys.maxISO([
            local["updatedAt"]?.stringValue.flatMap(DateKeys.parseISO),
            remote["updatedAt"]?.stringValue.flatMap(DateKeys.parseISO)
        ]))
        return merged
    }
}
