// TajweedVerseListView.swift
// L'édition « Lecture simplifiée » : les versets d'une page, en cartes.
//
// Correspondance : `MushafPage.tsx:34-43` — la branche
// `if(language==='fr'||mode==='tajweed')` — et l'enveloppe qui la fait défiler,
// `App.tsx:499`.
//
// POURQUOI CETTE ÉDITION N'EST PAS UNE PAGE
//   Le Coran de Médine et le Coran 1441 sont des IMAGES : une page, un
//   rectangle, et des rectangles de versets posés dessus. « Lecture
//   simplifiée », elle, n'a aucune image — elle rend le **texte** d'un verset,
//   découpé en fragments colorés par règle de Tajweed (`TajweedOptions`). C'est
//   pourquoi l'original la fait passer par la branche des cartes
//   (`MushafPage.tsx:34`) au lieu de la branche des images (`:44`), et pourquoi
//   elle ne peut pas vivre dans le `UIPageViewController` qui porte les pages :
//   `ReaderView` lui donne donc une **troisième forme de corps**.
//
// ELLE DÉFILE, ET C'EST UNE DÉCISION STRUCTURELLE
//   `App.tsx:499` enveloppe la liste dans un `ScrollView` dont le défilement
//   n'est activé que pour cette édition — `scrollEnabled={mushaf==='tajweed'}` —
//   et dont la hauteur est celle de la fenêtre de lecture, non celle d'une page
//   ajustée. Sans lui, une page de 286 versets (la plus longue du Moushaf)
//   serait coupée : c'est la classe de défaut du §9.28, un écran qui existe mais
//   dont on ne peut pas voir la fin.
//
// LE RAIL DE SÉANCE NE VIENT PAS DE `MarginAnnotations`
//   Sur une page, les pastilles se groupent par proximité dans la marge et le
//   rail couvre des **groupes** (`MarginAnnotations`, `VerseMarginView`). Ici il
//   n'y a pas de marge : `MushafPage.tsx:41` lit la position de chaque carte
//   (`plainPositions`, remplie par `onLayout`) et pose une pastille par verset
//   actif, alignée sur le rail. Une carte, une pastille — deux règles
//   différentes, deux types différents. Les positions viennent donc de la mise
//   en page elle-même (une `PreferenceKey`), comme dans l'original.
//
// CE QUI N'EST PAS PORTÉ, ET QUI EST DIT
//   - le geste de balayage pour changer de page : l'original l'emprunte au
//     `ScrollView` (`swipe.panHandlers`), et le porter ici entrerait en conflit
//     avec le défilement. Les deux boutons de page du lecteur restent ;
//   - le bandeau de séance (`studyBanner`) : il remplace l'en-tête dans
//     l'original, et le lecteur de ce portage montre la séance par le rail, comme
//     sur une page ;
//   - l'agrandissement (`textScale` reste à 1) : `ZoomableReader` n'est pas
//     porté, mais le facteur est un paramètre — la formule du modèle est
//     complète.

import SwiftUI
import UIKit

// MARK: - Les couleurs d'une carte

/// Les couleurs d'une carte de verset — `MushafPage.tsx:36`.
///
/// LES DEUX COULEURS DU VERSET DIFFICILE NE VIENNENT PAS DE LA PALETTE
///   L'original les écrit en clair, et elles ne suivent donc aucun thème. Ce ne
///   sont **pas** celles de la mise en évidence d'une page : un verset difficile
///   est rouge vif sur une page (`#E85B5B`, `VerseHighlightStyle.difficultRed`)
///   et rose pâle en carte (`#FCE8E8`). Les confondre ne produirait aucune
///   erreur — seulement une carte de la mauvaise couleur.
enum TajweedCardStyle {

    /// `backgroundColor: difficult ? '#FCE8E8' : …` — `MushafPage.tsx:36`.
    static let difficultBackgroundHex = "#FCE8E8"

    /// `borderColor: difficult ? '#D97878' : colors.green2` — `MushafPage.tsx:36`.
    static let difficultBorderHex = "#D97878"

