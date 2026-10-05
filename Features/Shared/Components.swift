// Components.swift
// Petits composants partagés par plusieurs écrans.
//
// Correspondance : `src/ui/DesignSystem.tsx` et `src/ui/Premium.tsx` côté React
// Native. Les noms et les rôles sont conservés (`DailyTaskCard`,
// `SectionHeader`, `SegmentedControl`, `StatCard`, `ProgressRing`,
// `ProgressTrack`, `ArabicLabel`, `QuranNumberMedallion`, `ThemeArtImage`) pour
// que la correspondance entre les deux applications reste lisible.
//
// Ces composants ne connaissent pas le modèle : ils reçoivent leur palette par
// l'environnement SwiftUI. Ils ne portent aucune logique métier.

import SwiftUI
import UIKit

// MARK: - En-tête de section

struct SectionHeader: View {
    @Environment(\.palette) private var palette

    let title: String
    var action: String?
    var onPress: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: Theme.Typography.section, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer()
            if let action, let onPress {
                Button(action: onPress) {
                    Text(action)
                        .font(.system(size: Theme.Typography.secondary, weight: .medium))
                        .foregroundStyle(palette.green)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Carte de tâche du jour

/// La carte « Apprentissage » / « Révision » de l'accueil et du programme.
struct DailyTaskCard: View {
    @Environment(\.palette) private var palette

    let title: String
    let passage: String
    let details: String
    var isRevision: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: isRevision ? "arrow.triangle.2.circlepath" : "book")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.green)
                    Text(title)
                        .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
                Text(passage)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(details)
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(Theme.Spacing.md)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .stroke(palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sélecteur segmenté

/// `SegmentedControl` — `src/ui/DesignSystem.tsx`.
struct SegmentedControl: View {
    @Environment(\.palette) private var palette

    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = index
                } label: {
                    Text(option)
                        .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                        .foregroundStyle(selection == index ? palette.paper : palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            selection == index ? palette.green : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}

// MARK: - Statistique

struct StatCard: View {
    @Environment(\.palette) private var palette

    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(palette.green)
            Text(value)
                .font(.system(size: Theme.Typography.header, weight: .bold))
                .foregroundStyle(palette.text)
            Text(title)
                .font(.system(size: Theme.Typography.metadata))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .stroke(palette.line, lineWidth: 1)
        )
    }
}

// MARK: - Anneau de progression

/// `ProgressRing` — `src/ui/Premium.tsx`.
struct ProgressRing<Content: View>: View {
    @Environment(\.palette) private var palette

    let value: Double
    var size: CGFloat = 112
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.line, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(palette.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Barre de progression

/// `ProgressTrack` — `src/ui/Premium.tsx`.
struct ProgressTrack: View {
    @Environment(\.palette) private var palette

    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.line)
                Capsule()
                    .fill(palette.green)
                    .frame(width: geometry.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Libellé arabe

struct ArabicLabel: View {
    @Environment(\.palette) private var palette

    let text: String
    var size: CGFloat = Theme.Typography.arabic
    var color: Color?

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(color ?? palette.gold)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Médaillon numéroté

/// `QuranNumberMedallion` — `src/ui/DesignSystem.tsx`.
struct QuranNumberMedallion: View {
    @Environment(\.palette) private var palette

    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: Theme.Typography.secondary, weight: .bold))
            .foregroundStyle(palette.green)
            .frame(width: 38, height: 38)
            .background(palette.selected, in: Circle())
            .overlay(Circle().stroke(palette.softBorder, lineWidth: 1))
    }
}

// MARK: - En-tête d'écran

/// `IslamicHero` — `src/ui/Premium.tsx`, dans sa version sobre.
struct HeroHeader: View {
    @Environment(\.palette) private var palette

    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.system(size: Theme.Typography.screen, weight: .bold))
                .foregroundStyle(palette.green)
            Text(subtitle)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Ligne sélectionnable

/// Les deux formes de `src/ui/DesignSystem.tsx` en un seul composant :
///
///   - `.single`   → `Choice`      : une seule réponse possible (objectif,
///                                   niveau de rythme). Une pastille.
///   - `.multiple` → `CheckChoice` : plusieurs réponses possibles (sourates
///                                   connues, jours d'apprentissage). Une coche.
///
/// C'est un BOUTON, jamais un `Toggle` : l'état affiché est **exactement**
/// celui qu'on lui passe. Un `Toggle` garderait un état interne, qui pourrait
/// diverger de `state.knowledge` — le même piège que la case `autoStop` de
/// l'écran audio (`Features/Quran/AudioRepeatSettingsView.swift:19`).
///
/// Aucune décision ici : `selected` est calculé par l'appelant à partir du
/// modèle, et `action` ne fait que remonter l'intention.
struct SelectableRow: View {
    enum Style {
        case single
        case multiple
    }

    @Environment(\.palette) private var palette

    let label: String
    var subtitle: String?
    let selected: Bool
    var style: Style = .single
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: Theme.Typography.body))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(palette.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(selected ? palette.green : palette.line)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Les deux marques de la référence, reprises à l'identique :
    /// `Choice` affiche `●` / `○`, `CheckChoice` une case CARRÉE avec un `✓`.
    /// Le carré n'est pas un détail : c'est ce qui distingue « plusieurs
    /// réponses possibles » de « une seule ».
    private var symbol: String {
        switch (style, selected) {
        case (.multiple, true): return "checkmark.square.fill"
        case (.multiple, false): return "square"
        case (.single, true): return "largecircle.fill.circle"
        case (.single, false): return "circle"
        }
    }
}

// MARK: - État vide

struct EmptyLabel: View {
    @Environment(\.palette) private var palette

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: Theme.Typography.secondary))
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Bouton de carte

/// Le bouton d'une carte — la traduction du `Button` **secondaire** de
/// l'original (`src/ui/theme.tsx:29`, `secondary`).
///
/// Un seul endroit pour ce style : la recette vivait **trois fois** — dans le
/// gabarit `settingsRow` de `SettingsView`, dans l'`actionButton` de
/// `NotificationSettingsView`, et il en fallait une quatrième pour l'écran du
/// profil. Trois copies divergent au premier ajustement. Les valeurs sont celles
/// de ce gabarit — la traduction déjà retenue, déjà à l'écran — et non une
/// seconde lecture de l'original : les changer ici change les trois pages d'un
/// coup, ce qui est précisément le but.
///
/// L'opacité à l'arrêt est celle de l'original (`disabled && {opacity:0.45}`).
/// Elle ne sert encore nulle part : le bouton de connexion désactivé de
/// l'original n'est pas monté ici (voir `Features/Profile/ProfileView.swift`).
struct CardButton: View {
    @Environment(\.palette) private var palette

