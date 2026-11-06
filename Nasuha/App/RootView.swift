import NasuhaCore
import SwiftData
import SwiftUI

/// Start screen: the logo and app name. Debug builds also show a notice when the content database is missing.
struct RootView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var settings: [UserSettings]

    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("Nasuha")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
            #if DEBUG
            // Developer notice. Release builds never show tool names to users.
            if content.store == nil {
                Text(verbatim: "Content is missing. Run tools/build_content.py.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .preferredColorScheme(settings.first?.appearance.colorScheme)
    }
}
