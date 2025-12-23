import SwiftUI

extension TTSSettingsViewModel {
    func resetStyleControl(_ control: ProviderStyleControl) {
        guard hasActiveStyleControls else { return }
        guard canResetStyleControl(control) else { return }
        styleValues[control.id] = control.defaultValue
    }

    func resetStyleControls() {
        guard hasActiveStyleControls else { return }
        let defaults = activeStyleControls.reduce(into: [String: Double]()) { partialResult, control in
            partialResult[control.id] = control.defaultValue
        }
        styleValues = defaults
    }

    func refreshStyleControls(for providerType: TTSProviderType) {
        let provider = getProvider(for: providerType)
        let controls = provider.styleControls
        activeStyleControls = controls

        guard !controls.isEmpty else {
            styleValues = [:]
            cachedStyleValues[providerType] = [:]
            return
        }

        let resolved = resolveStyleValues(for: controls, cached: cachedStyleValues[providerType])
        styleValues = resolved
    }

    func resolveStyleValues(for controls: [ProviderStyleControl], cached: [String: Double]?) -> [String: Double] {
        controls.reduce(into: [:]) { partialResult, control in
            let stored = cached?[control.id] ?? control.defaultValue
            partialResult[control.id] = control.clamp(stored)
        }
    }

    func styleValues(for providerType: TTSProviderType) -> [String: Double] {
        if providerType == selectedProvider {
            return styleValues
        }

        let provider = getProvider(for: providerType)
        let controls = provider.styleControls
        guard !controls.isEmpty else {
            cachedStyleValues[providerType] = [:]
            persistStyleValues()
            return [:]
        }
        let resolved = resolveStyleValues(for: controls, cached: cachedStyleValues[providerType])
        cachedStyleValues[providerType] = resolved
        persistStyleValues()
        return resolved
    }

    func persistStyleValues() {
        let filtered = cachedStyleValues.reduce(into: [String: [String: Double]]()) { partialResult, element in
            guard !element.value.isEmpty else { return }
            partialResult[element.key.rawValue] = element.value
        }

        if filtered.isEmpty {
            AppSettings.TTS.styleValuesData = nil
            return
        }

        do {
            let data = try JSONEncoder().encode(filtered)
            AppSettings.TTS.styleValuesData = data
        } catch {
            AppLogger.storage.error("Failed to persist style values: \(error.localizedDescription)")
        }
    }

    func binding(for control: ProviderStyleControl) -> Binding<Double> {
        Binding(
            get: { self.currentStyleValue(for: control) },
            set: { newValue in
                let clamped = control.clamp(newValue)
                if self.styleValues[control.id] != clamped {
                    self.styleValues[control.id] = clamped
                }
            }
        )
    }

    func currentStyleValue(for control: ProviderStyleControl) -> Double {
        styleValues[control.id] ?? control.defaultValue
    }

    func canResetStyleControl(_ control: ProviderStyleControl) -> Bool {
        abs(currentStyleValue(for: control) - control.defaultValue) > styleComparisonEpsilon
    }
}
