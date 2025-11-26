import SwiftUI

class QuickRulesManager: ObservableObject {
    @Published var rules: [QuickRule]
    @Published var isEnabled: Bool {
        didSet {
            QuickRulesService.shared.isEnabled = isEnabled
        }
    }
    
    init() {
        self.rules = QuickRulesService.shared.loadRules()
        self.isEnabled = QuickRulesService.shared.isEnabled
    }
    
    func toggleRule(_ rule: QuickRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled.toggle()
            saveRules()
        }
    }
    
    func addRule(_ rule: QuickRule) {
        rules.append(rule)
        saveRules()
    }
    
    func removeRule(_ rule: QuickRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    func updateRule(_ rule: QuickRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    func resetToDefaults() {
        QuickRulesService.shared.resetToDefaults()
        rules = QuickRulesService.shared.loadRules()
    }
    
    private func saveRules() {
        QuickRulesService.shared.saveRules(rules)
    }
    
    func rulesByCategory() -> [QuickRule.RuleCategory: [QuickRule]] {
        Dictionary(grouping: rules, by: { $0.category })
    }
}

struct QuickRulesView: View {
    @StateObject private var manager = QuickRulesManager()
    @State private var showAddRuleSheet = false
    @State private var showResetConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            // Header with toggle and actions
            HStack {
                Toggle("Enable Quick Rules", isOn: $manager.isEnabled)
                    .toggleStyle(.switch)
                
                Spacer()
                
                Button {
                    showResetConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to defaults")
                
                Button {
                    showAddRuleSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add custom rule")
            }
            
            Text("Automatically clean up transcribed text")
                .voiceInkCaptionStyle()
            
            if manager.isEnabled {
                Divider()
                
                // Rules list by category
                ScrollView {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                        ForEach(QuickRule.RuleCategory.allCases, id: \.self) { category in
                            if let categoryRules = manager.rulesByCategory()[category], !categoryRules.isEmpty {
                                SimpleCategorySection(
                                    category: category,
                                    rules: categoryRules,
                                    onToggle: { rule in manager.toggleRule(rule) },
                                    onDelete: { rule in manager.removeRule(rule) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRuleSheet) {
            AddCustomRuleSheet(manager: manager)
        }
        .alert("Reset to Defaults", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                manager.resetToDefaults()
            }
        } message: {
            Text("This will reset all rules to their default state and remove any custom rules.")
        }
    }
}

struct SimpleCategorySection: View {
    let category: QuickRule.RuleCategory
    let rules: [QuickRule]
    let onToggle: (QuickRule) -> Void
    let onDelete: (QuickRule) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
            // Category header
            HStack(spacing: VoiceInkSpacing.xs) {
                Image(systemName: category.icon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text(category.rawValue)
                    .voiceInkHeadline()
            }
            
            // Rules
            VStack(spacing: VoiceInkSpacing.xs) {
                ForEach(rules) { rule in
                    SimpleRuleRow(
                        rule: rule,
                        onToggle: { onToggle(rule) },
                        onDelete: rule.category == .custom ? { onDelete(rule) } : nil
                    )
                }
            }
        }
    }
}

struct SimpleRuleRow: View {
    let rule: QuickRule
    let onToggle: () -> Void
    let onDelete: (() -> Void)?
    
    @State private var isHovered = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(.system(size: 12))
                    Text(rule.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let onDelete = onDelete, isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                
                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, VoiceInkSpacing.xs)
            .padding(.horizontal, VoiceInkSpacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            // Collapsible technical details
            if isExpanded {
                VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                    Divider()
                    HStack(spacing: VoiceInkSpacing.xs) {
                        Text(rule.isRegex ? "Pattern:" : "Find:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(rule.pattern)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    HStack(spacing: VoiceInkSpacing.xs) {
                        Text("Replace:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(rule.replacement.isEmpty ? "(remove)" : rule.replacement)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                            .italic(rule.replacement.isEmpty)
                    }
                }
                .padding(.horizontal, VoiceInkSpacing.sm)
                .padding(.bottom, VoiceInkSpacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                .fill(VoiceInkTheme.Card.background)
        )
        .onHover { isHovered = $0 }
    }
}

struct AddCustomRuleSheet: View {
    @ObservedObject var manager: QuickRulesManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var isRegex = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Text("Add Custom Rule")
                    .font(.headline)
                
                Spacer()
                
                Button("Add") {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(name.isEmpty || pattern.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(CardBackground(isSelected: false))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rule Name")
                            .font(.headline)
                        TextField("e.g., 'Convert yeah to yes'", text: $name)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Description")
                            .font(.headline)
                        TextField("e.g., 'Replace casual 'yeah' with formal 'yes''", text: $description)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Pattern to Match")
                            .font(.headline)
                        TextField(isRegex ? "Enter regex pattern" : "Enter text to find", text: $pattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        Toggle("Use Regular Expression", isOn: $isRegex)
                            .font(.subheadline)
                        
                        if isRegex {
                            Text("Regex patterns allow advanced matching. Use \\\\b for word boundaries.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Replacement")
                            .font(.headline)
                        TextField("Enter replacement text (leave empty to remove)", text: $replacement)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        if isRegex {
                            Text("Use $1, $2, etc. to reference capture groups")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    // Examples
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Examples")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            ExampleCard(
                                title: "Simple Text Replacement",
                                pattern: "yeah",
                                replacement: "yes",
                                isRegex: false
                            )
                            
                            ExampleCard(
                                title: "Word Boundary Match",
                                pattern: "\\\\bcan't\\\\b",
                                replacement: "cannot",
                                isRegex: true
                            )
                            
                            ExampleCard(
                                title: "Remove Pattern",
                                pattern: "\\\\bbasically\\\\b",
                                replacement: "",
                                isRegex: true
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private func addRule() {
        let rule = QuickRule(
            name: name,
            description: description.isEmpty ? name : description,
            pattern: pattern,
            replacement: replacement,
            isRegex: isRegex,
            category: .custom
        )
        manager.addRule(rule)
        dismiss()
    }
}

struct ExampleCard: View {
    let title: String
    let pattern: String
    let replacement: String
    let isRegex: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pattern:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern)
                        .font(.system(size: 11, design: .monospaced))
                }
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replacement:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(replacement.isEmpty ? "(remove)" : replacement)
                        .font(.system(size: 11, design: .monospaced))
                        .italic(replacement.isEmpty)
                }
            }
            
            HStack {
                Text(isRegex ? "Regex" : "Text")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(Color(.textBackgroundColor))
        .cornerRadius(8)
    }
}
