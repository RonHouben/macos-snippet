import SwiftUI

struct CapturePreviewView: View {
    let image: CGImage
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovered = false

    private var previewBadgeForegroundStyle: AnyShapeStyle {
        isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var previewBadgeBackground: Color {
        isHovered ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08)
    }

    private var imageBorderColor: Color {
        .white.opacity(isHovered ? 0.26 : 0.12)
    }

    private var cardBorderColor: Color {
        isHovered ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.10)
    }

    private var callToActionBackground: Color {
        isHovered ? Color.accentColor : Color.primary.opacity(0.10)
    }

    private var callToActionForegroundStyle: AnyShapeStyle {
        isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)

                    Text("Copied to clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("Preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(previewBadgeForegroundStyle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(previewBadgeBackground)
                        )
                }

                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 220, height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(imageBorderColor, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [.black.opacity(0.26), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in editor")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Annotate, crop, and export")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(callToActionForegroundStyle)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(callToActionBackground)
                        )
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(cardBorderColor, lineWidth: isHovered ? 1.5 : 1)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isHovered ? 0.10 : 0.05),
                                .clear,
                                .black.opacity(isHovered ? 0.05 : 0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovered ? 1.018 : 1)
            .offset(y: isHovered ? -2 : 0)
            .animation(.easeOut(duration: 0.16), value: isHovered)
        }
        .buttonStyle(CapturePreviewButtonStyle())
        .padding(12)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
        .focusable(false)
        .accessibilityIdentifier(AppAutomationIdentifiers.capturePreviewRoot)
    }
}

private struct CapturePreviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .brightness(configuration.isPressed ? -0.01 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
