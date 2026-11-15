import SwiftUI

/// A titled group of rows inside a rounded border, as on Settings and Profile.
struct RowGroup<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Palette.muted)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
        }
    }
}

/// The hairline between two rows of a group.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// The label of one row: a title, an optional note under it, and an optional value on the right.
struct RowLabel: View {
    let title: LocalizedStringKey
    var note: String?
    var value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if let note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(verbatim: value)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A row that goes somewhere when tapped.
struct NavRow: View {
    let title: LocalizedStringKey
    var note: String?
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RowLabel(title: title, note: note, value: value)
        }
        .buttonStyle(.plain)
    }
}

/// A row that opens a short list of choices.
struct ChoiceRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    var note: String?
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(verbatim: option.title)
                    }
                }
            }
        } label: {
            RowLabel(title: title, note: note, value: options.first { $0.value == selection }?.title)
        }
        .buttonStyle(.plain)
    }
}

/// A row with an on/off switch. The whole row is the button, so it is easy to hit.
struct SwitchRow: View {
    let title: LocalizedStringKey
    var note: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Text(verbatim: note)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Capsule()
                    .fill(isOn ? Palette.accent : Palette.line)
                    .frame(width: 50, height: 30)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                            .padding(3)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .animation(.snappy(duration: 0.15), value: isOn)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

/// Back button and centred title for pushed screens.
struct ScreenHeader: View {
    let title: LocalizedStringKey
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                IconButton(systemName: "chevron.backward", label: "Back", action: onBack)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .background(Palette.bg)
    }
}
