import AppKit
import SwiftUI

struct BrandLogo: View {
    let state: MenuVisualState
    let size: CGFloat
    let showsPulse: Bool

    @State private var isBreathing = false

    var body: some View {
        ZStack {
            if let iconURL = Bundle.main.url(forResource: "GitHubReadyIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: state.systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(fallbackColor, Color.primary)
            }

            if showsPulse, state == .ready {
                Circle()
                    .stroke(.green.opacity(isBreathing ? 0.03 : 0.82), lineWidth: max(1, size * 0.06))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .scaleEffect(isBreathing ? 1.7 : 0.8)
                    .position(x: size * 0.67, y: size * 0.58)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            updateBreathingAnimation(for: state)
        }
        .onChange(of: state) { newState in
            updateBreathingAnimation(for: newState)
        }
    }

    private var fallbackColor: Color {
        switch state {
        case .ready: .green
        case .checking: .blue
        case .partial: .yellow
        case .networkUnavailable: .orange
        case .authenticationRequired: .red
        case .cliMissing: .gray
        }
    }

    private func updateBreathingAnimation(for newState: MenuVisualState) {
        isBreathing = false
        guard showsPulse, newState == .ready else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }
}
