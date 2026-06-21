import Foundation

enum BlitztextTextImprovementError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API Key fehlt."
        case .invalidResponse:
            return "Ungültige Antwort von OpenAI."
        case .apiError(let message):
            return "OpenAI-Fehler: \(message)"
        case .emptyResult:
            return "Keine verbesserte Fassung erhalten."
        }
    }
}

/// Überarbeitet ein Diktat-Transkript per OpenAI Chat Completions:
/// korrigiert, verbessert Formulierungen und kürzt – ohne den Sinn zu verändern.
/// Analog zum LLMService der Mac-App (gpt-4o-mini).
enum BlitztextTextImprovementClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o-mini"

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let choices: [Choice]?
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable { let message: String? }
        let error: APIError?
    }

    static func improve(
        text: String,
        apiKey: String,
        customTerms: [String] = []
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw BlitztextTextImprovementError.missingAPIKey }

        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return source }

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: buildSystemPrompt(customTerms: customTerms)),
                .init(role: "user", content: source)
            ],
            temperature: 0.3
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlitztextTextImprovementError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
            throw BlitztextTextImprovementError.apiError(message ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw BlitztextTextImprovementError.emptyResult
        }
        return content
    }

    private static func buildSystemPrompt(customTerms: [String]) -> String {
        var prompt = """
        Du bist ein Lektor und Schreibassistent. Du erhältst ein gesprochenes Diktat-Transkript. Überarbeite es:
        - Korrigiere Rechtschreibung, Grammatik und Zeichensetzung
        - Verbessere Formulierung und Lesefluss
        - Kürze Wiederholungen, Füllwörter und Abschweifungen; fasse dich knapp und präzise
        - Behalte Sinn, Kernaussagen und Absicht unbedingt vollständig bei
        - Behalte die Sprache des Originals bei
        - Erfinde keine neuen Inhalte
        - Gib NUR den überarbeiteten Text zurück: keine Erklärungen, keine Anführungszeichen, keine Einleitung
        """
        if !customTerms.isEmpty {
            prompt += "\n\nDiese Eigennamen und Fachbegriffe müssen exakt so geschrieben werden: \(customTerms.joined(separator: ", "))"
        }
        return prompt
    }
}
