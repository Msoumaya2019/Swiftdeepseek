// JSONValue.swift
// Représentation d'une valeur JSON arbitraire.
//
// Pourquoi ce type existe : `user_state.data` est un document JSON produit par
// l'application React Native. Un client Swift qui le décoderait dans des structs
// strictes perdrait silencieusement :
//   - les clés qu'il ne connaît pas (ajoutées plus tard côté React Native),
//   - la distinction entre une clé absente et une clé valant `null`.
// La fusion à trois voies de React Native (`src/core/offlineMerge.ts`) opère sur
// du JSON générique. Pour rester compatible, on fait de même : ce type est la
// source de vérité, les structs typés n'en sont qu'une vue de lecture.

import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Valeur JSON non reconnue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Accès typé

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let dictionary) = self else { return nil }
            return dictionary[key]
        }
        set {
            guard case .object(var dictionary) = self else { return }
            dictionary[key] = newValue
            self = .object(dictionary)
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Représentation canonique, utilisée pour comparer deux valeurs comme le fait
    /// `JSON.stringify(a) === JSON.stringify(b)` côté JavaScript.
    var canonical: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            // Évite « 1.0 » là où JavaScript écrit « 1 ».
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .string(let value):
            return Self.escape(value)
        case .array(let values):
            return "[" + values.map(\.canonical).joined(separator: ",") + "]"
        case .object(let dictionary):
            let pairs = dictionary.keys.sorted().map { key in
                Self.escape(key) + ":" + dictionary[key]!.canonical
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    private static func escape(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - Conversion depuis les types Swift natifs

public extension JSONValue {
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull: return .null
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as String: return .string(value)
        case let value as [Any]: return .array(value.map(JSONValue.from))
        case let value as [String: Any]:
            return .object(value.mapValues(JSONValue.from))
        default: return .null
        }
    }

    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let values): return values.map(\.anyValue)
        case .object(let dictionary): return dictionary.mapValues(\.anyValue)
        }
    }
}
