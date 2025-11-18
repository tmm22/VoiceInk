import SwiftUI

struct AppBackgroundView<Content: View>: View {
    var material: NSVisualEffectView.Material = VoiceInkTheme.Sidebar.backgroundMaterial
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    let content: () -> Content

    init(material: NSVisualEffectView.Material = VoiceInkTheme.Sidebar.backgroundMaterial,
         blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
         @ViewBuilder content: @escaping () -> Content) {
        self.material = material
        self.blendingMode = blendingMode
        self.content = content
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: blendingMode)
                .ignoresSafeArea()

            LinearGradient(
                colors: [VoiceInkTheme.Palette.canvas, VoiceInkTheme.Palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.6)
            .ignoresSafeArea()

            content()
        }
    }
}
