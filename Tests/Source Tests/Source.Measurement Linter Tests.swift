import Source_Linter
import Testing

@Suite
struct `Source linter measurement` {
  let engine = Source.Engine.ID("swift-linter")
  let rule = Source.Rule.ID(engine: .init("swift-linter"), token: "rule")
  let subject = Source.Subject(
    identity: "package",
    root: "/package",
    artifacts: [
      .init(
        path: "A.swift",
        kind: .swift,
        purpose: .governedSource,
        provenance: .authored,
        digest: .init("a")
      )
    ]
  )

  @Test
  func `accepts complete clean evidence`() {
    let measurement = measure(output: clean)
    guard case .clean = measurement.verdict else {
      Issue.record("expected CLEAN")
      return
    }
    #expect(measurement.files == ["/package/A.swift"])
    #expect(measurement.applicableRules == [rule])
    #expect(measurement.observations.count == 1)
    #expect(measurement.suppressions.isEmpty)
    #expect(measurement.repairs.isEmpty)
  }

  @Test
  func `accepts findings suppressions and typed repairs`() {
    let measurement = measure(status: 1, output: finding)
    guard case .findings(let findings) = measurement.verdict else {
      Issue.record("expected FINDINGS")
      return
    }
    #expect(findings.count == 1)
    #expect(measurement.suppressions.count == 1)
    #expect(measurement.repairs.count == 1)
    #expect(findings[0].repair == .automatic)
    guard case .edits(let edits) = measurement.repairs[0].disposition else {
      Issue.record("expected typed edits")
      return
    }
    #expect(edits == [.rewrite(path: "/package/A.swift", contents: "fixed")])
  }

  @Test(arguments: [
    ("{", "malformed-output"),
    (replace(clean, "\"schema\":1", with: "\"schema\":1,\"extra\":0"), "unconsumed-output"),
    (replace(clean, observation, with: ""), "observation-count"),
    (
      replace(clean, "\"activeRules\":[\"rule\"]", with: "\"activeRules\":[\"other\"]"),
      "active-rule-mismatch"
    ),
    (
      replace(
        clean,
        "\"files\":[\"/package/A.swift\"]",
        with: "\"files\":[\"/package/B.swift\"]"
      ), "file-mismatch"
    ),
    (replace(clean, "\"findings\":0", with: "\"findings\":1"), "summary-mismatch"),
  ])
  func `rejects incomplete or contradictory evidence`(fixture: (Swift.String, Swift.String)) {
    let measurement = measure(output: fixture.0)
    guard case .unmeasured(let reasons) = measurement.verdict else {
      Issue.record("expected UNMEASURED")
      return
    }
    #expect(reasons.map(\.code) == [fixture.1])
  }

  @Test
  func `requires status two for unmeasured evidence`() {
    let unmeasured = replace(
      clean,
      "\"coverage\":{\"status\":\"measured\"}",
      with:
        "\"coverage\":{\"status\":\"unmeasured\",\"reason\":{\"code\":\"missingSemanticContext\"}}"
    )
    let counts = replace(
      unmeasured,
      "\"measuredObservations\":1",
      with: "\"measuredObservations\":0"
    )
    let output = replace(
      counts,
      "\"unmeasuredObservations\":0",
      with: "\"unmeasuredObservations\":1"
    )
    let accepted = measure(status: 2, output: output)
    guard case .unmeasured(let reasons) = accepted.verdict else {
      Issue.record("expected UNMEASURED")
      return
    }
    #expect(reasons.map(\.code) == ["missingSemanticContext"])

    let rejected = measure(status: 0, output: output)
    guard case .unmeasured(let rejectedReasons) = rejected.verdict else {
      Issue.record("expected status mismatch")
      return
    }
    #expect(rejectedReasons.map(\.code) == ["engine-status-mismatch"])
  }

  private func measure(
    status: Swift.Int32 = 0,
    output: Swift.String
  ) -> Source.Measurement {
    Source.Measurement.linter(
      engine: engine,
      subject: subject,
      rules: [rule],
      status: status,
      output: output,
      diagnostics: ""
    )
  }

  private static let observation = """
    {"file":"/package/A.swift","rule":"rule","applicable":true,"coverage":{"status":"measured"}}
    """

  private static let clean = """
    {"schema":1,"files":["/package/A.swift"],"activeRules":["rule"],"applicableRules":["rule"],"observations":[\(observation)],"findings":[],"suppressions":[],"repairProposals":[],"summary":{"files":1,"activeRules":1,"applicableRules":1,"applicableObservations":1,"measuredObservations":1,"unmeasuredObservations":0,"findings":0,"suppressions":0,"repairProposals":0}}
    """

  private static let finding = """
    {"schema":1,"files":["/package/A.swift"],"activeRules":["rule"],"applicableRules":["rule"],"observations":[\(observation)],"findings":[{"rule":"rule","severity":"error","message":"message","fileID":"A.swift","filePath":"/package/A.swift","line":1,"column":1}],"suppressions":[{"rule":"rule","severity":"note","message":"suppressed","fileID":"A.swift","filePath":"/package/A.swift","line":2,"column":1,"visibility":"internal"}],"repairProposals":[{"file":"/package/A.swift","rule":"rule","proposal":{"status":"edits","edits":[{"operation":"rewrite","path":"/package/A.swift","contents":"fixed"}]}}],"summary":{"files":1,"activeRules":1,"applicableRules":1,"applicableObservations":1,"measuredObservations":1,"unmeasuredObservations":0,"findings":1,"suppressions":1,"repairProposals":1}}
    """

  private static func replace(
    _ source: Swift.String,
    _ target: Swift.String,
    with replacement: Swift.String
  ) -> Swift.String {
    guard let range = source.firstRange(of: target) else { return source }
    var result = source
    result.replaceSubrange(range, with: replacement)
    return result
  }
}
