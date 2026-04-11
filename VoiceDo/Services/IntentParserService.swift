import Foundation
import NaturalLanguage
import os.log
import VoiceDoShared

// MARK: - ParseError

enum ParseError: Error, LocalizedError {
    case emptyTranscript
    case claudeAPIError(ClaudeAPIError)
    case claudeResponseMalformed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Nothing was transcribed. Please try speaking again."
        case .claudeAPIError(let err):
            return err.errorDescription
        case .claudeResponseMalformed(let detail):
            return "Could not parse AI response: \(detail)"
        }
    }
}

// MARK: - IntentParsing Protocol

protocol IntentParsing: Sendable {
    func parse(transcript: String) async throws -> ParsedIntent
}

// MARK: - IntentParserService

final class IntentParserService: IntentParsing {

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "IntentParser")
    private let offlineParser = OfflineIntentParser()
    private let claudeService: ClaudeAPIService

    init(claudeService: ClaudeAPIService = ClaudeAPIService()) {
        self.claudeService = claudeService
    }

    func parse(transcript: String) async throws -> ParsedIntent {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyTranscript }

        var intent = offlineParser.parse(transcript: trimmed)
        logger.info("Offline parse: type=\(intent.type.rawValue), confidence=\(intent.confidence)")

        // Always call Claude when an API key is configured.
        // Claude summarises the title and generates the message body in a single call —
        // the result view only appears after this completes, so the item is always
        // created with fully AI-processed content.
        guard APIKeyManager.hasKey() else {
            logger.info("No API key configured — using offline result only")
            return intent
        }

        logger.info("Calling Claude API for title + message body generation")
        do {
            let claudeResult = try await claudeService.refineIntent(
                transcript: trimmed,
                offlineTitle: intent.title,
                offlineIntent: intent.type.rawValue
            )
            intent = merge(offline: intent, claude: claudeResult, transcript: trimmed)
            logger.info("Claude refinement applied. confidence=\(intent.confidence)")
        } catch {
            logger.error("Claude call failed: \(error.localizedDescription)")
            // Keep the offline-parsed title and metadata.
            // Flag that message body generation failed so the UI can inform the user.
            intent.messageBodyError = friendlyError(from: error)
        }

        return intent
    }

    // MARK: - Error Localisation

    private func friendlyError(from error: Error) -> String {
        if let apiError = error as? ClaudeAPIError {
            switch apiError {
            case .missingAPIKey:
                return "No API key configured — add your key in Settings."
            case .timeout:
                return "Request timed out. Check your connection and try again."
            case .networkError:
                return "No internet connection. Connect and re-save to regenerate."
            case .httpError(let code, _):
                return "API error (HTTP \(code)). Check your API key in Settings."
            default:
                return "Could not generate message draft (\(apiError.localizedDescription))."
            }
        }
        return "Could not generate message draft. Please try again."
    }

    // MARK: - Merge

    private func merge(
        offline: ParsedIntent,
        claude: ClaudeIntentResponse,
        transcript: String
    ) -> ParsedIntent {
        let intentType: ParsedIntent.IntentType
        switch claude.intent {
        case "todo": intentType = .todo
        case "reminder": intentType = .reminder
        default: intentType = offline.type
        }

        var dueDate: Date? = offline.detectedDueDate
        if let dueDateStr = claude.dueDate {
            let formatter = ISO8601DateFormatter()
            if let parsed = formatter.date(from: dueDateStr) {
                dueDate = OfflineIntentParser.roundToNearest30(parsed)
            }
        }

        let taskType: AssociatedTaskType?
        if let rawType = claude.taskType {
            taskType = AssociatedTaskType(rawValue: rawType) ?? offline.detectedTaskType
        } else {
            taskType = offline.detectedTaskType
        }

        let category: TaskCategory
        if let rawCat = claude.category, let parsed = TaskCategory(rawValue: rawCat) {
            category = parsed
        } else {
            category = offline.detectedCategory
        }

        let workspace: Workspace
        if let rawWs = claude.workspace, let parsed = Workspace(rawValue: rawWs) {
            workspace = parsed
        } else {
            workspace = offline.detectedWorkspace
        }

        return ParsedIntent(
            type: intentType,
            confidence: claude.confidence,
            title: claude.title.isEmpty ? offline.title : claude.title,
            notes: claude.notes ?? offline.notes,
            detectedDueDate: dueDate,
            detectedTaskType: taskType,
            detectedCategory: category,
            detectedWorkspace: workspace,
            recipientHint: claude.recipientHint ?? offline.recipientHint,
            platformHint: claude.platformHint ?? offline.platformHint,
            messageContextNotes: offline.messageContextNotes,
            messageSubject: claude.messageSubject,
            generatedMessageBody: claude.messageBody.map { ClaudeAPIService.htmlToPlainText($0) }
        )
    }
}

// MARK: - OfflineIntentParser

