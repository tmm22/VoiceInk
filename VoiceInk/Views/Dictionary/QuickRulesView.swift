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
    @State private var selectedCategory: QuickRule.RuleCategory?
    @State private var showAddRuleSheet = false
    @State private var showResetConfirmation = false
    @State private var testInput = ""
    @State private var testOutput = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Info Section with Toggle
            GroupBox {
                HStack {
                    Label {
                        Text("Apply quick correction rules to clean up transcribed text automatically")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(alignment: .leading)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Toggle("Enable", isOn: $manager.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Enable automatic quick rules after transcription")
                }
            }
            
            // Test Section
            if manager.isEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Rules")
                            .font(.headline)
                        
                        Text("Type or paste text to see how rules will transform it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $testInput)
                                    .font(.system(size: 12))
                                    .frame(height: 60)
                                    .padding(4)
                                    .background(Color(.textBackgroundColor))
                                    .cornerRadius(6)
                                    .onChange(of: testInput) { _, newValue in
                                        testOutput = QuickRulesService.shared.applyRules(to: newValue, rules: manager.rules)
                                    }
                            }
                            
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Output:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: .constant(testOutput))
                                    .font(.system(size: 12))
                                    .frame(height: 60)
                                    .padding(4)
                                    .background(Color(.textBackgroundColor))
                                    .cornerRadius(6)
                                    .opacity(0.8)
                            }
                        }
                        
                        // Quick test buttons
                        HStack {
                            Button("Test: 'I'm gonna wanna kinda go there'") {
                                testInput = "I'm gonna wanna kinda go there"
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            
                            Button("Test: 'um, you know, like, it's the the best'") {
                                testInput = "um, you know, like, it's the the best"
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            
                            Spacer()
                            
                            Button("Clear") {
                                testInput = ""
                                testOutput = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
            
            Divider()
            
            // Rules Management Header
            HStack {
                Text("Quick Rules")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showResetConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                }
                .buttonStyle(.borderless)
                .help("Reset all rules to default presets")
                
                Button {
                    showAddRuleSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Custom Rule")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Rules by Category
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(QuickRule.RuleCategory.allCases, id: \.self) { category in
                        if let categoryRules = manager.rulesByCategory()[category], !categoryRules.isEmpty {
                            CategorySection(
                                category: category,
                                rules: categoryRules,
                                onToggle: { rule in
                                    manager.toggleRule(rule)
                                },
                                onDelete: { rule in
                                    manager.removeRule(rule)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showAddRuleSheet) {
            AddCustomRuleSheet(manager: manager)
        }
        .alert("Reset to Defaults", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                manager.resetToDefaults()
            }
        } message: {
            Text("This will reset all rules to their default state and remove any custom rules. This cannot be undone.")
        }
    }
}

struct CategorySection: View {
    let category: QuickRule.RuleCategory
    let rules: [QuickRule]
    let onToggle: (QuickRule) -> Void
    let onDelete: (QuickRule) -> Void
    
    @State private var isExpanded = true
    
    var enabledCount: Int {
        rules.filter { $0.isEnabled }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(.accentColor)
                    
                    Text(category.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("(\(enabledCount)/\(rules.count) enabled)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(rules) { rule in
                        QuickRuleRow(
                            rule: rule,
                            onToggle: { onToggle(rule) },
                            onDelete: rule.category == .custom ? { onDelete(rule) } : nil
                        )
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

struct QuickRuleRow: View {
    let rule: QuickRule
    let onToggle: () -> Void
    let onDelete: (() -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .medium))
                
                Text(rule.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // Show pattern in monospace for technical users
                HStack(spacing: 4) {
                    Text(rule.isRegex ? "Regex:" : "Text:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                    Text(rule.pattern)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if !rule.replacement.isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .opacity(0.5)
                        Text(rule.replacement)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0)
                .help("Delete custom rule")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.textBackgroundColor))
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
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
