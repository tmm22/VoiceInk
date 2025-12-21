import Foundation

// MARK: - Prompt Management
extension AIEnhancementService {
    
    /// Adds a new custom prompt
    /// - Parameters:
    ///   - title: The prompt title
    ///   - promptText: The prompt text/instructions
    ///   - icon: The icon for the prompt
    ///   - description: Optional description
    ///   - triggerWords: Words that trigger this prompt
    ///   - useSystemInstructions: Whether to use system instructions
    func addPrompt(
        title: String,
        promptText: String,
        icon: PromptIcon = "doc.text.fill",
        description: String? = nil,
        triggerWords: [String] = [],
        useSystemInstructions: Bool = true
    ) {
        let newPrompt = CustomPrompt(
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false,
            triggerWords: triggerWords,
            useSystemInstructions: useSystemInstructions
        )
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    /// Updates an existing prompt
    /// - Parameter prompt: The prompt with updated values
    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    /// Deletes a prompt
    /// - Parameter prompt: The prompt to delete
    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    /// Sets the active prompt
    /// - Parameter prompt: The prompt to make active
    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    /// Initializes predefined prompts, updating existing ones and adding new ones
    func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                // Update existing predefined prompt with latest template values
                // but preserve user's trigger words and active state
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                // Add new predefined prompt
                customPrompts.append(template)
            }
        }
    }
}
