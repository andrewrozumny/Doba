import Foundation

/// One task as returned by the Claude NL parser (Phase 4). This is the JSON
/// contract the model must follow — see the system prompt in DobaApp's
/// ClaudeClient. All fields except `title` are optional so a sparse model
/// response still decodes. A multi-day range is expressed as **several**
/// `ParsedTask`s (one per day, each with its own `scheduledDate`), matching the
/// "expand ranges into N atomic tasks" decision (DECISIONS D9).
public struct ParsedTask: Codable, Sendable, Equatable {
    public var title: String
    public var project: String?
    public var estimatedHours: Double?
    public var scheduledTime: String?   // "HH:mm" (24h), or nil = floating
    public var billable: Bool?
    public var scheduledDate: String?   // "yyyy-MM-dd", or nil = today

    public init(
        title: String,
        project: String? = nil,
        estimatedHours: Double? = nil,
        scheduledTime: String? = nil,
        billable: Bool? = nil,
        scheduledDate: String? = nil
    ) {
        self.title = title
        self.project = project
        self.estimatedHours = estimatedHours
        self.scheduledTime = scheduledTime
        self.billable = billable
        self.scheduledDate = scheduledDate
    }
}

/// Wrapper matching the `{ "tasks": [ ... ] }` object the model returns.
public struct ParsedTaskList: Codable, Sendable {
    public var tasks: [ParsedTask]
    public init(tasks: [ParsedTask]) { self.tasks = tasks }
}
