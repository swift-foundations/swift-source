extension Source.Report {
    public var human: Swift.String {
        var lines = [
            "source profile \(profile.hex)",
            "scope: \(scope.rawValue)",
            "subjects: \(subjects.count)",
        ]
        for reason in references {
            lines.append("UNMEASURED reference \(reason.code): \(reason.detail)")
        }
        for measurement in measurements {
            switch measurement.verdict {
            case .clean:
                lines.append("CLEAN \(measurement.subject.identity) \(measurement.engine.token)")
            case .findings(let findings):
                lines.append(
                    "FINDINGS \(measurement.subject.identity) \(measurement.engine.token) \(findings.count)"
                )
            case .unmeasured(let reasons):
                for reason in reasons {
                    lines.append(
                        "UNMEASURED \(measurement.subject.identity) \(measurement.engine.token) \(reason.code): \(reason.detail)"
                    )
                }
            case .notRequested:
                lines.append(
                    "NOT REQUESTED \(measurement.subject.identity) \(measurement.engine.token)"
                )
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
