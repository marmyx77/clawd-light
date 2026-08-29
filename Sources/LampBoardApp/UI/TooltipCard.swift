import LampBoardCore
import SwiftUI

/// The row's second layer, drawn.
///
/// It reads a `RowSummary` and decides nothing: what appears, in what order and
/// under which word is settled in Core, where a test can see it. Everything here
/// is about weight, spacing and colour — the three things the old version, one
/// `Text` holding a string with newlines in it, had none of.
///
/// The one colour is the row's own state. Everything else is greyscale on
/// purpose: a tooltip that introduced a second palette would compete with the
/// column it exists to explain.
struct TooltipCard: View {
    let summary: RowSummary
    /// Fixed, and passed in rather than measured: the window has to be sized
    /// before it is shown, and a card whose width depends on its content would
    /// make every tooltip a different shape.
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            grid.padding(.top, 9)

            if !summary.sessions.isEmpty {
                sessions.padding(.top, 6)
            }

            if let message = summary.message, !message.isEmpty {
                separator
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(summary.messageIsError ? StatusPalette.warningTint : Color.primary.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = summary.notice {
                Text(notice)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.top, 7)
            }

            separator
            Text(summary.keys)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Head

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle()
                    .fill(StatusPalette.color(for: summary.status))
                    .frame(width: 8, height: 8)
                    .opacity(StatusPalette.opacity(for: summary.status))

                Text(summary.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // The state word takes the light's colour, which is the one thing
            // that makes this card unmistakably *this* row's. The rest of the
            // line — where it is, what folder it really is — stays grey.
            (
                Text(summary.status.label)
                    .foregroundColor(StatusPalette.color(for: summary.status))
                + Text(summary.subtitle.map { " · \($0)" } ?? "")
                    .foregroundColor(Color.primary.opacity(0.55))
            )
            .font(.system(size: 11))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 15)
        }
    }

    // MARK: - The grid

    private var grid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(summary.fields.enumerated()), id: \.offset) { _, field in
                GridRow(alignment: .firstTextBaseline) {
                    Text(field.label.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .kerning(0.5)
                        .foregroundStyle(Color.primary.opacity(0.38))
                        .gridColumnAlignment(.leading)

                    VStack(alignment: .leading, spacing: 3) {
                        (
                            Text(field.value)
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundColor(Color.primary.opacity(0.92))
                            + Text(field.detail.map { "  \($0)" } ?? "")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundColor(Color.primary.opacity(0.5))
                        )
                        .fixedSize(horizontal: false, vertical: true)

                        // The one field with a shape. It is the same quantity the
                        // ring on the row draws, at a size where the difference
                        // between 62% and 86% is a length instead of an arc.
                        if let fill = field.fill {
                            GeometryReader { space in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.13))
                                    Capsule()
                                        .fill(Color.primary.opacity(0.72))
                                        .frame(width: max(2, space.size.width * fill))
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                }
            }
        }
    }

    /// One line per session, when the row is a whole project.
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(summary.sessions.enumerated()), id: \.offset) { _, state in
                Text("· \(state)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .padding(.leading, 2)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 9)
    }
}
