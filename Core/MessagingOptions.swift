import Foundation

/// Les règles de la **messagerie** — `src/services/social.ts:130-190`.
///
/// Pourquoi dans `Core/` et non dans `Features/` : ce sont des décisions — ce
/// qu'on garde, ce qu'on masque, comment on compte, ce qu'on affiche quand le
/// message est supprimé. Un écran ne décide de rien : il rend ce que ces
/// fonctions rendent. Même partage que `SurahListOptions` et `Program`.
///
/// **Ce que ce fichier ne fait pas** : il ne parle pas au réseau. Les appels
/// réseau vivent dans `SocialService`, l'état dans le view model. Ici, il n'y a
/// que les règles, donc il n'y a que des tests — pas de faux serveur.
public enum MessagingOptions {

    /// Le nombre de messages ramenés d'un coup — `social.ts:131`, `.limit(50)`.
    public static let pageSize = 50

    /// Le nombre de conversations résumées — `social.ts:167`, `.limit(300)`.
    public static let summaryLimit = 300

    /// La borne du corps d'un partage de récitation — `social.ts:159`,
    /// `.slice(0, 2000)`. **UTF-16**, comme partout dans ce projet : la
    /// troncature de JavaScript compte les unités, pas les graphèmes.
    public static let sharedDescriptionLimit = 2000

    /// Ce qui s'affiche à la place du corps d'un message supprimé —
    /// `social.ts:173`, `row.deleted_at ? 'Message supprimé' : row.body`.
    public static let deletedPlaceholder = "Message supprimé"

    /// Ce qui s'affiche quand une conversation n'a **aucun** message mais un
    /// décompte non lu — `social.ts:180`.
    public static let newMessagePlaceholder = "Nouveau message"

    /// Les quatre sortes de message — `ChatMessage['kind']`.
    public enum Kind: String, CaseIterable, Sendable {
        case text
        case encouragement
        case progress
        case recitation

        /// Un message de récitation est le seul qui porte une pièce jointe.
        public var carriesRecitation: Bool { self == .recitation }
    }

    /// Le type de pièce jointe attachée à un message de récitation —
    /// `ChatMessage['recitation']`.
    public struct Recitation: Equatable, Sendable {
        public let id: String
        public let startVerseID: Int
        public let endVerseID: Int
        public let durationMS: Int
        public let storagePath: String

        public init(id: String, startVerseID: Int, endVerseID: Int, durationMS: Int, storagePath: String) {
            self.id = id
            self.startVerseID = startVerseID
            self.endVerseID = endVerseID
            self.durationMS = durationMS
            self.storagePath = storagePath
        }

        /// Le nombre de versets de la récitation, bornes **incluses**.
        public var verseCount: Int { max(0, endVerseID - startVerseID + 1) }
    }

    /// Une conversation : l'un ou l'autre, jamais les deux — `room: {linkId?,
    /// groupId?}`. L'original choisit par `room.linkId ? … : …`, donc un `linkId`
    /// **vide** bascule sur le groupe, exactement comme `undefined`.
    public enum Room: Equatable, Sendable {
        case link(String)
        case group(String)

        /// Le filtre de colonne employé par l'original — `social.ts:133`.
        public var column: String {
            switch self {
            case .link: return "link_id"
            case .group: return "group_id"
            }
        }

        public var value: String {
            switch self {
            case .link(let id), .group(let id): return id
            }
        }
    }

    /// Le résumé d'une conversation — `conversationSummaries`, `social.ts:166`.
    public struct Summary: Equatable, Sendable {
        public var body: String
        public var createdAt: String
        public var unread: Int

        public init(body: String, createdAt: String, unread: Int) {
            self.body = body
            self.createdAt = createdAt
            self.unread = unread
        }
    }

    /// Construit le fragment d'URL qui filtre une pièce — `social.ts:133`.
    ///
    /// L'original écrit `room.linkId ? … : …` : un `linkId` **vide** prend la
    /// branche du groupe. La décision se compare sur `Bool`, pas sur la valeur —
    /// deux vocabulaires, une seule décision.
    public static func filter(room: Room) -> (column: String, value: String) {
        (room.column, room.value)
    }

