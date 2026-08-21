extension Source.Report {
    public struct Complete: Sendable {
        public let report: Source.Report

        public init(_ report: Source.Report, required engines: Set<Source.Engine.ID>) throws(Error) {
            guard report.scope == .workspace else { throw .partial }
            guard report.references.isEmpty else { throw .references }

            for subject in report.subjects {
                let measurements = report.measurements.filter { $0.subject.identity == subject.identity }
                guard Set(measurements.map(\.engine)) == engines else { throw .engines(subject.identity) }
                for measurement in measurements {
                    guard !measurement.files.isEmpty,
                        !measurement.activeRules.isEmpty,
                        !measurement.applicableRules.isEmpty
                    else { throw .coverage(subject.identity) }
                    switch measurement.verdict {
                    case .clean, .findings: break
                    case .unmeasured, .notRequested: throw .coverage(subject.identity)
                    }
                }
            }
            self.report = report
        }
    }
}
