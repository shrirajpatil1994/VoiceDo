import Foundation
import os.log
import VoiceDoShared

// MARK: - ClaudeAPIError

enum ClaudeAPIError: Error, LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key configured. Add your key in Settings."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .httpError(let code, let body):
            // Extract Anthropic's error message from the JSON body when available.
            let detail = Self.extractAnthropicMessage(from: body)
            switch code {
            case 400:
                return "Bad request (400)\(detail). Check model name and request format."
            case 401, 403:
                return "Invalid API key (\(code))\(detail). Update your key in Settings."
            case 429:
                return "Rate limit exceeded (429)\(detail). Try again in a moment."
            case 500...599:
                return "Anthropic server error (\(code))\(detail). Try again later."
            default:
                return "Claude API error (\(code))\(detail)."
            }
        case .decodingError:
            return "Could not parse Claude's response."
        case .timeout:
            return "Claude API timed out. Using offline result."
        case .invalidResponse:
            return "Claude returned an unexpected response format."
        }
    }

    /// Pulls the `message` field out of Anthropic's standard error JSON, e.g.:
    /// `{"type":"error","error":{"type":"invalid_request_error","message":"..."}}`.
    /// Returns `": <message>"` if found, empty string otherwise.
    private static func extractAnthropicMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty else { return "" }
        return ": \(message.prefix(120))"
    }
}

// MARK: - Claude Request / Response Models

private struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

/// The structured JSON Claude returns inside its text block.
struct ClaudeIntentResponse: Decodable {
    let intent: String          // "todo" | "reminder" | "ambiguous"
    let title: String
    let notes: String?
    let dueDate: String?        // ISO8601 or nil
    let taskType: String?       // raw AssociatedTaskType value or nil
    let category: String?       // raw TaskCategory value
    let workspace: String?      // raw Workspace value
    let platformHint: String?
    let recipientHint: String?
    let messageSubject: String?
    let messageBody: String?
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case intent, title, notes, confidence, category, workspace
        case dueDate = "due_date"
        case taskType = "task_type"
        case platformHint = "platform_hint"
        case recipientHint = "recipient_hint"
        case messageSubject = "message_subject"
        case messageBody = "message_body"
    }
}

// MARK: - ClaudeAPIService

