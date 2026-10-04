// MarginAnnotations.swift
// Repères de progression de séance dans la marge d'une page du Moushaf.
//
// Correspondance : `src/core/marginAnnotations.ts` et `MushafPage.tsx:53` de
// l'application React Native.
//
// À QUOI ÇA SERT
//   Quand une séance est ouverte — apprentissage ou révision — l'original
//   affiche, dans la marge gauche de la page, un rail vertical et une pastille
//   par LIGNE de la page, portant le ou les numéros de verset de cette ligne.
//   Une pastille pleine marque un verset déjà validé, une pastille creuse un
//   verset qui reste à faire. C'est le seul repère de progression qui soit
//   posé sur la page elle-même.
//
// POURQUOI UN FICHIER `Core` ET PAS UNE VUE
//   Le regroupement des versets par ligne et la position du rail sont de la
//   géométrie pure, sans couleur ni police. Ils sont ici pour être éprouvables
//   sans rien dessiner : la vue ne fait que tracer ce que ce fichier calcule.
//   Même partage que `VerseBounds` / `VerseHighlightView`.
//
// LES DEUX PIÈGES DU REGROUPEMENT, ET ILS SONT SILENCIEUX
//   1. **Une seule région par verset.** Un verset à cheval sur deux lignes a
//      deux régions ; c'est la PREMIÈRE dans l'ordre (ligne, puis y) qui
//      décide de la ligne du groupe. Prendre la seconde place le numéro une
//      ligne trop bas.
//   2. **`bottom` se calcule sur TOUTES les régions**, pas seulement sur
//      celles retenues par le groupe. Un verset à cheval sur deux lignes
//      étend donc le rail jusqu'au bas de sa seconde ligne. Le lire sur le
//      seul groupe retenu raccourcit le rail — sans erreur, juste un rail
//      trop court.
//
// CE QUE CE FICHIER NE FAIT PAS
//   Il ne dessine rien et ne connaît aucune couleur. Les couleurs sont fixées
//   par la vue (`VerseMarginStyle`), comme celles d'une pastille de numéro le
//   sont par `VerseMedallionStyle`.

import CoreGraphics
import Foundation

public enum MarginAnnotations {

    // MARK: Une région

    /// Une ligne du fichier de rectangles, ramenée en fractions de page.
    ///
    /// `x`, `y` et `height` sont des fractions de la page — `x` de sa largeur,
    /// `y` et `height` de sa hauteur — exactement comme l'original
    /// (`row[3] / sourceWidth`, `row[5] / sourceHeight`, …). C'est ce qui rend
    /// la géométrie indépendante de la taille d'affichage.
    public struct Region: Equatable, Sendable {
        public let id: Int
        public let ayah: Int
        public let line: Int
        public let x: CGFloat
        public let y: CGFloat
        public let height: CGFloat

        public init(id: Int, ayah: Int, line: Int, x: CGFloat, y: CGFloat, height: CGFloat) {
            self.id = id
            self.ayah = ayah
            self.line = line
            self.x = x
            self.y = y
            self.height = height
        }
    }

    /// Un verset dans une pastille.
    public struct Item: Equatable, Sendable {
        public let id: Int
        public let ayah: Int
        public let done: Bool

        public init(id: Int, ayah: Int, done: Bool) {
            self.id = id
            self.ayah = ayah
            self.done = done
        }
    }

    /// Une pastille : les versets d'UNE ligne de la page.
    public struct Group: Equatable, Sendable {
        /// Haut du groupe, en fraction de la hauteur de page.
        public let y: CGFloat
        /// Hauteur du groupe, en fraction de la hauteur de page.
        public let height: CGFloat
        /// Les versets de la ligne, **triés par identifiant**.
        public let items: [Item]
        /// Bas de la sélection, en fraction de la hauteur de page. Calculé sur
        /// **toutes** les régions des versets du groupe, pas seulement sur la
        /// ligne retenue — voir l'en-tête.
        public let bottom: CGFloat

        public init(y: CGFloat, height: CGFloat, items: [Item], bottom: CGFloat) {
            self.y = y
            self.height = height
            self.items = items
            self.bottom = bottom
        }
    }

    // MARK: Regroupement