    let title: String
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(palette.green)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    palette.soft,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - Bouton de profil de la barre de titre

/// `ProfileHeaderButton` — `src/ui/ProfileHeaderButton.tsx`.
///
/// Le rond vert cerclé d'or de la barre de titre, qui porte l'**initiale** du
/// prénom — ou, faute de prénom, un petit bonhomme blanc.
///
/// L'initiale vient de `ProfileOptions.avatarInitial(_:)` : c'est une décision
/// (quelle lettre, dans quelle casse) et non une mise en page, et l'original la
/// prend en JavaScript avec `Array.from(...)[0]?.toLocaleUpperCase('fr-FR')`.
/// La vue ne fait que la poser.
///
/// Le bonhomme de repli est **dessiné** dans l'original — une tête de 9 × 9 et
/// deux épaules de 17 × 9 aux coins supérieurs arrondis — et non une icône.
/// `person.fill` de SF Symbols a exactement ces proportions : une tête ronde et
/// des épaules en dôme. Le redessiner à la main donnerait un tracé qui ne
/// suivrait ni la taille de police ni le rendu des autres icônes de la barre.
///
/// Aucun libellé d'accessibilité ici : l'appelant le pose, comme il le pose pour
/// l'engrenage des réglages.
struct ProfileHeaderButton: View {
    @Environment(\.palette) private var palette

