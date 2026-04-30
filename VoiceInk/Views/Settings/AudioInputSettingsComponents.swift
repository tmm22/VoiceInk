import SwiftUI

struct InputModeCard: View {
    let mode: AudioInputMode
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch mode {
        case .systemDefault: return "macbook.and.iphone"
        case .custom: return "mic.circle.fill"
        case .prioritized: return "list.number"
        }
    }

    private var description: String {
        switch mode {
        case .systemDefault: return "Use system's default input device"
        case .custom: return "Select a specific input device"
        case .prioritized: return "Set up device priority order"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? VoiceInkTheme.Palette.accent : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .voiceInkHeadline()

                    Text(description)
                        .voiceInkCaptionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VoiceInkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(VoiceInkTheme.Card.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "")
        .help(description)
    }
}

struct DeviceSelectionCard: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? VoiceInkTheme.Palette.accent : .secondary)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)

                Text(name)
                    .foregroundStyle(.primary)

                Spacer()

                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
            .padding(VoiceInkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(VoiceInkTheme.Card.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : (isActive ? "Active" : ""))
    }
}

struct DevicePriorityCard: View {
    let name: String
    let priority: Int?
    let isActive: Bool
    let isPrioritized: Bool
    let isAvailable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onTogglePriority: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack {
            if let priority = priority {
                Text("\(priority + 1)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Text("-")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            Text(name)
                .foregroundStyle(isAvailable ? .primary : .secondary)

            Spacer()

            HStack(spacing: 12) {
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                } else if !isAvailable && isPrioritized {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                }

                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? VoiceInkTheme.Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        .frame(minWidth: 20, minHeight: 20)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Move \(name) up")
                        .help("Move \(name) up")

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? VoiceInkTheme.Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                        .frame(minWidth: 20, minHeight: 20)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Move \(name) down")
                        .help("Move \(name) down")
                    }
                }

                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : VoiceInkTheme.Palette.accent)
                }
                .frame(minWidth: 20, minHeight: 20)
                .contentShape(Rectangle())
                .accessibilityLabel(isPrioritized ? "Remove \(name) from prioritized devices" : "Add \(name) to prioritized devices")
                .help(isPrioritized ? "Remove from prioritized devices" : "Add to prioritized devices")
            }
            .buttonStyle(.plain)
        }
        .padding(VoiceInkSpacing.md)
        .background(
             RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                 .fill(VoiceInkTheme.Card.background)
                 .overlay(
                     RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                         .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                 )
        )
    }
}
