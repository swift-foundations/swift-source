internal import JSON

extension Source.Measurement {
    public static func linter(
        engine: Source.Engine.ID,
        subject: Source.Subject,
        rules: [Source.Rule.ID],
        status: Swift.Int32,
        output: Swift.String,
        diagnostics: Swift.String
    ) -> Self {
        guard !subject.files.isEmpty else {
            return sourceLinterUnmeasured(
                engine: engine,
                subject: subject,
                rules: rules,
                code: "zero-files",
                detail: "no source files"
            )
        }
        guard !rules.isEmpty else {
            return sourceLinterUnmeasured(
                engine: engine,
                subject: subject,
                rules: rules,
                code: "zero-rules",
                detail: "no active rules"
            )
        }
        do throws(Source.Reason) {
            return try sourceLinterMeasurement(
                engine: engine,
                subject: subject,
                rules: rules,
                status: status,
                output: output
            )
        } catch {
            return sourceLinterUnmeasured(
                engine: engine,
                subject: subject,
                rules: rules,
                code: error.code,
                detail: error.detail + (diagnostics.isEmpty ? "" : "; stderr: \(diagnostics)")
            )
        }
    }
}

private func sourceLinterMeasurement(
    engine: Source.Engine.ID,
    subject: Source.Subject,
    rules: [Source.Rule.ID],
    status: Swift.Int32,
    output: Swift.String
) throws(Source.Reason) -> Source.Measurement {
    let document: JSON
    do throws(JSON.Error) {
        document = try JSON.parse(output)
    } catch {
        throw .init(code: "malformed-output", detail: Swift.String(describing: error))
    }
    let root = try sourceLinterObject(
        document,
        required: [
            "schema", "files", "activeRules", "applicableRules", "observations",
            "findings", "suppressions", "repairProposals", "summary",
        ]
    )
    guard try sourceLinterInt(root["schema"]) == 1 else {
        throw .init(code: "schema-mismatch", detail: "expected swift-linter schema 1")
    }

    let expectedRuleTokens = rules.map(\.token)
    let activeTokens = try sourceLinterStrings(root["activeRules"])
    guard activeTokens == expectedRuleTokens else {
        throw .init(
            code: "active-rule-mismatch",
            detail: "expected \(expectedRuleTokens), received \(activeTokens)"
        )
    }

    let expectedFiles = subject.files.map { file in
        if file.hasPrefix("/") { return file }
        if subject.root.hasSuffix("/") { return subject.root + file }
        return subject.root + "/" + file
    }.sorted()
    let files = try sourceLinterStrings(root["files"])
    guard files.sorted() == expectedFiles else {
        throw .init(code: "file-mismatch", detail: "linter file set differs from subject")
    }

    let observationsJSON = try sourceLinterArray(root["observations"])
    var observations: [Source.Rule.Observation] = []
    var observationKeys: Swift.Set<Swift.String> = []
    var unmeasured: [Source.Reason] = []
    for value in observationsJSON {
        let object = try sourceLinterObject(
            value,
            required: ["file", "rule", "applicable", "coverage"]
        )
        let file = try sourceLinterString(object["file"])
        let token = try sourceLinterString(object["rule"])
        guard expectedFiles.contains(file), expectedRuleTokens.contains(token) else {
            throw .init(code: "observation-identity", detail: "unknown file or rule")
        }
        let key = file + "\u{0}" + token
        guard observationKeys.insert(key).inserted else {
            throw .init(code: "duplicate-observation", detail: key)
        }
        let coverageObject = try sourceLinterObject(
            object["coverage"],
            required: ["status"],
            optional: ["reason"]
        )
        let coverage: Source.Rule.Coverage
        switch try sourceLinterString(coverageObject["status"]) {
        case "measured":
            guard coverageObject["reason"] == nil else {
                throw .init(code: "coverage-shape", detail: "measured coverage carried a reason")
            }
            coverage = .measured
        case "unmeasured":
            guard let reasonJSON = coverageObject["reason"] else {
                throw .init(code: "coverage-shape", detail: "unmeasured coverage omitted reason")
            }
            let reason = try sourceLinterReason(reasonJSON)
            coverage = .unmeasured(reason)
            unmeasured.append(reason)
        default:
            throw .init(code: "coverage-shape", detail: "unknown coverage status")
        }
        observations.append(
            .init(
                file: file,
                rule: .init(engine: engine, token: token),
                applicable: try sourceLinterBool(object["applicable"]),
                coverage: coverage
            )
        )
    }
    guard observationKeys.count == expectedFiles.count * expectedRuleTokens.count else {
        throw .init(code: "observation-count", detail: "file/rule matrix is incomplete")
    }

    let applicableTokens = try sourceLinterStrings(root["applicableRules"])
    let derivedApplicable = expectedRuleTokens.filter { token in
        observations.contains { $0.rule.token == token && $0.applicable }
    }
    guard applicableTokens == derivedApplicable else {
        throw .init(code: "applicable-rule-mismatch", detail: "applicable rule set disagrees")
    }

    let repairs = try sourceLinterRepairs(
        root["repairProposals"],
        engine: engine,
        files: expectedFiles,
        rules: expectedRuleTokens
    )
    let repairKeys = repairs.map { $0.file + "\u{0}" + $0.rule.token }
    guard Swift.Set(repairKeys).count == repairKeys.count else {
        throw .init(code: "duplicate-repair", detail: "duplicate file/rule repair proposal")
    }
    let repairByKey = Swift.Dictionary(uniqueKeysWithValues: Swift.zip(repairKeys, repairs))

    let findings = try sourceLinterFindings(
        root["findings"],
        engine: engine,
        files: expectedFiles,
        rules: expectedRuleTokens,
        repairs: repairByKey
    )
    let suppressions = try sourceLinterFindings(
        root["suppressions"],
        engine: engine,
        files: expectedFiles,
        rules: expectedRuleTokens,
        repairs: repairByKey
    )
    let findingKeys = Swift.Set((findings + suppressions).map {
        ($0.diagnostic.location.filePath ?? $0.diagnostic.location.fileID)
            + "\u{0}" + $0.rule.token
    })
    guard findingKeys == Swift.Set(repairByKey.keys) else {
        throw .init(code: "repair-coverage", detail: "repair proposals do not match findings")
    }

    let summary = try sourceLinterObject(
        root["summary"],
        required: [
            "files", "activeRules", "applicableRules", "applicableObservations",
            "measuredObservations", "unmeasuredObservations", "findings",
            "suppressions", "repairProposals",
        ]
    )
    let measuredCount = observations.count { if case .measured = $0.coverage { true } else { false } }
    let expectedCounts: [Swift.String: Swift.Int] = [
        "files": files.count,
        "activeRules": activeTokens.count,
        "applicableRules": applicableTokens.count,
        "applicableObservations": observations.count { $0.applicable },
        "measuredObservations": measuredCount,
        "unmeasuredObservations": unmeasured.count,
        "findings": findings.count,
        "suppressions": suppressions.count,
        "repairProposals": repairs.count,
    ]
    for (key, count) in expectedCounts {
        guard try sourceLinterInt(summary[key]) == count else {
            throw .init(code: "summary-mismatch", detail: "summary field '\(key)' disagrees")
        }
    }

    let hasError = findings.contains { $0.diagnostic.severity == .error }
    let expectedStatus: Swift.Int32 = unmeasured.isEmpty ? (hasError ? 1 : 0) : 2
    guard status == expectedStatus else {
        throw .init(
            code: "engine-status-mismatch",
            detail: "expected status \(expectedStatus), received \(status)"
        )
    }

    let verdict: Source.Measurement.Verdict
    if !unmeasured.isEmpty { verdict = .unmeasured(unmeasured) }
    else if findings.isEmpty { verdict = .clean }
    else { verdict = .findings(findings) }
    return Source.Measurement(
        engine: engine,
        subject: subject,
        activeRules: rules,
        applicableRules: applicableTokens.map { .init(engine: engine, token: $0) },
        files: files,
        observations: observations,
        suppressions: suppressions,
        repairs: repairs,
        verdict: verdict
    )
}