    /// La couleur de fond d'une carte, dans l'ordre où l'original la décide.
    ///
    /// L'ordre est celui de `TajweedOptions.CardState.of` : `difficult` passe
    /// avant la sélection, qui passe avant la lecture. `.bookmarked` et
    /// `.playing` rendent aujourd'hui la **même** couleur (`colors.selected`) —
    /// c'est ce que dit l'original, et le type les garde distincts pour le jour
    /// où l'une des deux changera.
    static func background(_ state: TajweedOptions.CardState, palette: Palette) -> Color {
        switch state {
        case .difficult: return difficultBackground
        case .bookmarked, .playing: return palette.selected
        case .plain: return palette.paper
        }
    }

    /// `borderWidth: difficult ? 1 : 0` — les trois autres états n'ont **pas**
    /// de bordure, même si leur couleur de bordure est définie.
    static func borderWidth(_ state: TajweedOptions.CardState) -> CGFloat {
        state == .difficult ? 1 : 0
    }

    /// `borderColor: difficult ? '#D97878' : colors.green2`.
    static func borderColor(_ state: TajweedOptions.CardState, palette: Palette) -> Color {
        state == .difficult ? difficultBorder : palette.green2
    }

    /// `#FCE8E8`, résolu une fois.
    ///
    /// Le repli est le papier du thème : une carte **lisible** plutôt qu'une
    /// carte transparente. Sur cette chaîne la conversion réussit —
    /// `TajweedListTests` l'épingle — donc ce repli est une ceinture.
    static var difficultBackground: Color {
        Theme.color(hexString: difficultBackgroundHex) ?? Theme.white.paper
    }

    /// `#D97878`, résolu une fois. Même ceinture que ci-dessus.
    static var difficultBorder: Color {
        Theme.color(hexString: difficultBorderHex) ?? Theme.white.paper
    }

    // MARK: La hauteur de ligne

    /// La **hauteur de ligne** de l'original est ABSOLUE (`lineHeight: 25`),
    /// celle de SwiftUI est ADDITIVE (`lineSpacing`). Le pont est la hauteur de
    /// ligne de la police elle-même : la somme retombe donc sur la hauteur de
    /// l'original, au lieu d'une valeur choisie ici.
    ///
    /// `max(0, …)` parce que `lineSpacing` négatif est refusé : sur les largeurs
    /// où la formule s'applique, l'écart est toujours positif — `TajweedListTests`
    /// le mesure —, donc cette borne ne se déclenche pas non plus.
    static func lineSpacing(fontSize: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, lineHeight - UIFont.systemFont(ofSize: fontSize).lineHeight)
    }

    /// L'écart du texte arabe — `fontSize` et `lineHeight` viennent tous deux de
    /// `TajweedOptions`, à partir de la **largeur de la fenêtre de lecture** (et
    /// non de celle de la carte : c'est la largeur que l'original passe, et la
    /// formule en dépend).
    static func arabicLineSpacing(width: CGFloat, textScale: CGFloat) -> CGFloat {
        lineSpacing(
            fontSize: TajweedOptions.arabicFontSize(width: width, textScale: textScale),
            lineHeight: TajweedOptions.arabicLineHeight(width: width, textScale: textScale)
        )
    }
}

// MARK: - Le rail de séance

/// La géométrie du rail de séance de la **liste** — `MushafPage.tsx:41`.
///
/// Trois règles, et chacune est silencieuse :
///
///   1. le rail ne couvre que les versets **actifs** — dans la plage de la
///      séance — **dont la position est connue** : un verset de la plage qui
///      n'est pas sur cette page ne compte pas, et n'a donc pas de pastille ;
///   2. la barre part du **premier** actif et va jusqu'au **bas** du dernier ;
///   3. une pastille par actif, remplie jusqu'à `through` inclus.
///
/// Ce n'est PAS la règle de la marge d'une page : là-bas les pastilles se
/// groupent par proximité, et un verset à cheval sur deux lignes n'est retenu
/// qu'une fois. Ici il n'y a ni marge, ni lignes : une carte, une pastille.
enum TajweedSessionRail {

    /// `left: 10` — la barre passe par le **centre** des pastilles, qui sont
    /// larges de 20 et posées à `left: 0`.
    static let barX: CGFloat = 10
    static let barWidth: CGFloat = 1
    static let dotDiameter: CGFloat = 20

    /// `+ 10` sur le haut de la barre comme sur celui d'une pastille : les deux
    /// descendantes, et non une seule, sans quoi elles se décaleraient.
    static let topInset: CGFloat = 10

