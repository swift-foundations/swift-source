extension Source.Engine.Driver {
    public static func swiftLint(process: Source.Engine.Process) -> Self {
        let id = Source.Engine.ID("swiftlint")
        return Self(
            id: id,
            measure: { subject, profile in
                let result = await process.run(
                    profile.executable,
                    ["lint", "--strict", "--reporter", "xcode", "--path", subject.root],
                    subject.root
                )
                return Source.Measurement.external(
                    engine: id,
                    subject: subject,
                    rules: profile.rules,
                    status: result.status,
                    output: result.output,
                    diagnostics: result.diagnostics
                )
            },
            repair: { _, _ in
                .init(
                    edits: [],
                    refusals: [.init(code: "unsupported", detail: "SwiftLint proposal unavailable")]
                )
            }
        )
    }
}
