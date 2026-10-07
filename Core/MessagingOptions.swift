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

    /// La garde du bouton « Proposer cet objectif » — `SocialScreens.tsx:177` :
    /// `!Number.isInteger(Number(targetSessions)) || Number(targetSessions) < 1
    /// || Number(targetSessions) > 14`.
    ///
    /// `Number("")` vaut **0**, et `Number(" ")` aussi — un champ vide ou
    /// d'espaces n'est donc pas « non numérique », il est **hors bornes** : le
    /// bouton reste éteint, mais pour la seconde raison. Le porter avec
    /// `Int(...)` seul donnerait la même décision sur ces deux entrées ; c'est
    /// sur `"1e2"` que les deux diffèrent — `Number` rend **100** (accepté,
    /// puisque ≤ 14 est faux… donc refusé), `Int("1e2")` rend `nil` (refusé
    /// aussi). Les deux refusent, mais **pas par la même branche**, et c'est
    /// exactement ce que `Tests/MessagingTests` épingle.
    ///
    /// Le second rôle : rendre le **nombre** que l'écran enverra. Une garde qui
    /// valide sans rendre la valeur oblige l'appelant à la reconvertir, et les
    /// deux conversions peuvent diverger. Ici, une seule fonction décide **et**
    /// rend — la vue ne reconvertit rien.
    public static func sessionCount(_ text: String) -> Int? {
        guard let value = number(text) else { return nil }
        guard value.rounded() == value else { return nil }
        let count = Int(value)
        guard count >= 1, count <= 14 else { return nil }
        return count
    }

    /// La garde du bouton « Proposer un rendez-vous » — `SocialScreens.tsx:186-188`.
    /// L'original teste une **expression régulière** `^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})$`,
    /// puis construit `new Date("…T…:00")`, puis refuse si la date est
    /// **invalide** (`NaN`) ou **passée** (`<= new Date()`).
    ///
    /// Les trois refus sont distincts et le message d'erreur est **le même**
    /// pour les trois : c'est une décision de l'écran, et elle est recopiée ici
    /// pour que le refus ne dépende pas de la vue.
    ///
    /// **LE 31 FÉVRIER EST ACCEPTÉ, ET C'EST LA RÉFÉRENCE QUI LE VEUT.**
    /// `new Date("2026-02-31T10:00:00")` **roule** au 3 mars en JavaScript :
    /// mesuré, `2026-03-03T09:00:00.000Z`. L'ISO n'est rejeté que s'il est
    /// *illisible* (`2026-02-3asdf` rend `Invalid Date`), pas s'il désigne un
    /// jour qui n'existe pas. Le portage fait donc rouler de même — une garde
    /// d'aller-retour qui refuserait le 31 février **divergerait** de
    /// l'original, et enverrait un écran qui refuse une saisie que l'application
    /// React Native accepte. C'est une histoire de mesure : une première sonde
    /// avait conclu « invalide », et c'était la sonde qui était cassée (un `$`
    /// mangé par le shell), pas la référence. L'oracle le mesure maintenant, et
    /// le raconte dans `SWIFT_MIGRATION.md` §9.37.
    public static func appointmentISO(_ text: String, now: Date) -> String? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        let clock = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard day.count == 3, clock.count == 2 else { return nil }
        guard day[0].count == 4, day[1].count == 2, day[2].count == 2 else { return nil }
        guard clock[0].count == 2, clock[1].count == 2 else { return nil }
        guard day.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        guard clock.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        // La garde de forme est passée : on peut maintenant lire des nombres.
        guard let year = Int(day[0]), let month = Int(day[1]), let date = Int(day[2]) else { return nil }
        guard let hour = Int(clock[0]), let minute = Int(clock[1]) else { return nil }
        guard (1...12).contains(month), (1...31).contains(date) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = date
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let when = calendar.date(from: components) else { return nil }
        // Pas de garde d'aller-retour : le calendrier **roule** le 31 février,
        // comme `new Date(...)`. Refuser ici serait la divergence.
        guard when > now else { return nil }
        return DateKeys.iso(when)
    }

    /// Le prédicat de lecture d'un message — `SocialScreens.tsx:198` :
    /// `m.created_at <= otherReadAt`, où la comparaison porte sur des **chaînes
    /// ISO**. L'original écrit `<=` (et non `<`) : un message écrit à la
    /// milliseconde exacte de la marque de lecture est **lu**.
    ///
    /// C'est le **miroir** de `isUnread` (`>`) et non sa négation à l'identique :
    /// `isUnread` répond sur `createdAt > lastReadAt`, celle-ci sur
    /// `createdAt <= otherReadAt`. Avec la même paire, `isRead(a, b) == !isUnread(a, b)`
    /// — mais l'égalité n'est **pas** écrite ici, elle est vérifiée par un test,
    /// parce que deux négations qui se répondent sont exactement le genre
    /// d'accord qu'une refonte casse en silence.
    public static func isRead(_ createdAt: String, at otherReadAt: String?) -> Bool {
        guard let otherReadAt else { return false }
        return createdAt <= otherReadAt
    }

    /// `Number(text)` — la conversion de JavaScript, et **non** `Int(text)`.
    ///
    /// Trois écarts, tous mesurés dans `_banc/oracle-messaging.mjs` :
    ///   · `Number("")` et `Number("  ")` valent **0**, `Int("")` vaut `nil` ;
    ///   · `Number("1e2")` vaut **100**, `Int("1e2")` vaut `nil` ;
    ///   · `Number("0x10")` vaut **16**, `Int("0x10")` vaut `nil`.
    ///
    /// Les deux premiers changent les **décisions** de l'écran (voir
    /// `sessionCount`). Le troisième ne peut pas être saisi : le champ porte
    /// `keyboardType="number-pad"`, qui n'offre ni `x` ni `e`.
    ///
    /// `Number("Infinity")` rend `Infinity` et non un entier : la valeur est
    /// écartée par `Int(value)`, qui rend `nil` sur l'infini — la garde de
    /// `sessionCount` le refuse avant.
    public static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed)
    }

    // MARK: Cercles privés

    /// Le nom d'un cercle est-il acceptable ?
    ///
    /// L'original désactive le bouton sur `groupName.trim().length < 2`
    /// (`SocialScreens.tsx:196`) — **deux caractères une fois détouré**, et le
    /// détourage est celui de JavaScript (`String.prototype.trim`), qui retire
    /// les blancs Unicode, pas seulement l'espace ASCII.
    ///
    /// C'est la seule condition qui garde la création : le nom part ensuite tel
    /// quel à `create_friend_group` (`p_name`), sans re-détourage côté Swift.
    /// La règle rend donc le nom **détouré**, et l'appelant envoie ce qu'elle
    /// rend — sinon l'écran validerait « a b » et enverrait «  a b  », et les
    /// deux applications ne nommeraient pas le même cercle de la même façon.
    ///
    /// Ce n'est PAS une validation d'unicité ni une longueur maximale : la
    /// fonction Postgres ne les impose pas, et en ajouter ici ferait refuser à
    /// Swift ce que l'application actuelle accepte.
    public static func circleNameIsAcceptable(_ text: String) -> Bool {
        trimmedCircleName(text).count >= 2
    }

    /// Le nom détouré, tel qu'il sera envoyé. `Character` compte des
    /// **graphèmes**, comme `String.length` de JavaScript compte des unités
    /// UTF-16 : deux emoji — un seul « caractère » chacun — passent la borne.
    public static func trimmedCircleName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ce rôle peut-il inviter, nommer un modérateur ou retirer un membre ?
    ///
    /// L'original l'écrit deux fois : `['owner','moderator'].includes(m.role)`
    /// (`SocialScreens.tsx:203` et `:204`). Deux copies d'une même liste, dans
    /// le même écran — le portage en fait **une** fonction, pour qu'une
    /// divergence soit impossible.
    ///
    /// `member` n'y est pas, et `nil` non plus : un rôle inconnu n'administre
    /// rien. C'est le sens de `includes` sur une liste fermée.
    public static func managesMembers(_ role: String?) -> Bool {
        guard let role else { return false }
        return role == "owner" || role == "moderator"
    }

    /// Cette appartenance attend-elle une réponse de **moi** ?
    ///
    /// `m.user_id === myId && !m.accepted_at` — l'original, deux fois aussi
    /// (`:202` et `:203`). L'ordre des deux tests n'importe pas, mais le second
    /// est bien sur `accepted_at` **nul**, non sur sa valeur.
    public static func awaitsMyAnswer(_ member: GroupMember, myID: String) -> Bool {
        member.userId == myID && member.acceptedAt == nil
    }
}