    /// Les pastilles d'une page, dans l'ordre de haut en bas.
    ///
    /// Traduction directe de `marginAnnotations` (`src/core/marginAnnotations.ts`) :
    ///   1. ne garder, pour chaque verset, que la **première** région dans
    ///      l'ordre (ligne, puis `y`) — comparaisons **strictes**, donc à
    ///      égalité c'est la région rencontrée en premier qui reste, comme la
    ///      `Map` de l'original ;
    ///   2. regrouper par ligne, dans l'ordre de première apparition ;
    ///   3. trier les groupes par le `y` de leur **première** région — donc
    ///      avant le tri interne par identifiant, comme l'original, qui trie
    ///      `a[0].y` puis `group.sort(...)` à l'intérieur du `map`.
    ///
    /// Le tri des groupes est rendu **stable** (égalité de `y` départagée par
    /// l'ordre d'apparition) : `Array.sorted` ne garantit pas la stabilité,
    /// `Array.prototype.sort` la garantit depuis ES2019. Sans ce départage, un
    /// document où deux lignes partagent le même `y` pourrait s'ordonner
    /// autrement qu'en React Native.
    ///
    /// Seuls les versets dont l'identifiant est dans `start...end` sont
    /// retenus. `through` est le dernier identifiant validé : un verset est
    /// marqué fait si `id <= through`.
    public static func groups(
        _ regions: [Region],
        start: Int,
        end: Int,
        through: Int = 0
    ) -> [Group] {
        // 1. Une région par verset, la première dans l'ordre (ligne, y).
        var first: [Int: Region] = [:]
        var insertionOrder: [Int] = []
        for region in regions {
            guard region.id >= start, region.id <= end else { continue }
            guard let previous = first[region.id] else {
                first[region.id] = region
                insertionOrder.append(region.id)
                continue
            }
            let better = region.line < previous.line
                || (region.line == previous.line && region.y < previous.y)
            if better { first[region.id] = region }
        }

        // 2. Regroupement par ligne, dans l'ordre de première apparition.
        var byLine: [Int: [Region]] = [:]
        var lineOrder: [Int] = []
        for id in insertionOrder {
            guard let region = first[id] else { continue }
            if byLine[region.line] == nil { lineOrder.append(region.line) }
            byLine[region.line, default: []].append(region)
        }

        // 3. Tri par le `y` de la première région, à égalité l'ordre d'apparition.
        let sortedLines = lineOrder.enumerated().sorted { lhs, rhs in
            let left = byLine[lhs.element]?.first?.y ?? 0
            let right = byLine[rhs.element]?.first?.y ?? 0
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)

        return sortedLines.map { line in
            let group = (byLine[line] ?? []).sorted { $0.id < $1.id }
            let ids = Set(group.map(\.id))
            // `bottom` sur TOUTES les régions, non filtrées : c'est ce qui
            // étend le rail jusqu'au bas d'un verset à cheval sur deux lignes.
            let bottoms = regions.filter { ids.contains($0.id) }.map { $0.y + $0.height }
            return Group(
                y: group.map(\.y).min() ?? 0,
                height: group.map(\.height).max() ?? 0,
                items: group.map { Item(id: $0.id, ayah: $0.ayah, done: $0.id <= through) },
                bottom: bottoms.max() ?? 0
            )
        }
    }

    // MARK: Lecture d'une page

    /// Les régions d'une page, en fractions de page.
    ///
    /// Reproduit les `entries` de `MushafPage.tsx:53` :
    ///   `rows.flatMap(row => { const id = verseId(row[0], row[1]);
    ///    return id === null ? [] : [{…}] })`.
    ///
    /// Une ligne dont le couple (sourate, verset) ne désigne aucun verset est
    /// **écartée** — c'est ce que fait `verseId` en rendant `null`, et
    /// `Quran.verseID` a le même contrat.
    ///
    /// Les fractions se rapportent à la taille de la page de la source :
    /// `VerseBounds.imageSize(for:page:)`, et non une constante. Pour le Coran
    /// 1441 cette taille est lue page par page ; s'y tromper décale toutes les
    /// pastilles sans autre symptôme.
    public static func regions(page: Int, source: VerseBounds.Source) -> [Region] {
        let imageSize = VerseBounds.imageSize(for: source, page: page)
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }

