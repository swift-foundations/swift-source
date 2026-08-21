extension Source {
    public struct Measurement: Sendable {
        public let engine: Engine.ID
        public let subject: Subject
        public let activeRules: [Rule.ID]
        public let applicableRules: [Rule.ID]
        public let files: [Swift.String]
        public let verdict: Verdict

        public init(
            engine: Engine.ID,
            subject: Subject,
            activeRules: [Rule.ID],
            applicableRules: [Rule.ID],
            files: [Swift.String],
            verdict: Verdict
        ) {
            self.engine = engine
            self.subject = subject
            self.activeRules = activeRules
            self.applicableRules = applicableRules
            self.files = files.sorted()
            self.verdict = verdict
        }
    }
}
