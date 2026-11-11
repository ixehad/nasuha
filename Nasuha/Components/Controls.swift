import SwiftUI

/// The one accent button on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var minHeight: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isEnabled ? Palette.onAccent : Palette.muted)
            .background(isEnabled ? Palette.accent : Palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// An outlined button for second choices.
struct OutlineButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(Palette.ink)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A plain text button in the accent colour.
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Palette.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A pill that can be picked: topics, minutes.
struct Pill: View {
    let title: String
    let isOn: Bool
    var showsCheck = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn && showsCheck {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(isOn ? .semibold : .medium))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Palette.tintInk : Palette.ink)
            .background(isOn ? Palette.tint : Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Palette.accent : Palette.line, lineWidth: isOn ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A row of choices where exactly one is picked.
struct SegmentedBar<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(isOn ? .semibold : .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Palette.ink)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Palette.surface)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Small capital heading above a group.
struct GroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The app logo, rounded like the icon.
struct LogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.223, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A 44 pt icon button with a spoken label.
struct IconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The two-step marker at the top of setup.
struct StepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Palette.accent : Palette.line)
                    .frame(width: 22, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: ProposedViewSize(width: min(result.sizes[index].width, bounds.width), height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], sizes: [CGSize], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, sizes, widest, y + rowHeight)
    }
}
