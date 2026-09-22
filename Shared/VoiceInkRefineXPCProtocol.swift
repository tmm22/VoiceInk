import Foundation

let voiceInkRefineXPCServiceName = "com.prakashjoshipax.VoiceInk.RefineXPC"
let voiceInkRefineXPCErrorDomain = "com.prakashjoshipax.VoiceInk.RefineXPC"

enum VoiceInkRefineXPCErrorCode: Int {
    case invalidRequest = 1
    case inferenceFailed = 2
    case invalidResponse = 3
    case connectionFailed = 4
}

/// Arguments are passed as plain values; NSXPCInterface serializes String and NSError natively,
/// so no intermediate JSON encoding of the transcript is needed on either side.
/// `requestID` is a UUID string used by the service to track in-flight work.
@objc protocol VoiceInkRefineXPCProtocol {
    func prepare(
        modelDirectoryPath: String,
        systemPrompt: String,
        requestID: String,
        withReply reply: @escaping (NSError?) -> Void
    )

    func enhance(
        transcript: String,
        modelDirectoryPath: String,
        systemPrompt: String,
        requestID: String,
        withReply reply: @escaping (String?, NSError?) -> Void
    )

    func shutdown(withReply reply: @escaping () -> Void)
}

func makeVoiceInkRefineXPCError(
    _ code: VoiceInkRefineXPCErrorCode,
    description: String
) -> NSError {
    NSError(
        domain: voiceInkRefineXPCErrorDomain,
        code: code.rawValue,
        userInfo: [NSLocalizedDescriptionKey: description]
    )
}
