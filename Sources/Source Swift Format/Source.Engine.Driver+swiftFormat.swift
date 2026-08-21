extension Source.Engine.Driver {
    public static func swiftFormat(process: Source.Engine.Process) -> Self {
        let id = Source.Engine.ID("swift-format")
        return Self(
            id: id,
            measure: { subject, profile in
                let result = await process.run(
                    profile.executable,
                    ["lint", "--strict", "--recursive", subject.root],
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
                    refusals: [.init(code: "unsupported", detail: "format proposal unavailable")]
                )
            }
        )
    }
}
