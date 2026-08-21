import Source_Swift_Format
import Testing

@Suite
struct `Source external measurements` {
    let subject = Source.Subject(identity: "package", root: "/package", artifacts: [.init(path: "A.swift", kind: .swift, provenance: .authored)])

    @Test
    func `swift format accepts strict diagnostics`() {
        let engine = Source.Engine.ID("swift-format")
        let rule = Source.Rule.ID(engine: engine, token: "format")
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
    func `swift format rejects a noncanonical profile`() {
        let engine = Source.Engine.ID("swift-format")
        let measurement = Source.Measurement.swiftFormat(
            engine: engine,
            subject: subject,
            rules: [.init(engine: engine, token: "other")],
            status: 1,
            output: "",
            diagnostics: "/package/A.swift:1:6: error: [Other] message\n"
        )
        guard case .unmeasured(let reasons) = measurement.verdict else {
            Issue.record("expected unmeasured")
            return
        }
        #expect(reasons.map(\.code) == ["rule-profile"])
    }
}