private func sourceLinterRepairs(
    _ value: JSON?,
    engine: Source.Engine.ID,
    files: [Swift.String],
    rules: [Swift.String]
) throws(Source.Reason) -> [Source.Repair.Evidence] {
    try sourceLinterArray(value).map { value in
        let object = try sourceLinterObject(
            value,
            required: ["file", "rule", "proposal"]
        )
        let proposal = try sourceLinterObject(
            object["proposal"],
            required: ["status"],
            optional: ["edits", "reason"]
        )
        let file = try sourceLinterString(object["file"])
        let token = try sourceLinterString(object["rule"])
        guard files.contains(file), rules.contains(token) else {
            throw .init(code: "repair-identity", detail: "unknown file or rule")
        }
        let disposition: Source.Repair.Evidence.Disposition
        switch try sourceLinterString(proposal["status"]) {
        case "unchanged":
            guard proposal["edits"] == nil, proposal["reason"] == nil else {
                throw .init(code: "repair-shape", detail: "unchanged carried extra evidence")
            }
            disposition = .unchanged
        case "refused":
            guard let reason = proposal["reason"], proposal["edits"] == nil else {
                throw .init(code: "repair-shape", detail: "refusal omitted reason")
            }
            disposition = .refused(try sourceLinterReason(reason))
        case "edits":
            guard let edits = proposal["edits"], proposal["reason"] == nil else {
                throw .init(code: "repair-shape", detail: "edits disposition omitted edits")
            }
            let parsed = try sourceLinterArray(edits).map(sourceLinterEdit)
            guard !parsed.isEmpty else {
                throw .init(code: "repair-shape", detail: "edits disposition was empty")
            }
            disposition = .edits(parsed)
        default: throw .init(code: "repair-shape", detail: "unknown disposition")
        }
        return .init(
            file: file,
            rule: .init(engine: engine, token: token),
            disposition: disposition
        )
    }
}