    /// Les versets actifs, dans l'ordre de la page, dont la position est connue.
    static func activeIDs(
        _ ids: [Int],
        session: MarginAnnotations.Session,
        positions: [Int: CGRect]
    ) -> [Int] {
        ids.filter {
            $0 >= session.range.start && $0 <= session.range.end && positions[$0] != nil
        }
    }

    /// La barre verticale, ou `nil` s'il n'y a rien à couvrir.
    ///
    /// La hauteur est `bas - haut - 10` : la barre commence 10 pt sous le haut du
    /// premier actif et finit 10 pt sous le bas du dernier, donc au **centre** de
    /// sa pastille. Pour un seul actif elle vaut `hauteur de la carte - 10`, ce
    /// qui reste positif — une carte fait au moins 20 pt.
    static func bar(active: [Int], positions: [Int: CGRect]) -> CGRect? {
        guard let premier = active.first, let dernier = active.last,
              let haut = positions[premier], let bas = positions[dernier] else { return nil }
        return CGRect(
            x: barX,
            y: haut.minY + topInset,
            width: barWidth,
            height: bas.maxY - haut.minY - topInset
        )
    }

    /// La pastille d'un verset actif, ou `nil` si sa position n'est pas connue.
    static func dot(_ id: Int, positions: [Int: CGRect]) -> CGRect? {
        guard let position = positions[id] else { return nil }
        return CGRect(
            x: 0,
            y: position.minY + topInset,
            width: dotDiameter,
            height: dotDiameter
        )
    }

    /// Vrai quand la pastille est **remplie** — `backgroundColor: id <= sessionThrough
    /// ? sessionColor : colors.paper`. La borne est inclusive : le dernier verset
    /// validé est rempli.
    static func isFilled(_ id: Int, through: Int) -> Bool {
        id <= through
    }
}

// MARK: - La position des cartes

/// La position de chaque carte, dans la boîte de la liste.
///
/// C'est le `plainPositions` de `MushafPage.tsx:23`, rempli par `onLayout` : la
/// position n'est pas déductible du texte, puisque la hauteur d'une carte dépend
/// du repli de ses lignes. La mesure est donc la seule source — et elle est prise
/// **dans la boîte de la liste**, pour que le rail et les cartes parlent du même
/// repère par construction, plutôt qu'en recopiant un décalage.
private struct CardBoundsKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, nouveau in nouveau }
    }
}

// MARK: - La liste

/// Les versets d'une page, en cartes défilantes.
struct TajweedVerseListView: View {

    /// La page du Coran de Médine dont on rend les versets.
    ///
    /// Pour cette édition, « page » garde son sens de pagination : l'original
    /// passe le même `page` à la liste et à l'en-tête, et
    /// `QuranSourceNavigation` range `.tajweed` avec les éditions paginées
    /// (`isZipSource` ne vaut que pour `coran_1441`).
    let page: Int

    /// La langue rendue. `App.tsx:499` passe toujours `"ar"` ; le mode français
    /// est porté parce que la branche existe dans l'original.
    let language: TajweedOptions.ReaderLanguage

    /// Le verset en cours de lecture, s'il y en a un.
    let playing: Int?

    /// Les versets marqués difficiles et ceux qui portent un signet.
    let difficulty: Set<Int>
    let bookmarks: Set<Int>

    /// La séance à représenter, ou `nil` pour une lecture libre.
    let session: MarginAnnotations.Session?

    /// Le facteur de taille du texte. `ZoomableReader` n'est pas porté : il vaut
    /// donc 1, mais il reste un paramètre, comme dans le modèle.
    var textScale: CGFloat = 1

    /// La palette active. Elle est **passée** plutôt que lue de l'environnement :
    /// les fonctions de style ci-dessus sont ainsi pures, et éprouvables sans
    /// environnement.
    let palette: Palette

    @State private var positions: [Int: CGRect] = [:]

