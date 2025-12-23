import Foundation

enum HTTPResponseHandler {
    static func handleResponse(
        _ response: URLResponse,
        data: Data,
        successCodes: Set<Int> = [200],
        unauthorizedCodes: Set<Int> = [401],
        onUnauthorized: (() -> Void)? = nil,
        errorOverrides: [Int: (Data) -> TTSError] = [:],
        errorMessageDecoder: ((Data) -> String?)? = nil,
        clientErrorFormat: String = "Client error: %d",
        serverErrorFormat: String = "Server error: %d",
        unexpectedFormat: String = "Unexpected response: %d"
    ) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError("Invalid response")
        }

        let statusCode = httpResponse.statusCode
        if successCodes.contains(statusCode) {
            return data
        }

        if let override = errorOverrides[statusCode] {
            throw override(data)
        }

        if unauthorizedCodes.contains(statusCode) {
            onUnauthorized?()
            throw TTSError.invalidAPIKey
        }

        if statusCode == 429 {
            throw TTSError.quotaExceeded
        }

        switch statusCode {
        case 400...499:
            if let message = errorMessageDecoder?(data) {
                throw TTSError.apiError(message)
            }
            throw TTSError.apiError(String(format: clientErrorFormat, statusCode))
        case 500...599:
            throw TTSError.apiError(String(format: serverErrorFormat, statusCode))
        default:
            throw TTSError.apiError(String(format: unexpectedFormat, statusCode))
        }
    }
}