final class OfflineIntentParser: Sendable {

    // MARK: - Keyword Sets

    private let messageKeywords = [
        "email", "e-mail", "write to", "draft", "message to", "send to",
        "whatsapp", "text to", "ping", "slack", "sms to", "reach out"
    ]
    private let purchaseKeywords = [
        "buy", "order", "get", "pick up", "purchase", "grab", "shop for",
        "groceries", "grocery", "supermarket"
    ]
    private let deadlineKeywords = [
        "deadline", "due by", "submit", "hand in", "deliver by", "due on"
    ]
    private let callKeywords = [
        "call", "phone", "ring", "dial", "video call", "facetime"
    ]
    private let reminderSignals = [
        "remind me", "don't forget", "remember to", "reminder", "make sure"
    ]
    private let workKeywords = [
        "work", "office", "meeting", "client", "boss", "project",
        "colleague", "team", "presentation", "report", "manager"
    ]
    private let homeKeywords = [
        "home", "house", "family", "mom", "dad", "kitchen",
        "garden", "kids", "dinner", "laundry"
    ]

    // MARK: - Date Detector

    private let dataDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    // MARK: - Round to nearest 30 minutes

    /// Rounds a detected date UP to the nearest 30-minute mark.
    /// e.g. 3:22 pm → 3:30 pm, 3:31 pm → 4:00 pm, 4:00 pm → 4:00 pm (unchanged).
    static func roundToNearest30(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let minutesPast = minute % 30
        let hasStraySeconds = second > 0

        if minutesPast == 0 && !hasStraySeconds { return date }

        let minutesToAdd = 30 - minutesPast
        guard let rounded = calendar.date(byAdding: .minute, value: minutesToAdd, to: date) else {
            return date
        }
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rounded)
        comps.second = 0
        return calendar.date(from: comps) ?? rounded
    }

    // MARK: - Quick Parse (category + workspace only, no date detection)

    /// Lightweight re-categorisation used by pull-to-refresh.
    /// Skips date detection and title extraction — just returns category + workspace.
    static func quickParse(_ transcript: String) -> (category: TaskCategory, workspace: Workspace) {
        let instance = OfflineIntentParser()
        let lower = transcript.lowercased()
        let taskType = instance.detectTaskType(in: lower)
        let category = instance.deriveCategory(from: taskType)
        let workspace = instance.detectWorkspace(in: lower)
        return (category: category, workspace: workspace)
    }

    // MARK: - Parse

    func parse(transcript: String) -> ParsedIntent {
        let lower = transcript.lowercased()

        let taskType = detectTaskType(in: lower)
        let platformHint = detectPlatformHint(in: lower)
        let recipientHint = extractRecipientHint(from: transcript, taskType: taskType)
        let dueDate = detectDate(in: transcript)
        let intentType = determineIntent(lower: lower, dueDate: dueDate)
        let title = extractTitle(from: transcript, taskType: taskType, dueDate: dueDate)
        let messageContext = taskType == .message ? extractMessageContext(from: transcript) : nil
        let category = deriveCategory(from: taskType)
        let workspace = detectWorkspace(in: lower)
        let confidence = computeConfidence(
            intentType: intentType,
            dueDate: dueDate,
            taskType: taskType,
            titleLength: title.count
        )

        return ParsedIntent(
            type: intentType,
            confidence: confidence,
            title: title,
            notes: nil,
            detectedDueDate: dueDate,
            detectedTaskType: taskType,
            detectedCategory: category,
            detectedWorkspace: workspace,
            recipientHint: recipientHint,
            platformHint: platformHint,
            messageContextNotes: messageContext,
            messageSubject: nil,
            generatedMessageBody: nil
        )
    }

    // MARK: - Private Helpers

    private func detectTaskType(in lower: String) -> AssociatedTaskType? {
        if messageKeywords.contains(where: { lower.contains($0) }) { return .message }
        if purchaseKeywords.contains(where: { lower.contains($0) }) { return .purchase }
        if deadlineKeywords.contains(where: { lower.contains($0) }) { return .deadline }
        if callKeywords.contains(where: { lower.contains($0) }) { return .call }
        return nil
    }

    private func deriveCategory(from taskType: AssociatedTaskType?) -> TaskCategory {
        switch taskType {
        case .message: return .message
        case .purchase: return .grocery
        case .deadline: return .deadline
        case .call: return .call
        case .other, nil: return .task
        }
    }

    private func detectWorkspace(in lower: String) -> Workspace {
        if workKeywords.contains(where: { lower.contains($0) }) { return .work }
        if homeKeywords.contains(where: { lower.contains($0) }) { return .home }
        return .personal
    }

    private func detectPlatformHint(in lower: String) -> String? {
        if lower.contains("whatsapp") { return "whatsapp" }
        if lower.contains("slack") { return "slack" }
        if lower.contains("imessage") || lower.contains("i message") { return "imessage" }
        if lower.contains("sms") || lower.contains("text message") { return "sms" }
        if lower.contains("email") || lower.contains("e-mail") { return "email" }
        return nil
    }

    private func detectDate(in transcript: String) -> Date? {
        if let detector = dataDetector {
            let range = NSRange(transcript.startIndex..., in: transcript)
            let matches = detector.matches(in: transcript, options: [], range: range)
            if let first = matches.first(where: { $0.date != nil }), let date = first.date {
                return Self.roundToNearest30(date)
            }
        }
        return parseRelativeDate(from: transcript.lowercased())
    }

    private func parseRelativeDate(from lower: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        if lower.contains("tonight") {
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
        }
        if lower.contains("this morning") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)
        }
        if let match = lower.range(of: #"in (\d+) hours?"#, options: .regularExpression) {
            let matchStr = String(lower[match])
            if let num = matchStr.components(separatedBy: " ").dropFirst().first.flatMap(Int.init) {
                let base = calendar.date(byAdding: .hour, value: num, to: now)
                return base.map { Self.roundToNearest30($0) }
            }
        }
        if let match = lower.range(of: #"in (\d+) days?"#, options: .regularExpression) {
            let matchStr = String(lower[match])
            if let num = matchStr.components(separatedBy: " ").dropFirst().first.flatMap(Int.init) {
                return calendar.date(byAdding: .day, value: num, to: now)
            }
        }
        if lower.contains("end of week") || lower.contains("end of the week") {
            return nextWeekday(.friday, hour: 17, from: now)
        }
        if lower.contains("next week") {
            return nextWeekday(.monday, hour: 9, from: now)
        }
        return nil
    }

    private func nextWeekday(_ weekday: Calendar.Weekday, hour: Int, from date: Date) -> Date? {
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: date)
        let targetWeekday = weekday.rawValue
        var daysUntil = targetWeekday - todayWeekday
        if daysUntil <= 0 { daysUntil += 7 }
        guard let nextDay = calendar.date(byAdding: .day, value: daysUntil, to: date) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: nextDay)
    }

    private func determineIntent(lower: String, dueDate: Date?) -> ParsedIntent.IntentType {
        if dueDate != nil { return .reminder }
        if reminderSignals.contains(where: { lower.contains($0) }) { return .reminder }
        return .todo
    }

    private func extractTitle(
        from transcript: String,
        taskType: AssociatedTaskType?,
        dueDate: Date?
    ) -> String {
        var text = transcript

        if let detector = dataDetector {
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, options: [], range: range)
            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: text) {
                    text = text.replacingCharacters(in: swiftRange, with: "")
                }
            }
        }

        let prefixesToStrip = [
            "remind me to ", "remind me ", "don't forget to ", "don't forget ",
            "remember to ", "remember ", "i need to ", "i have to ", "make sure to ",
            "make sure ", "please ", "can you "
        ]
        var lower = text.lowercased()
        for prefix in prefixesToStrip where lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            lower = text.lowercased()
            break
        }

        text = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")

        if text.isEmpty { return transcript }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func extractRecipientHint(from transcript: String, taskType: AssociatedTaskType?) -> String? {
        guard taskType == .message || taskType == .call else { return nil }
        let contactPattern = #"(?:email|message|text|whatsapp|slack|write to|send to|call|phone|ring)"#
            + #"\s+(?:to\s+)?([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"#
        let patterns = [
            contactPattern,
            #"(?:email|message|text|call)\s+my\s+([a-z]+(?:\s+[a-z]+)?)"#
        ]
        for pattern in patterns {
            if let match = transcript.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let matchStr = String(transcript[match])
                let words = matchStr.components(separatedBy: " ")
                if words.count >= 2 {
                    let candidate = words.dropFirst().joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty { return candidate }
                }
            }
        }
        return nil
    }

    private func extractMessageContext(from transcript: String) -> String? {
        let contextMarkers = ["about ", "regarding ", "saying ", "mention ", "to say "]
        let lower = transcript.lowercased()
        for marker in contextMarkers {
            if let range = lower.range(of: marker) {
                let contextStart = transcript.index(
                    transcript.startIndex,
                    offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound)
                )
                let context = String(transcript[contextStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !context.isEmpty { return context }
            }
        }
        return transcript
    }

    private func computeConfidence(
        intentType: ParsedIntent.IntentType,
        dueDate: Date?,
        taskType: AssociatedTaskType?,
        titleLength: Int
    ) -> Double {
        var score = 0.5
        if dueDate != nil { score += 0.2 }
        if taskType != nil { score += 0.1 }
        if titleLength > 5 { score += 0.1 }
        if intentType != .ambiguous { score += 0.05 }
        return min(score, 1.0)
    }
}

// MARK: - Calendar.Weekday Extension

private extension Calendar {
    enum Weekday: Int {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    }
}
