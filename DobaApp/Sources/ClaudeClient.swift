import Foundation
import DobaKit

/// Turns natural-language text into structured tasks via the Claude API.
/// Raw HTTPS (no Swift SDK exists) against POST /v1/messages, model
/// claude-haiku-4-5-20251001 (cheap, sufficient — see DECISIONS D21). The
/// system prompt forces a JSON-only `{"tasks":[...]}` reply; we parse it
/// defensively (strip fences, slice to the JSON object) so a stray sentence
/// doesn't break things.
enum ClaudeClient {
    /// Bump to "claude-sonnet-4-6" if range parsing proves weak.
    static let model = "claude-haiku-4-5-20251001"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ParseError: LocalizedError {
        case missingKey
        case http(Int, String)
        case badResponse
        case noJSON

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No API key. Add it in settings (the gear icon)."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " — \(body.prefix(180))"
                return "Claude API error \(code)\(detail)"
            case .badResponse: return "Unexpected response from the Claude API."
            case .noJSON: return "Couldn't read tasks from the model's reply."
            }
        }
    }

    /// Parse `text` into tasks. `now` is injected so the model can resolve
    /// relative dates ("Mon–Fri") to absolute ones.
    static func parse(_ text: String, now: Date = Date(), knownProjects: [String] = []) async throws -> [ParsedTask] {
        guard let key = Keychain.apiKey, !key.isEmpty else { throw ParseError.missingKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt(now: now, knownProjects: knownProjects),
            "messages": [["role": "user", "content": text]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ParseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ParseError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let message = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let replyText = message.content.first { $0.type == "text" }?.text ?? ""
        guard let jsonData = extractJSONObject(from: replyText) else { throw ParseError.noJSON }
        return try JSONDecoder().decode(ParsedTaskList.self, from: jsonData).tasks
    }

    // MARK: - Response shape

    private struct MessagesResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    // MARK: - System prompt

    private static func systemPrompt(now: Date, knownProjects: [String]) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd (EEEE)"
        let todayLine = df.string(from: now)

        let projectsHint = knownProjects.isEmpty ? "" : """


        The user's existing projects are: \(knownProjects.joined(separator: ", ")). \
        When a project/client is mentioned, prefer matching it to one of these — \
        including abbreviations and transliterations (e.g. "nw"/"норт" → \
        "Northwind") — and return that EXACT existing name. Only invent a new \
        project name if none clearly fits.
        """

        return """
        You convert a freelancer's natural-language note into structured tasks. \
        The note may be in any language (often Russian or English).

        Today is \(todayLine). Resolve relative dates ("today", "Mon–Fri", \
        "next week") to absolute calendar dates relative to today.\(projectsHint)

        Reply with ONLY a JSON object, no prose and no markdown code fences:
        {"tasks": [ { ...task... }, ... ]}

        Each task object has these fields:
        - "title": string (required) — short task name, without the metadata.
        - "project": string or null — the project/client name if mentioned.
        - "estimatedHours": number or null — planned hours if stated (e.g. "2ч"→2, "30 min"→0.5).
        - "scheduledTime": string "HH:mm" (24-hour) or null — only if a clock time is given.
        - "billable": boolean — true only if the note says it's billable/paid; otherwise false.
        - "scheduledDate": string "yyyy-MM-dd" — the day; default to today if none is given.

        For a multi-day range ("6h/day Mon–Fri"), output ONE task object PER DAY, \
        each with its own scheduledDate and the per-day hours.

        Examples:
        Input: "подготовить эстимейт для Acme, 2ч, оплачиваемо"
        Output: {"tasks":[{"title":"Подготовить эстимейт","project":"Acme","estimatedHours":2,"scheduledTime":null,"billable":true,"scheduledDate":"\(DateFormatter.localizedDay(now))"}]}

        Input: "созвон в 10:30"
        Output: {"tasks":[{"title":"Созвон","project":null,"estimatedHours":null,"scheduledTime":"10:30","billable":false,"scheduledDate":"\(DateFormatter.localizedDay(now))"}]}
        """
    }

    // MARK: - Defensive JSON extraction

    /// Pull the JSON object out of the model's reply: strip code fences, then
    /// slice from the first "{" to the matching last "}".
    private static func extractJSONObject(from text: String) -> Data? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Drop the opening fence line and any trailing fence.
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let fence = s.range(of: "```", options: .backwards) {
                s = String(s[..<fence.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let open = s.firstIndex(of: "{"), let close = s.lastIndex(of: "}"), open < close else {
            return nil
        }
        return String(s[open...close]).data(using: .utf8)
    }
}

private extension DateFormatter {
    /// "yyyy-MM-dd" for `date` in the current calendar's time zone — used in the
    /// prompt examples so the model copies the right format.
    static func localizedDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = Calendar.current.timeZone
        return df.string(from: date)
    }
}
