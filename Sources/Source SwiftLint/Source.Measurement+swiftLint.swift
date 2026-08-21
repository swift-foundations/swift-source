internal import JSON

extension Source.Measurement {
  public static func swiftLint(
    engine: Source.Engine.ID,
    subject: Source.Subject,
    rules: [Source.Rule.ID],
    status: Swift.Int32,
    output: Swift.String,
    diagnostics: Swift.String
  ) -> Self {
    let files = sourceSwiftLintFiles(subject)
    guard !files.isEmpty else {
      return sourceSwiftLintUnmeasured(engine, subject, rules, "zero-files", "no files")
    }
    guard !rules.isEmpty else {
      return sourceSwiftLintUnmeasured(engine, subject, rules, "zero-rules", "no rules")
    }
    guard diagnostics.isEmpty else {
      return sourceSwiftLintUnmeasured(
        engine, subject, rules, "unexpected-diagnostics", diagnostics
      )
    }
    guard status == 0 || status == 2 else {
      return sourceSwiftLintUnmeasured(
        engine, subject, rules, "engine-status", "status \(status)"
      )
    }
    do throws(Source.Reason) {
      let findings = try sourceSwiftLintFindings(
        output, engine: engine, files: files, rules: rules
      )
      guard (status == 0) == findings.isEmpty else {
        throw .init(code: "engine-status-mismatch", detail: "status and findings disagree")
      }
      let observations = files.flatMap { file in
        rules.map { rule in
          Source.Rule.Observation(
            file: file,
            rule: rule,
            applicable: true,
            coverage: .measured
          )
        }
      }
      return Self(
        engine: engine,
        subject: subject,
        activeRules: rules,
        applicableRules: rules,
        files: files,
        observations: observations,
        verdict: findings.isEmpty ? .clean : .findings(findings)
      )
    } catch {
      return sourceSwiftLintUnmeasured(engine, subject, rules, error.code, error.detail)
    }
  }
}

private func sourceSwiftLintFindings(
  _ output: Swift.String,
  engine: Source.Engine.ID,
  files: [Swift.String],
  rules: [Source.Rule.ID]
) throws(Source.Reason) -> [Source.Finding] {
  let document: JSON
  do throws(JSON.Error) { document = try JSON.parse(output) } catch {
    throw .init(code: "malformed-output", detail: Swift.String(describing: error))
  }
  guard let values = document.array else {
    throw .init(code: "malformed-output", detail: "expected SwiftLint array")
  }
  return try values.map { value in
    guard let members = value.object else {
      throw .init(code: "malformed-output", detail: "expected SwiftLint finding object")
    }
    let keys = members.map(\.key)
    let required: Swift.Set<Swift.String> = [
      "character", "file", "line", "reason", "rule_id", "severity", "type",
    ]
    guard Swift.Set(keys) == required, Swift.Set(keys).count == keys.count else {
      throw .init(code: "unconsumed-output", detail: "SwiftLint finding keys disagree")
    }
    let object = Swift.Dictionary(uniqueKeysWithValues: members.map { ($0.key, $0.value) })
    func required(_ key: Swift.String) throws(Source.Reason) -> JSON {
      guard let value = object[key] else {
        throw .init(code: "malformed-output", detail: "missing \(key)")
      }
      return value
    }
    let file = try sourceSwiftLintString(required("file"))
    let token = try sourceSwiftLintString(required("rule_id"))
    guard files.contains(file), let rule = rules.first(where: { $0.token == token }) else {
      throw .init(code: "finding-identity", detail: "unknown file or rule")
    }
    guard try sourceSwiftLintString(required("severity")) == "Error" else {
      throw .init(code: "finding-severity", detail: "strict SwiftLint emitted non-error")
    }
    _ = try sourceSwiftLintString(required("type"))
    let line = try sourceSwiftLintInt(required("line"))
    let column = try sourceSwiftLintInt(required("character"))
    guard line > 0, column > 0 else {
      throw .init(code: "finding-location", detail: "non-positive location")
    }
    return Source.Finding(
      rule: rule,
      diagnostic: .init(
        location: .init(fileID: file, filePath: file, line: line, column: column),
        severity: .error,
        identifier: token,
        message: try sourceSwiftLintString(required("reason"))
      ),
      repair: .unavailable(
        .init(code: "engine-repair", detail: "SwiftLint emitted no repair proposal")
      )
    )
  }
}

private func sourceSwiftLintString(_ value: JSON) throws(Source.Reason) -> Swift.String {
  do throws(JSON.Error) { return try Swift.String(json: value) } catch {
    throw .init(code: "malformed-output", detail: "expected string")
  }
}

private func sourceSwiftLintInt(_ value: JSON) throws(Source.Reason) -> Swift.Int {
  do throws(JSON.Error) { return try Swift.Int(json: value) } catch {
    throw .init(code: "malformed-output", detail: "expected integer")
  }
}

private func sourceSwiftLintUnmeasured(
  _ engine: Source.Engine.ID,
  _ subject: Source.Subject,
  _ rules: [Source.Rule.ID],
  _ code: Swift.String,
  _ detail: Swift.String
) -> Source.Measurement {
  .init(
    engine: engine,
    subject: subject,
    activeRules: rules,
    applicableRules: [],
    files: subject.files,
    verdict: .unmeasured([.init(code: code, detail: detail)])
  )
}