    /// Le corps envoyé, **détouré** — `sendMessage`, `social.ts:158`, `body.trim()`.
    ///
    /// `trim` de JavaScript retire l'espace blanc des deux bouts, y compris
    /// `\u{FEFF}` et les espaces insécables. `CharacterSet.whitespacesAndNewlines`
    /// ne retire **pas** `\u{FEFF}` : c'est une divergence connue, et mesurée.
    public static func outgoing(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La description d'un partage, tronquée en **unités UTF-16** —
    /// `social.ts:159`, `.slice(0, 2000)`.
    ///
    /// Un `String.count` compte les **graphèmes** : sur des emoji, les deux
    /// diffèrent. On prend donc les 2 000 premières unités UTF-16 et on
    /// reconstruit, en tolérant une paire de substitution coupée — le `String`
    /// garde alors le caractère de remplacement, comme `slice` garde le
    /// demi-`surrogate`.
    public static func sharedDescription(_ description: String) -> String {
        let units = Array(description.utf16)
        guard units.count > sharedDescriptionLimit else { return description }
        return String(decoding: units.prefix(sharedDescriptionLimit), as: UTF16.self)
    }

    /// Le corps affiché dans le résumé d'une conversation — `social.ts:173`.
    public static func summaryBody(body: String, isDeleted: Bool) -> String {
        isDeleted ? deletedPlaceholder : body
    }

    /// Les messages **visibles** : ceux qu'on n'a pas masqués pour soi —
    /// `social.ts:135-138`. L'original filtre sur un `Set` d'identifiants.
    public static func visible<T>(_ messages: [T], id: (T) -> String, hidden: Set<String>) -> [T] {
        messages.filter { !hidden.contains(id($0)) }
    }

    /// Les identifiants des récitations à charger — `social.ts:139`.
    ///
    /// Deux conditions **cumulées** : le message est de sorte `recitation` **et**
    /// porte un identifiant non nul. Un message `text` qui porterait par accident
    /// un `recitation_id` ne déclenche **pas** de chargement — l'original teste
    /// les deux.
    public static func recitationIDs(_ messages: [(kind: Kind, recitationID: String?)]) -> [String] {
        messages
            .filter { $0.kind.carriesRecitation && $0.recitationID != nil }
            .compactMap { $0.recitationID }
    }

    /// L'horodatage d'une marque de lecture — `markConversationRead`,
    /// `social.ts:148-150`. C'est `new Date().toISOString()`, donc en
    /// **millisecondes entières** : `DateKeys.iso` porte déjà la conversion.
    public static func readStamp(now: Date) -> String {
        DateKeys.iso(now)
    }

    /// La comparaison qui décide si un message est **non lu** —
    /// `social.ts:176-177` : `created_at > last_read_at`, et en l'absence de
    /// marque de lecture, **tout** est non lu.
    ///
    /// Les deux horodatages sont des chaînes ISO de même longueur : la
    /// comparaison **lexicographique** suffit et c'est celle de Postgres ici.
    /// Comparer en `Date` serait plus « propre » mais introduirait une
    /// divergence sur les formats non canoniques — on garde la comparaison de
    /// chaînes, comme la requête.
    public static func isUnread(createdAt: String, lastReadAt: String?) -> Bool {
        guard let lastReadAt else { return true }
        return createdAt > lastReadAt
    }

    /// Le résumé d'une conversation, à partir de ses messages — `social.ts:171-183`.
    ///
    /// **Trois décisions, et l'ordre compte :**
    /// 1. le premier message parcouru **fixe** le résumé (`??=`), donc c'est le
    ///    plus **récent** — la liste arrive dans l'ordre décroissant ;
    /// 2. un message supprimé affiche le libellé, mais **conserve** son
    ///    horodatage : c'est la date du message qui compte, pas celle du masquage ;
    /// 3. un décompte non nul **crée** le résumé s'il n'existait pas, avec
    ///    `new Date()` comme horodatage — un horodatage que rien ne peut mesurer
    ///    hors ligne, donc **injecté**.
    ///
    /// `unread` du parcours initial reste à **zéro** : le compte vient d'une
    /// requête séparée, jamais du parcours. L'original pose `unread: 0` puis
    /// l'écrase ; le porter autrement donnerait le même chiffre par accident.
    public static func summaries(
        messages: [(linkID: String, body: String, createdAt: String, isDeleted: Bool)],
        unreadCounts: [String: Int],
        now: Date
    ) -> [String: Summary] {
        var result: [String: Summary] = [:]
        for row in messages where result[row.linkID] == nil {
            result[row.linkID] = Summary(
                body: summaryBody(body: row.body, isDeleted: row.isDeleted),
                createdAt: row.createdAt,
                unread: 0
            )
        }
        for (linkID, count) in unreadCounts where count > 0 {
            if result[linkID] == nil {
                result[linkID] = Summary(body: newMessagePlaceholder, createdAt: DateKeys.iso(now), unread: 0)
            }
            result[linkID]?.unread = count
        }
        return result
    }

    /// Le libellé d'un décompte non lu, ou `nil` quand il n'y a rien à montrer —
    /// l'écran ne doit **pas** afficher « 0 ». La borne de 99 est celle des
    /// pastilles d'interface, elle est ici pour être mesurée une fois.
    public static func unreadBadge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }

    /// Les quatre sortes, avec leur libellé français — l'écran les propose.
    /// `allCases` n'est **pas** employé pour l'affichage : une liste offerte se
    /// fige, comme pour les éditions du Coran.
    public static func kindLabel(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Message"
        case .encouragement: return "Encouragement"
        case .progress: return "Progrès"
        case .recitation: return "Récitation"
        }
    }

    /// La durée d'une pièce jointe de récitation, en `m:ss` —
    /// comme `formatDuration` de l'original.
    public static func durationText(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "0:00" }
        let total = milliseconds / 1000
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + (seconds < 10 ? "0\(seconds)" : "\(seconds)")
    }
}