/// Sends voice transcripts to the Claude API for intent parsing and message body generation.
/// Always called with a timeout — falls back to offline parse on failure.
final class ClaudeAPIService: Sendable {

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "ClaudeAPIService")
    private let session: URLSession
    /// Override the timeout for unit tests. Uses `AppConstants.claudeTimeoutSeconds` when nil.
    let timeoutOverride: Double?

    init(session: URLSession = .shared, timeoutOverride: Double? = nil) {
        self.session = session
        self.timeoutOverride = timeoutOverride
    }

    private var effectiveTimeout: Double {
        timeoutOverride ?? AppConstants.claudeTimeoutSeconds
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        let isoDate = ISO8601DateFormatter().string(from: Date())
        let timezone = TimeZone.current.identifier
        return """
        You are a productivity assistant that parses voice-dictated text into structured actions.
        Return ONLY the raw JSON object — no explanation, no markdown, no code fences, no text before or after the JSON.

        Schema:
        {
          "intent": "todo" | "reminder" | "ambiguous",
          "title": "concise action title (≤60 chars)",
          "notes": "additional context or null",
          "due_date": "ISO8601 datetime string or null",
          "task_type": "message" | "purchase" | "deadline" | "call" | "other" | null,
          "category": "grocery" | "task" | "deadline" | "call" | "message" | "other",
          "workspace": "personal" | "work" | "home",
          "platform_hint": "email" | "whatsapp" | "slack" | "sms" | "imessage" | null,
          "recipient_hint": "informal recipient name/description or null",
          "message_subject": "subject line for the message, or null",
          "message_body": "full drafted message body if task_type is 'message', else null",
          "confidence": 0.0 to 1.0
        }

        Rules:
        - If a date/time is mentioned, set intent to "reminder" and parse due_date.
        - If a messaging action is detected (email, WhatsApp, text, etc.), set task_type to "message".
        - Summarise the dictation into a meaningful title (≤60 chars) that captures the core action — not a verbatim excerpt. Example: "remind me to email my landlord about the broken heating" → "Email landlord about broken heating".
        - For message tasks, write a complete, professional message_body using the full context from the dictation. The message_body must be plain text only — no HTML tags, no markdown, no bullet symbols. Use plain newline characters for paragraph breaks. Good: "Dear Sarah,\\n\\nJust following up on the deadline.\\n\\nBest regards" — Bad: "<p>Dear Sarah,</p><br/>Just following up."
        - If you cannot determine intent, set intent to "ambiguous" and confidence below 0.5.
        - Never include personal data beyond what was dictated.

        Current date/time: \(isoDate)
        User timezone: \(timezone)
        """
    }

    // MARK: - Refine Intent

    /// Call Claude to refine an offline-parsed intent.
    /// - Parameters:
    ///   - transcript: The raw voice transcript.
    ///   - offlineIntent: The offline parse result (used to build the user message).
    /// - Returns: `ClaudeIntentResponse` on success.
    /// - Throws: `ClaudeAPIError` on any failure (callers should fall back to offline result).
    func refineIntent(
        transcript: String,
        offlineTitle: String,
        offlineIntent: String
    ) async throws -> ClaudeIntentResponse {
        guard let apiKey = try? APIKeyManager.retrieve() else {
            throw ClaudeAPIError.missingAPIKey
        }
        let userMessage = """
        Voice dictation: "\(transcript)"
        Offline parser detected: intent=\(offlineIntent), title="\(offlineTitle)"
        Please parse this and return the structured JSON.
        """
        let request = try buildRequest(userMessage: userMessage, apiKey: apiKey)
        let (data, response) = try await executeWithTimeout(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            logger.error("Claude HTTP \(httpResponse.statusCode): \(bodyString.prefix(200))")
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }
        return try decodeIntentResponse(from: data)
    }

    private func buildRequest(userMessage: String, apiKey: String) throws -> URLRequest {
        let requestBody = ClaudeRequest(
            model: AppConstants.claudeModel,
            maxTokens: 1024,
            system: buildSystemPrompt(),
            messages: [ClaudeMessage(role: "user", content: userMessage)]
        )
        guard let url = URL(string: AppConstants.claudeAPIEndpoint) else {
            throw ClaudeAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = effectiveTimeout
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw ClaudeAPIError.networkError(error)
        }
        return request
    }

    private func executeWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { try await self.session.data(for: request) }
                group.addTask {
                    try await Task.sleep(for: .seconds(self.effectiveTimeout))
                    throw ClaudeAPIError.timeout
                }
                guard let result = try await group.next() else { throw ClaudeAPIError.timeout }
                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            throw ClaudeAPIError.timeout
        } catch let err as ClaudeAPIError {
            throw err
        } catch {
            throw ClaudeAPIError.networkError(error)
        }
    }

    private func decodeIntentResponse(from data: Data) throws -> ClaudeIntentResponse {
        do {
            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
                  let rawText = textBlock.text else {
                throw ClaudeAPIError.invalidResponse
            }

            // Sanitise Claude's text before JSON-decoding — handles code fences,
            // preamble text, and any trailing explanation.
            let cleaned = Self.extractJSON(from: rawText)
            logger.debug("Claude response text (first 300 chars): \(cleaned.prefix(300))")

            guard let jsonData = cleaned.data(using: .utf8) else {
                throw ClaudeAPIError.invalidResponse
            }
            let intentResponse = try JSONDecoder().decode(ClaudeIntentResponse.self, from: jsonData)
            logger.info("Claude refined intent: \(intentResponse.intent), confidence: \(intentResponse.confidence)")
            return intentResponse
        } catch {
            logger.error("Claude response decode error: \(error.localizedDescription)")
            throw ClaudeAPIError.decodingError(error)
        }
    }

    // MARK: - JSON Extraction

    /// Strips markdown code fences and any preamble/postamble text so that
    /// only the bare JSON object remains. Handles:
    ///   • ` ```json { ... } ``` `
    ///   • ` ``` { ... } ``` `
    ///   • Plain text before/after the `{…}` object
    static func extractJSON(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip opening fence line (`json, ```, etc.)
        if s.hasPrefix("```") {
            if let newline = s.range(of: "\n") {
                s = String(s[newline.upperBound...])
            }
            // Strip closing fence
            if let closeFence = s.range(of: "```", options: .backwards) {
                s = String(s[..<closeFence.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If there is still non-JSON preamble, extract from first '{' to last '}'
        if !s.hasPrefix("{"),
           let start = s.firstIndex(of: "{"),
           let end = s.lastIndex(of: "}") {
            s = String(s[start...end])
        }

        return s
    }

    // MARK: - HTML → Plain Text

    /// Converts HTML that Claude may emit in message_body to clean, copy-pasteable
    /// plain text. Block tags become newlines; all other tags are stripped;
    /// common HTML entities are decoded.
    static func htmlToPlainText(_ html: String) -> String {
        var s = html

        // Block-level tags → newline
        let blockPatterns = ["</p>", "<br>", "<br/>", "<br />", "</div>",
                             "</li>", "</h1>", "</h2>", "</h3>",
                             "<p>", "<p ", "<div>", "<li>"]
        for tag in blockPatterns {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Strip all remaining tags
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        s = s
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&lt;",    with: "<")
            .replacingOccurrences(of: "&gt;",    with: ">")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&#39;",   with: "'")
            .replacingOccurrences(of: "&apos;",  with: "'")

        // Collapse 3+ consecutive newlines to at most 2
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