    /// Le nom du repère où les cartes sont mesurées.
    private static let space = "tajweed-verses"

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                contenu(largeur: proxy.size.width, hauteur: proxy.size.height)
            }
        }
    }

    /// Les identifiants des versets de la page — `Array.from({length: end-start+1})`
    /// (`MushafPage.tsx:32`). Une plage inversée rend une liste vide, comme le
    /// `Array.from` d'une longueur négative.
    private var ids: [Int] {
        guard let range = Quran.pageRange(page), range.start <= range.end else { return [] }
        return Array(range.start...range.end)
    }

    // MARK: Le contenu

    private func contenu(largeur: CGFloat, hauteur: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete

            ForEach(ids, id: \.self) { id in
                carte(id, largeur: largeur)
            }

            pied
        }
        .padding(12)
        .frame(width: largeur, minHeight: hauteur, alignment: .top)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 9))
        // Le repère est posé APRÈS la mise en page : c'est la boîte de la liste
        // entière — remplissage compris — que les cartes mesurent, et c'est elle
        // aussi que le rail recouvre. Les deux s'accordent donc par construction.
        .coordinateSpace(name: Self.space)
        .overlay(alignment: .topLeading) { rail }
        .onPreferenceChange(CardBoundsKey.self) { positions = $0 }
    }

    /// `MushafPage.tsx:35` — un libellé doré, centré.
    ///
    /// Le bandeau de séance de l'original n'est pas porté : il remplace cet
    /// en-tête, et le lecteur de ce portage représente la séance par le rail,
    /// comme il le fait sur une page.
    private var enTete: some View {
        Text(TajweedOptions.header(page: page, language: language))
            .font(.system(size: 13))
            .foregroundStyle(palette.gold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 12)
    }

    /// `MushafPage.tsx:42` — la provenance du texte, en 11 pt gris.
    private var pied: some View {
        Text(TajweedOptions.footer(language: language))
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    // MARK: Une carte

    /// Une carte de verset.
    ///
    /// `marginBottom: 8` de l'original est posé **après** la mesure : la marge
    /// est hors de la boîte mesurée, comme `onLayout` la rapporte — sans quoi le
    /// rail descendrait de 8 pt par carte.
    private func carte(_ id: Int, largeur: CGFloat) -> some View {
        TajweedVerseCard(
            id: id,
            verse: Quran.verseAt(id),
            language: language,
            state: TajweedOptions.CardState.of(
                difficult: difficulty.contains(id),
                bookmarked: bookmarks.contains(id),
                playing: id == playing
            ),
            width: largeur,
            textScale: textScale,
            palette: palette
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardBoundsKey.self,
                    value: [id: proxy.frame(in: .named(Self.space))]
                )
            }
        )
        .padding(.bottom, 8)
    }

    // MARK: Le rail

    /// `MushafPage.tsx:41` — la barre et les pastilles, en superposition.
    ///
    /// `pointerEvents="none"` dans l'original : le rail ne doit jamais intercepter
    /// le toucher, sinon on ne pourrait plus ouvrir un verset en appuyant dessus.
    /// `.allowsHitTesting(false)` dit la même chose.
    @ViewBuilder
    private var rail: some View {
        if let session {
            let active = TajweedSessionRail.activeIDs(ids, session: session, positions: positions)
            ZStack(alignment: .topLeading) {
                if let bar = TajweedSessionRail.bar(active: active, positions: positions) {
                    Rectangle()
                        .fill(sessionColor)
                        .frame(width: bar.width, height: bar.height)
                        .opacity(0.35)
                        .offset(x: bar.minX, y: bar.minY)
                }
                ForEach(active, id: \.self) { id in
                    if let dot = TajweedSessionRail.dot(id, positions: positions) {
                        pastille(id: id, dot: dot, session: session)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    /// Une pastille de verset actif — le numéro du verset, rempli si la séance
    /// l'a validé.
    private func pastille(id: Int, dot: CGRect, session: MarginAnnotations.Session) -> some View {
        let rempli = TajweedSessionRail.isFilled(id, through: session.through)
        return Text(String(Quran.verseAt(id).ayah))
            .font(.system(size: 10))
            .foregroundStyle(rempli ? Color.white : sessionColor)
            .frame(width: dot.width, height: dot.height)
            .background(rempli ? sessionColor : palette.paper, in: Circle())
            .overlay(Circle().strokeBorder(sessionColor, lineWidth: 1))
            .offset(x: dot.minX, y: dot.minY)
    }

    /// `sessionColor={colors.review}` — `App.tsx:499`.
    ///
    /// C'est la même couleur que le rail de la marge d'une page : le vert de
    /// séance `#246B48`, qui ne suit pas le thème. `VerseMarginStyle` la porte
    /// déjà, avec la raison — la recopier ici en créerait une seconde source.
    private var sessionColor: Color {
        Color(VerseMarginStyle.sessionGreen)
    }
}

// MARK: - Une carte

/// Le contenu d'une carte : un libellé doré, puis le texte arabe coloré — ou la
/// traduction, selon la langue.
private struct TajweedVerseCard: View {

    let id: Int
    let verse: Verse
    let language: TajweedOptions.ReaderLanguage
    let state: TajweedOptions.CardState
    let width: CGFloat
    let textScale: CGFloat
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `MushafPage.tsx:37` — « Al Fâtiha · verset 1 », en 12 pt doré.
            Text(TajweedOptions.verseLabel(verse))
                .font(.system(size: 12))
                .foregroundStyle(palette.gold)
                .padding(.bottom, 5)

            if language == .arabic {
                arabe
            } else {
                francais
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            TajweedCardStyle.background(state, palette: palette),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            // Une bordure de largeur nulle ne se dessine pas : l'original écrit
            // `borderWidth: 0` pour les trois autres états, et la couleur de
            // bordure est alors définie sans être peinte.
            if TajweedCardStyle.borderWidth(state) > 0 {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        TajweedCardStyle.borderColor(state, palette: palette),
                        lineWidth: TajweedCardStyle.borderWidth(state)
                    )
            }
        }
    }

    /// `MushafPage.tsx:39` — les fragments colorés, puis l'espace, puis le
    /// repère doré.
    ///
    /// L'espace et le repère sont **deux** fragments : l'original les écrit dans
    /// deux `Text` de couleurs différentes, et `TajweedOptions` porte donc deux
    /// constantes. Les confondre peindrait l'espace en doré.
    ///
    /// La concaténation de `Text` exige `foregroundColor`, et non
    /// `foregroundStyle` : avec la cible de déploiement iOS 16,
    /// `Text.foregroundStyle` rend `some View` et l'addition `a + b` ne compile
    /// pas. `foregroundColor` rend un `Text` sur toutes les versions.
    private var arabe: some View {
        var resultat = Text("")
        for span in TajweedOptions.spans(id) {
            resultat = resultat + Text(span.text)
                .foregroundColor(TajweedOptions.color(of: span, textColor: palette.text))
        }
        return (resultat
            + Text(TajweedOptions.ornamentGap).foregroundColor(palette.text)
            + Text(TajweedOptions.ornament).foregroundColor(palette.gold))
            .font(.system(size: TajweedOptions.arabicFontSize(width: width, textScale: textScale)))
            .lineSpacing(TajweedCardStyle.arabicLineSpacing(width: width, textScale: textScale))
            // `textAlign: 'right'` — le texte se cale à droite, et non à gauche.
            // La direction du paragraphe, elle, n'est pas forcée : un texte arabe
            // est reconnu de droite à gauche par l'algorithme bidirectionnel, ce
            // que `writingDirection: 'rtl'` demandait à React Native de croire.
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// `MushafPage.tsx:38` — la traduction, puis la note quand il y en a une.
    ///
    /// `??` et non `if let` : l'original écrit `translation?.translation ??
    /// 'Traduction indisponible.'`, donc une traduction **absente** prend le
    /// libellé de remplacement, alors qu'une traduction vide s'afficherait vide.
    /// Mesuré : aucune des 6 236 traductions n'est vide, donc les deux lectures
    /// coïncident — mais c'est la première que l'original écrit.
    private var francais: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TajweedOptions.translation(id)?.translation ?? TajweedOptions.missingTranslation)
                .font(.system(size: 16))
                .lineSpacing(TajweedCardStyle.lineSpacing(fontSize: 16, lineHeight: 25))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            // `translation?.footnotes ? <Label> : null` — c'est la **vérité** de
            // la note qui décide, et non sa présence : elle est présente sur les
            // 6 236 lignes et vaut `""` sur 4 906. `footnote` rend `nil` dans ce
            // cas, sans quoi 4 906 notes vides s'afficheraient ici.
            if let note = TajweedOptions.translation(id)?.footnote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
            }
        }
    }
}
