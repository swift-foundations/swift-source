extension Source.Engine.Driver {
    public static func swiftFormat(process: Source.Engine.Process) -> Self {
        let id = Source.Engine.ID("swift-format")
        return Self(
            id: id,
            measure: { subject, profile in
                let files = sourceSwiftFormatFiles(subject)
                let result = await process.run(
                    profile.executable,
                    ["lint", "--strict", "--configuration", profile.configurationPath] + files,
                    subject.root,
                    profile.environment
                )
                return Source.Measurement.swiftFormat(
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

internal func sourceSwiftFormatFiles(_ subject: Source.Subject) -> [Swift.String] {
    subject.paths(of: .swift).map { file in
        if file.hasPrefix("/") { return file }
        if subject.root.hasSuffix("/") { return subject.root + file }
        return subject.root + "/" + file
    }.sorted()
}