        return VerseBounds.rows(page: page, source: source).compactMap { row in
            guard let id = Quran.verseID(surah: row.surah, ayah: row.ayahStart) else { return nil }
            return Region(
                id: id,
                ayah: row.ayahStart,
                line: row.line,
                x: row.rect.minX / imageSize.width,
                y: row.rect.minY / imageSize.height,
                height: row.rect.height / imageSize.height
            )
        }
    }

    // MARK: Géométrie

    /// Diamètre minimal d'une pastille — `Math.max(8, …)`.
    public static let minimumDiameter: CGFloat = 8
    /// Diamètre maximal d'une pastille — `Math.min(24, …)`.
    public static let maximumDiameter: CGFloat = 24

    /// Hauteur du texte d'une pastille, pour une taille de police et une
    /// largeur de contenu données.
    ///
    /// Injectée parce que la mesure demande UIKit, que `Core` ne connaît pas.
    /// Le défaut rend **zéro**, donc une pastille de la hauteur de son
    /// diamètre : c'est le cas de la très grande majorité des pastilles, et
    /// cela rend la géométrie éprouvable sans police.
    public typealias TextHeight = (_ label: String, _ fontSize: CGFloat, _ maxWidth: CGFloat) -> CGFloat

    /// Une pastille à dessiner, en coordonnées de la vue.
    public struct Marker: Equatable, Sendable {
        /// Boîte de la pastille. Sa hauteur vaut au moins son diamètre, et
        /// grandit vers le BAS quand le texte passe à la ligne — `minHeight`
        /// dans l'original : le haut ne bouge pas, le bas descend.
        public let rect: CGRect
        public let cornerRadius: CGFloat
        public let items: [Item]
        /// Vrai quand **tous** les versets de la pastille sont validés
        /// (`group.items.every(item => item.done)`). La pastille est alors
        /// pleine ; un seul verset restant la laisse creuse.
        public let done: Bool
        public let fontSize: CGFloat
        public let label: String

        public init(
            rect: CGRect,
            cornerRadius: CGFloat,
            items: [Item],
            done: Bool,
            fontSize: CGFloat,
            label: String
        ) {
            self.rect = rect
            self.cornerRadius = cornerRadius
            self.items = items
            self.done = done
            self.fontSize = fontSize
            self.label = label
        }
    }

    /// Le rail et les pastilles d'une page, en coordonnées de la vue.
    public struct Layout: Equatable, Sendable {
        /// Le rail vertical. Sa largeur est de 1 point ; sa hauteur va du haut
        /// du premier groupe au bas du dernier.
        public let rail: CGRect
        public let markers: [Marker]

        public init(rail: CGRect, markers: [Marker]) {
            self.rail = rail
            self.markers = markers
        }

        public static let empty = Layout(rail: .zero, markers: [])

        /// Rien à dessiner : aucun verset de la séance sur cette page.
        public var isEmpty: Bool { markers.isEmpty }
    }

    /// Calcule le rail et les pastilles pour une page.
    ///
    /// `bounds` est la zone de la vue ENTIÈRE ; `padding` est la marge
    /// intérieure de l'original (`MushafPage.tsx:44` : `zipped ? 0 : 2`), donc
    /// 0 pour le Coran 1441 et 2 pour le Coran de Médine. La boîte de page est
    /// celle où l'image est RÉELLEMENT dessinée (`VerseBounds.pageBox`), comme
    /// pour les mises en évidence et les pastilles de numéro.
    ///
    /// LA SEULE DIFFÉRENCE DE FORME AVEC L'ORIGINAL, ET ELLE EST VÉRIFIÉE
    ///   L'original calcule `edge` dans le repère de sa `Pressable`, qui
    ///   commence à `marginGutter` dans la vue, et ajoute ensuite `marginGutter`
    ///   pour obtenir le diamètre :
    ///     `edge = min(x) * (width - padding*2) + padding`
    ///     `diameter = min(24, max(8, edge + marginGutter - 4))`
    ///   Ici la boîte de page est déjà mesurée dans la vue entière, donc
    ///   `marginGutter` est **contenu** dans `pageBox.minX` et disparaît :
    ///     `edge = pageBox.minX + min(x) * pageBox.width`
    ///     `diameter = min(24, max(8, edge - 4))`
    ///   `_banc/oracle-margin.mjs` fait tourner le VRAI `marginAnnotations.ts`
    ///   sur les vrais fichiers de rectangles et vérifie que les deux
    ///   formulations donnent les mêmes nombres, à trois valeurs de
    ///   `marginGutter` près (dont deux qui donnent des diamètres différents).
    public static func layout(
        regions: [Region],
        start: Int,
        end: Int,
        through: Int = 0,
        in bounds: CGRect,
        imageSize: CGSize,
        padding: CGFloat,
        textHeight: TextHeight = { _, _, _ in 0 }
    ) -> Layout {
        guard !regions.isEmpty,
              let leftmost = regions.map(\.x).min() else { return .empty }

        let box = VerseBounds.pageBox(
            in: bounds.insetBy(dx: padding, dy: padding),
            imageSize: imageSize
        )
        guard box.width > 0, box.height > 0 else { return .empty }

        let pageGroups = groups(regions, start: start, end: end, through: through)
        guard let firstGroup = pageGroups.first, let lastGroup = pageGroups.last else { return .empty }

        let edge = box.minX + leftmost * box.width
        let diameter = min(maximumDiameter, max(minimumDiameter, edge - 4))
        let left = edge - diameter - 2

        let rail = CGRect(
            x: left + diameter / 2,
            y: box.minY + firstGroup.y * box.height,
            width: 1,
            height: (lastGroup.bottom - firstGroup.y) * box.height
        )

        let markers = pageGroups.map { group -> Marker in
            let label = group.items.map { String($0.ayah) }.joined(separator: "·")
            let fontSize: CGFloat = group.items.count > 1 ? 8 : min(11, diameter * 0.55)
            // La bordure est d'un point, et dans l'original elle est DANS la
            // boîte : le texte se dispose sur `diameter - 2`.
            let measured = textHeight(label, fontSize, max(0, diameter - 2))
            let height = max(diameter, measured + 2)
            return Marker(
                rect: CGRect(
                    x: left,
                    y: box.minY + (group.y + group.height * 0.35) * box.height - diameter / 2,
                    width: diameter,
                    height: height
                ),
                cornerRadius: diameter / 2,
                items: group.items,
                done: group.items.allSatisfy(\.done),
                fontSize: fontSize,
                label: label
            )
        }

        return Layout(rail: rail, markers: markers)
    }

    // MARK: La séance

    /// La séance à représenter, dérivée de la demande d'ouverture du lecteur.
    public struct Session: Equatable, Sendable {
        /// La plage de versets de la séance.
        public let range: VerseRange
        /// Dernier identifiant validé — `studyRecord.through`.
        public let through: Int

        public init(range: VerseRange, through: Int) {
            self.range = range
            self.through = through
        }
    }

    /// Dérive la séance à représenter, ou `nil` s'il n'y a pas lieu d'afficher
    /// de repères.
    ///
    /// Reproduit `App.tsx:477-481` :
    ///   `learning = !!reader.sessionId`
    ///   `reviewing = !!(reader.reviewTask || reader.revisionId || reader.consolidation)`
    ///   `focused = learning || reviewing`
    ///   `studyMode = learning ? 'learning' : 'revision'`
    ///   `studyId = reader.sessionId ?? reader.reviewTask?.id ?? reader.revisionId`
    ///   `studyRecord = studyId ? state.studyProgress[studyKey(studyMode, studyId)] : undefined`
    ///   `plannedRange = learning ? (state.sessions.find(s => s.id === reader.sessionId) ?? reader.range)
    ///                            : (studyRecord ?? reader.range)`
    ///   `studyThrough = studyRecord?.through ?? plannedRange.start - 1`
    ///
    /// TROIS POINTS OÙ LE PORTAGE DOIT ÊTRE EXACT
    ///   1. **En apprentissage, la séance enregistrée prime sur la plage
    ///      demandée.** Le lecteur peut être ouvert sur une plage rétrécie —
    ///      « Reprendre au verset N » (`ProgramView`) — alors que l'original
    ///      affiche la plage ENTIÈRE de la séance. Prendre la plage demandée
    ///      donnerait un rail qui s'arrête au milieu de la séance.
    ///   2. **La clé de suivi dépend du mode.** `Program.studyKey` construit
    ///      `"<mode>:<id>"` ; la fabriquer à la main une fois de travers rend
    ///      le suivi invisible.
    ///   3. **`through` retombe sur `start - 1`** quand aucun suivi n'existe :
    ///      aucun verset n'est alors marqué fait, ce qui est le bon défaut pour
    ///      une séance jamais ouverte.
    ///
    /// `revisionId` n'existe pas dans `ReaderRequest` : une révision est
    /// toujours ouverte avec une `reviewTask` (`ReviewDashboardView`), donc
    /// `reviewing` se réduit à `reviewTaskID != nil || isConsolidation`.
    public static func session(
        learningSessionID: String?,
        reviewTaskID: String?,
        isConsolidation: Bool,
        requestRange: VerseRange?,
        state: AppState
    ) -> Session? {
        let learning = learningSessionID != nil
        let reviewing = reviewTaskID != nil || isConsolidation
        guard learning || reviewing else { return nil }

        let mode: StudyMode = learning ? .learning : .revision
        // Deux temps, et non `studyID.flatMap { … }` : sur une valeur optionnelle
        // de type `String`, `flatMap` peut résoudre vers `Sequence.flatMap` et
        // rendre un `Character` au lieu du suivi — l'erreur ne dit pas son nom.
        // Voir `prouver-une-logique-swift-sans-compilateur`.
        var record: StudyProgress?
        if let studyID = learningSessionID ?? reviewTaskID {
            record = state.studyProgress?[Program.studyKey(mode, studyID)]
        }

        let planned: VerseRange?
        if learning, let id = learningSessionID {
            planned = state.sessions.first { $0.id == id }
                .map { VerseRange(start: $0.start, end: $0.end) } ?? requestRange
        } else {
            planned = record.map { VerseRange(start: $0.start, end: $0.end) } ?? requestRange
        }

        guard let range = planned else { return nil }
        return Session(range: range, through: record?.through ?? range.start - 1)
    }
}
