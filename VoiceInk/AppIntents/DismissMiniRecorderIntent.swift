import AppIntents
import Foundation
import AppKit

struct DismissMiniRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Dismiss VoiceInk Community Recorder"
    static var description = IntentDescription("Dismiss the VoiceInk Community mini recorder and cancel any active recording.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .dismissMiniRecorder, object: nil)
        
        let dialog = IntentDialog(stringLiteral: "\(AppBrand.communityName) recorder dismissed")
        return .result(dialog: dialog)
    }
}