    let firstName: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(palette.green)
                    .overlay(Circle().stroke(palette.gold, lineWidth: 1))
                    .frame(width: 36, height: 36)
                if let initial = ProfileOptions.avatarInitial(firstName) {
                    Text(initial)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avis global

/// L'avis posé en bas de l'écran — `App.tsx:256`.
///
/// L'application d'origine n'en a **qu'un**, à la racine de son interface : il
/// recouvre tout, se ferme au toucher, et porte le même cadre doré quel que soit
/// l'écran qui l'a demandé. Ce portage le monte de la même façon, dans
/// `App/ContentView.swift`.
///
/// C'est ce qui rend le canal `notice` du modèle **visible** : jusqu'ici, cinq
/// écrans posaient un avis que rien n'affichait — l'écran de connexion excepté,
/// qui lit `model.notice` pour son propre message. Sans cette vue, la carte du
/// profil enregistrerait le prénom et se synchroniserait en silence.
///
/// Le `×` de l'original est collé au texte dans un seul `Label`
/// (`{notice}  ×`). Il est ici une seconde vue : c'est une **commande** — fermer
/// — et non du texte, sans quoi la voix de synthèse lirait « fois » à la fin de
/// chaque avis.
struct NoticeToast: View {
    @Environment(\.palette) private var palette

    let text: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(text)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("×")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .stroke(palette.gold, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }
}

// MARK: - Illustration d'un thème

/// `themeArt` — l'illustration d'un thème, lue dans `Resources/Themes`
/// (`src/ui/Premium.tsx:9`).
///
/// Les cinq PNG sont embarqués en **référence de dossier** (`type: folder` dans
/// `project.yml`), donc ils gardent leur sous-dossier et leur nom de fichier.
/// Un thème **inconnu ne rend rien** plutôt qu'une image inventée :
/// `Theme.artName(for:)` rend `nil`, exactement comme `themeArt[clé]` rend
/// `undefined` pour une clé absente.
///
/// Le mode est un **recadrage**, et ce n'est pas indifférent : les quatre
/// illustrations carrées sont en 1254 × 1254, mais `white.png` est en
/// 1613 × 975. Un ajustement qui préserve l'image entière laisserait donc des
/// bandes vides sur un thème et pas sur les autres.
struct ThemeArtImage: View {
    let theme: String

    var body: some View {
        if let image = ThemeArtCache.image(for: theme) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            Color.clear
        }
    }
}

/// Le cache des cinq illustrations.
///
/// Chacune pèse deux mégaoctets sur disque et se décode en 1254 × 1254 : les
/// relire à chaque rendu ferait clignoter la liste des thèmes et repayerait le
/// décodage à chaque passage. `NSCache` — et non un dictionnaire — parce qu'il
/// se vide de lui-même sous pression mémoire, ce qu'un dictionnaire statique ne
/// ferait jamais.
enum ThemeArtCache {
    private static let cache = NSCache<NSString, UIImage>()

    /// `nonisolated` à dessein : la lecture ne touche que des valeurs immuables
    /// et `Bundle.main`, et elle est appelée depuis la mise en page, qui est
    /// synchrone.
    nonisolated static func image(for theme: String) -> UIImage? {
        guard let name = Theme.artName(for: theme) else { return nil }
        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(
            forResource: base,
            withExtension: ext,
            subdirectory: "Themes"
        ), let image = UIImage(contentsOfFile: url.path) else { return nil }

        cache.setObject(image, forKey: key)
        return image
    }
}
