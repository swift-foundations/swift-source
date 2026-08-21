import Source_SwiftLint
import Source_Swift_Format
import Testing

@Suite
struct `Source external measurements` {
  let subject = Source.Subject(identity: "package", root: "/package", files: ["A.swift"])

  @Test
  func `swift format accepts strict diagnostics`() {
    let engine = Source.Engine.ID("swift-format")
    let rule = Source.Rule.ID(engine: engine, token: "Spacing")
    let measurement = Source.Measurement.swiftFormat(
      engine: engine,
      subject: subject,
      rules: [rule],
      status: 1,
      output: "",
      diagnostics: "/package/A.swift:1:6: error: [Spacing] add 1 space\n"
    )
    guard case .findings(let findings) = measurement.verdict else {
      Issue.record("expected findings")
      return
    }
    #expect(findings.count == 1)
    #expect(findings[0].rule == rule)
    #expect(findings[0].repair == .automatic)
    #expect(measurement.observations.count == 1)
  }

  @Test
  func `swift format rejects unknown rule output`() {
    let engine = Source.Engine.ID("swift-format")
    let measurement = Source.Measurement.swiftFormat(
      engine: engine,
      subject: subject,
      rules: [.init(engine: engine, token: "Spacing")],
      status: 1,
      output: "",
      diagnostics: "/package/A.swift:1:6: error: [Other] message\n"
    )
    guard case .unmeasured(let reasons) = measurement.verdict else {
      Issue.record("expected unmeasured")
      return
    }
    #expect(reasons.map(\.code) == ["malformed-output"])
  }

  @Test
  func `SwiftLint accepts its exact JSON schema`() {
    let engine = Source.Engine.ID("swiftlint")
    let rule = Source.Rule.ID(engine: engine, token: "identifier_name")
    let measurement = Source.Measurement.swiftLint(
      engine: engine,
      subject: subject,
      rules: [rule],
      status: 2,
      output: """
        [{"character":5,"file":"/package/A.swift","line":1,"reason":"name","rule_id":"identifier_name","severity":"Error","type":"Identifier Name"}]
        """,
      diagnostics: ""
    )
    guard case .findings(let findings) = measurement.verdict else {
      Issue.record("expected findings")
      return
    }
    #expect(findings.count == 1)
    #expect(findings[0].rule == rule)
    #expect(measurement.observations.count == 1)
  }

  @Test
  func `SwiftLint rejects added JSON fields`() {
    let engine = Source.Engine.ID("swiftlint")
    let measurement = Source.Measurement.swiftLint(
      engine: engine,
      subject: subject,
      rules: [.init(engine: engine, token: "identifier_name")],
      status: 2,
      output: """
        [{"character":5,"file":"/package/A.swift","line":1,"reason":"name","rule_id":"identifier_name","severity":"Error","type":"Identifier Name","extra":true}]
        """,
      diagnostics: ""
    )
    guard case .unmeasured(let reasons) = measurement.verdict else {
      Issue.record("expected unmeasured")
      return
    }
    #expect(reasons.map(\.code) == ["unconsumed-output"])
  }
}