private func sourceLinterEdit(_ value: JSON) throws(Source.Reason) -> Source.Repair.Evidence.Edit {
    let operationObject = try sourceLinterObject(
        value,
        required: ["operation"],
        optional: ["path", "contents", "from", "to"]
    )
    let operation = try sourceLinterString(operationObject["operation"])
    let object: [Swift.String: JSON]
    switch operation {
    case "rewrite", "create":
        object = try sourceLinterObject(value, required: ["operation", "path", "contents"])
    case "move":
        object = try sourceLinterObject(value, required: ["operation", "from", "to"])
    case "delete":
        object = try sourceLinterObject(value, required: ["operation", "path"])
    default:
        throw .init(code: "repair-edit", detail: "unknown edit operation")
    }
    switch operation {
    case "rewrite":
        return try .rewrite(
            path: sourceLinterString(object["path"]),
            contents: sourceLinterString(object["contents"])
        )
    case "create":
        return try .create(
            path: sourceLinterString(object["path"]),
            contents: sourceLinterString(object["contents"])
        )
    case "move":
        return try .move(
            from: sourceLinterString(object["from"]),
            to: sourceLinterString(object["to"])
        )
    case "delete": return try .delete(path: sourceLinterString(object["path"]))
    default: preconditionFailure("operation was validated")
    }
}

