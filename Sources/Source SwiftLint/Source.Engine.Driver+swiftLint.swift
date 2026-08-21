extension Source.Engine.Driver {
  public static func swiftLint(process: Source.Engine.Process) -> Self {
    let id = Source.Engine.ID("swiftlint")
    return Self(
      id: id,
      measure: { subject, profile in
        let files = sourceSwiftLintFiles(subject)
        let result = await process.run(
          profile.executable,
                    [
                        "lint", "--strict", "--quiet", "--no-cache", "--reporter", "json",
                        "--config", profile.configurationPath,
                    ]
                        + files,
                    subject.root,
                    profile.environment
                )
        return Source.Measurement.swiftLint(
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

internal func sourceSwiftLintFiles(_ subject: Source.Subject) -> [Swift.String] {
  subject.files.map { file in
    if file.hasPrefix("/") { return file }
    if subject.root.hasSuffix("/") { return subject.root + file }
    return subject.root + "/" + file
  }.sorted()
}
