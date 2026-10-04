// Components.swift
// Petits composants partagés par plusieurs écrans.
//
// Correspondance : `src/ui/DesignSystem.tsx` et `src/ui/Premium.tsx` côté React
// Native. Les noms et les rôles sont conservés (`DailyTaskCard`,
// `SectionHeader`, `SegmentedControl`, `StatCard`, `ProgressRing`,
// `ProgressTrack`, `ArabicLabel`, `QuranNumberMedallion`) pour que la
// correspondance entre les deux applications reste lisible.
//
// Ces composants ne connaissent pas le modèle : ils reçoivent leur palette par
// l'environnement SwiftUI. Ils ne portent aucune logique métier.

import SwiftUI

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