private func sourceLinterFindings(
    _ value: JSON?,
    engine: Source.Engine.ID,
    files: [Swift.String],
    rules: [Swift.String],
    repairs: [Swift.String: Source.Repair.Evidence]
) throws(Source.Reason) -> [Source.Finding] {
    try sourceLinterArray(value).map { value in
        let object = try sourceLinterObject(
            value,
            required: ["rule", "severity", "message", "fileID", "line", "column"],
            optional: ["filePath", "visibility"]
        )
        let token = try sourceLinterString(object["rule"])
        let fileID = try sourceLinterString(object["fileID"])
        let path = try object["filePath"].map(sourceLinterString) ?? fileID
        guard rules.contains(token), files.contains(path) else {
            throw .init(code: "finding-identity", detail: "unknown file or rule")
        }
        if let visibility = object["visibility"] { _ = try sourceLinterString(visibility) }
        let severity: Diagnostic.Severity
        switch try sourceLinterString(object["severity"]) {
        case "error": severity = .error
        case "warning": severity = .warning
        case "note": severity = .note
        case "remark": severity = .remark
        default: throw .init(code: "finding-severity", detail: "unknown severity")
        }
        let line = try sourceLinterInt(object["line"])
        let column = try sourceLinterInt(object["column"])
        guard line > 0, column > 0 else {
            throw .init(code: "finding-location", detail: "line and column must be positive")
        }
        let key = path + "\u{0}" + token
        guard let repair = repairs[key] else {
            throw .init(code: "repair-coverage", detail: "finding omitted repair proposal")
        }
        return try Source.Finding(
            rule: .init(engine: engine, token: token),
            diagnostic: .init(
                location: .init(
                    fileID: fileID,
                    filePath: path,
                    line: line,
                    column: column
                ),
                severity: severity,
                identifier: token,
                message: sourceLinterString(object["message"])
            ),
            repair: sourceLinterCapability(repair.disposition)
        )
    }
}

private func sourceLinterCapability(
    _ disposition: Source.Repair.Evidence.Disposition
) -> Source.Repair.Capability {
    switch disposition {
    case .unchanged:
        .unavailable(.init(code: "unchanged", detail: "rule proposed no edit"))
    case .refused(let reason): .unavailable(reason)
    case .edits(let edits):
        if edits.count == 1, case .rewrite = edits[0] { .automatic }
        else { .transactional }
    }
}

private func sourceLinterReason(_ value: JSON) throws(Source.Reason) -> Source.Reason {
    let object = try sourceLinterObject(value, required: ["code"], optional: ["detail"])
    let detail: Swift.String
    if let value = object["detail"] { detail = try sourceLinterString(value) }
    else { detail = "" }
    return .init(code: try sourceLinterString(object["code"]), detail: detail)
}

private func sourceLinterObject(
    _ value: JSON?,
    required: Swift.Set<Swift.String>,
    optional: Swift.Set<Swift.String> = []
) throws(Source.Reason) -> [Swift.String: JSON] {
    guard let value, let members = value.object else {
        throw .init(code: "malformed-output", detail: "expected object")
    }
    let keys = members.map(\.key)
    let keySet = Swift.Set(keys)
    guard keySet.count == keys.count,
        required.isSubset(of: keySet),
        keySet.isSubset(of: required.union(optional))
    else {
        throw .init(code: "unconsumed-output", detail: "object keys disagree with schema")
    }
    return Swift.Dictionary(uniqueKeysWithValues: members.map { ($0.key, $0.value) })
}

private func sourceLinterArray(_ value: JSON?) throws(Source.Reason) -> [JSON] {
    guard let value, let array = value.array else {
        throw .init(code: "malformed-output", detail: "expected array")
    }
    return array
}

private func sourceLinterStrings(_ value: JSON?) throws(Source.Reason) -> [Swift.String] {
    try sourceLinterArray(value).map(sourceLinterString)
}

private func sourceLinterString(_ value: JSON?) throws(Source.Reason) -> Swift.String {
    guard let value else { throw .init(code: "malformed-output", detail: "missing string") }
    do throws(JSON.Error) { return try Swift.String(json: value) }
    catch { throw .init(code: "malformed-output", detail: "expected string") }
}

private func sourceLinterInt(_ value: JSON?) throws(Source.Reason) -> Swift.Int {
    guard let value else { throw .init(code: "malformed-output", detail: "missing integer") }
    do throws(JSON.Error) { return try Swift.Int(json: value) }
    catch { throw .init(code: "malformed-output", detail: "expected integer") }
}

private func sourceLinterBool(_ value: JSON?) throws(Source.Reason) -> Swift.Bool {
    guard let value else { throw .init(code: "malformed-output", detail: "missing boolean") }
    do throws(JSON.Error) { return try Swift.Bool(json: value) }
    catch { throw .init(code: "malformed-output", detail: "expected boolean") }
}

private func sourceLinterUnmeasured(
    engine: Source.Engine.ID,
    subject: Source.Subject,
    rules: [Source.Rule.ID],
    code: Swift.String,
    detail: Swift.String
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
