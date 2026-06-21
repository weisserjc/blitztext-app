import Foundation

enum OpenAITranscriptionClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API Key fehlt."
        case .invalidResponse:
            return "Ungueltige Antwort von OpenAI."
        case .apiError(let message):
            return "OpenAI-Fehler: \(message)"
        case .emptyTranscript:
            return "Keine Sprache erkannt."
        }
    }
}

private struct OpenAITranscriptionErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

enum OpenAITranscriptionClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private static let model = "whisper-1"

    static func transcribe(
        audioURL: URL,
        apiKey: String,
        customTerms: [String] = [],
        language: String = "de"
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAITranscriptionClientError.missingAPIKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")

        let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])
        var body = Data()
        body.appendMultipartField(boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", data: audioData)
        body.appendMultipartField(boundary: boundary, name: "model", value: model)
        body.appendMultipartField(boundary: boundary, name: "response_format", value: "text")

        let cleanedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedLanguage.isEmpty {
            body.appendMultipartField(boundary: boundary, name: "language", value: cleanedLanguage)
        }

        if !customTerms.isEmpty {
            body.appendMultipartField(
                boundary: boundary,
                name: "prompt",
                value: "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
            )
        }

        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranscriptionClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(OpenAITranscriptionErrorResponse.self, from: data))?.error?.message
            throw OpenAITranscriptionClientError.apiError(message ?? "Status \(httpResponse.statusCode)")
        }

        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw OpenAITranscriptionClientError.emptyTranscript
        }

        return text
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func appendMultipartField(
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}

