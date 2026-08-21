extension Source.Measurement {
    public static func external(
        engine: Source.Engine.ID,
        subject: Source.Subject,
        rules: [Source.Rule.ID],
        status: Swift.Int32,
        output: Swift.String,
        diagnostics: Swift.String
    ) -> Self {
        guard !subject.files.isEmpty else {
            return Self(
                engine: engine,
                subject: subject,
                activeRules: rules,
                applicableRules: [],
                files: [],
                verdict: .unmeasured([.init(code: "zero-files", detail: "no source files")])
            )
        }
        guard !rules.isEmpty else {
            return Self(
                engine: engine,
                subject: subject,
                activeRules: [],
                applicableRules: [],
                files: subject.files,
                verdict: .unmeasured([.init(code: "zero-rules", detail: "no active rules")])
            )
        }
        guard status == 0 || status == 1 else {
            return Self(
                engine: engine,
                subject: subject,
                activeRules: rules,
                applicableRules: rules,
                files: subject.files,
                verdict: .unmeasured([
                    .init(
                        code: "engine-status",
                        detail: "status \(status): \(diagnostics)"
                    )
                ])
            )
        }

        let lines = output.split(separator: "\n").map(Swift.String.init)
        if lines.isEmpty {
            return Self(
                engine: engine,
                subject: subject,
                activeRules: rules,
                applicableRules: rules,
                files: subject.files,
                verdict: status == 0
                    ? .clean
                    : .unmeasured([
                        .init(code: "missing-output", detail: "finding status without output")
                    ])
            )
        }

        var findings: [Source.Finding] = []
        for line in lines {
            let fields = line.split(separator: ":", maxSplits: 4).map(Swift.String.init)
            guard fields.count == 5,
                let lineNumber = Swift.Int(fields[1]),
                let column = Swift.Int(fields[2])
            else {
                return Self(
                    engine: engine,
                    subject: subject,
                    activeRules: rules,
                    applicableRules: rules,
                    files: subject.files,
                    verdict: .unmeasured([
                        .init(code: "malformed-output", detail: line)
                    ])
                )
            }
            findings.append(
                .init(
                    rule: rules[0],
                    diagnostic: .init(
                        location: .init(
                            fileID: fields[0],
                            filePath: fields[0],
                            line: lineNumber,
                            column: column
                        ),
                        severity: fields[3].contains("error") ? .error : .warning,
                        identifier: rules[0].token,
                        message: fields[4]
                    ),
                    repair: .unavailable(
                        .init(code: "engine-repair", detail: "engine supplied no proposal")
                    )
                )
            )
        }
        return Self(
            engine: engine,
            subject: subject,
            activeRules: rules,
            applicableRules: rules,
            files: subject.files,
            verdict: .findings(findings)
        )
    }
}
