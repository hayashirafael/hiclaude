import AppKit
import SwiftUI

@MainActor
enum ProviderVisual {
    private static var cache: [Provider: NSImage] = [:]

    static func image(for provider: Provider) -> NSImage? {
        if let cached = cache[provider] { return cached }
        let name = provider == .claude ? "ClaudeSpark" : "OpenAIBlossom"
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[provider] = image
        return image
    }
}

struct ProviderIcon: View {
    let provider: Provider?
    var size: CGFloat = 16
    var fallbackSystemName: String = "terminal"

    var body: some View {
        Group {
            if let provider, let image = ProviderVisual.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel(provider?.displayName ?? "Command")
    }
}

struct ProviderBadge: View {
    let provider: Provider?
    let title: String
    var fallbackSystemName: String = "terminal"

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: provider, size: 13,
                         fallbackSystemName: fallbackSystemName)
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.secondary.opacity(0.12), in: Capsule())
    }
}
