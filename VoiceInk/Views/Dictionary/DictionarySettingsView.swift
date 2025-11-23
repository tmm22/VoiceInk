import SwiftUI

struct DictionarySettingsView: View {
    @State private var selectedSection: DictionarySection = .quickRules
    let whisperPrompt: WhisperPrompt
    
    enum DictionarySection: String, CaseIterable {
        case quickRules = "Quick Rules"
        case replacements = "Word Replacements"
        case spellings = "Correct Spellings"
        
        var description: String {
            switch self {
            case .quickRules:
                return "Apply preset correction rules to clean up transcribed text"
            case .spellings:
                return "Add words to help \(AppBrand.communityName) recognize them properly"
            case .replacements:
                return "Automatically replace specific words/phrases with custom formatted text "
            }
        }
        
        var icon: String {
            switch self {
            case .quickRules:
                return "wand.and.stars"
            case .spellings:
                return "character.book.closed.fill"
            case .replacements:
                return "arrow.2.squarepath"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: VoiceInkSpacing.xl) {
            sectionSelector
            
            selectedSectionContent
        }
    }
    
    private var sectionSelector: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            HStack {
                Text("Select Section")
                    .voiceInkHeadline()

                Spacer()

                HStack(spacing: VoiceInkSpacing.sm) {
                    Button(action: {
                        DictionaryImportExportService.shared.importDictionary()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                            .foregroundColor(VoiceInkTheme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Import dictionary items and word replacements")

                    Button(action: {
                        DictionaryImportExportService.shared.exportDictionary()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(VoiceInkTheme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Export dictionary items and word replacements")
                }
            }

            HStack(spacing: VoiceInkSpacing.md) {
                ForEach(DictionarySection.allCases, id: \.self) { section in
                    SectionCard(
                        section: section,
                        isSelected: selectedSection == section,
                        action: { selectedSection = section }
                    )
                }
            }
        }
    }
    
    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            switch selectedSection {
            case .quickRules:
                QuickRulesView()
                    .padding(VoiceInkSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Palette.elevatedSurface.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                    .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                            )
                    )
            case .spellings:
                DictionaryView(whisperPrompt: whisperPrompt)
                    .padding(VoiceInkSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Palette.elevatedSurface.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                    .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                            )
                    )
            case .replacements:
                WordReplacementView()
                    .padding(VoiceInkSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Palette.elevatedSurface.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                    .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                            )
                    )
            }
        }
    }
}

struct SectionCard: View {
    let section: DictionarySettingsView.DictionarySection
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                Image(systemName: section.icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? VoiceInkTheme.Palette.accent : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.rawValue)
                        .voiceInkHeadline()
                    
                    Text(section.description)
                        .voiceInkCaptionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VoiceInkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(VoiceInkTheme.Palette.elevatedSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .stroke(isSelected ? VoiceInkTheme.Palette.accent.opacity(0.5) : VoiceInkTheme.Palette.outline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
} 
