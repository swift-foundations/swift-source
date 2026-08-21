extension Source.Repair {
  public struct Staging: Sendable {
    public let subject: Source.Subject
    public let binding: Source.Subject.Binding
    public let profile: Source.Profile.Digest
    public let sources: Source.SourceSet.Digest
    public let files: [Staged.File]
    public let operations: [Operation]
    public let refusals: [Refusal]
    private let engines: Swift.Set<Source.Engine.ID>

    public init(
      subject: Source.Subject,
      profile: Source.Profile.Digest,
      sources: Source.SourceSet.Digest,
      measurements: [Source.Measurement],
      fileSystem: FileSystem
    ) throws(Source.Reason) {
      var staged: [Swift.String: Staged.File] = [:]
      for path in subject.files {
        let relative = try Self.relative(path, root: subject.root)
        guard staged[relative] == nil else {
          throw .init(code: "path-collision", detail: relative)
        }
        switch fileSystem.read(relative) {
        case .success(let contents):
          staged[relative] = .init(path: relative, contents: contents)
        case .failure(let reason): throw reason
        }
      }
      let initial = staged.values.sorted(by: { $0.path < $1.path })
      guard Source.SourceSet.digest(initial) == sources else {
        throw .init(code: "stale-sources", detail: sources.hex)
      }

      var operations: [Operation] = []
      var refusals: [Refusal] = []
      var affected: Swift.Set<Swift.String> = []
      let sorted = measurements.sorted {
        (Self.rank($0.engine), $0.engine.token) < (Self.rank($1.engine), $1.engine.token)
      }
      let engines = Swift.Set(sorted.map(\.engine))
      guard engines.count == sorted.count else {
        throw .init(code: "duplicate-engine", detail: subject.identity)
      }
      for measurement in sorted {
        guard measurement.subject == subject else {
          throw .init(code: "stale-subject", detail: measurement.subject.identity)
        }
        if !measurement.suppressions.isEmpty {
          refusals.append(.init(.init(code: "suppression", detail: measurement.engine.token)))
        }
        switch measurement.verdict {
        case .unmeasured(let reasons): refusals.append(contentsOf: reasons.map(Refusal.init))
        case .notRequested:
          refusals.append(.init(.init(code: "not-requested", detail: measurement.engine.token)))
        case .clean:
          guard measurement.repairs.isEmpty else {
            refusals.append(.init(.init(code: "non-idempotent", detail: measurement.engine.token)))
            continue
          }
        case .findings: break
        }
        for evidence in measurement.repairs {
          switch evidence.disposition {
          case .unchanged:
            refusals.append(.init(.init(code: "repair-unchanged", detail: evidence.rule.token)))
          case .refused(let reason): refusals.append(.init(reason))
          case .edits(let edits):
            for edit in edits {
              let operation = try Self.stage(
                edit,
                root: subject.root,
                files: &staged,
                affected: &affected
              )
              operations.append(operation)
            }
          }
        }
      }
      self.subject = subject
      self.binding = subject.binding
      self.profile = profile
      self.sources = sources
      self.files = staged.values.sorted(by: { $0.path < $1.path })
      self.operations = operations
      self.refusals = refusals
      self.engines = engines
    }

    public func finish(remeasured: [Source.Measurement]) -> Plan {
      var refusals = self.refusals
      let repeated = Swift.Set(remeasured.map(\.engine))
      if repeated != engines || repeated.count != remeasured.count {
        refusals.append(.init(.init(code: "remeasurement-engines", detail: subject.identity)))
      }
      for measurement in remeasured {
        guard measurement.subject == subject else {
          refusals.append(.init(.init(code: "stale-subject", detail: measurement.subject.identity)))
          continue
        }
        guard measurement.repairs.isEmpty else {
          refusals.append(.init(.init(code: "non-idempotent", detail: measurement.engine.token)))
          continue
        }
        switch measurement.verdict {
        case .clean:
          let complete =
            !measurement.files.isEmpty
            && !measurement.activeRules.isEmpty
            && !measurement.applicableRules.isEmpty
            && measurement.observations.allSatisfy {
              if case .measured = $0.coverage { true } else { false }
            }
          if !complete {
            refusals.append(
              .init(.init(code: "incomplete-remeasurement", detail: measurement.engine.token)))
          }
        case .findings:
          refusals.append(
            .init(.init(code: "postmeasurement-findings", detail: measurement.engine.token)))
        case .unmeasured(let reasons): refusals.append(contentsOf: reasons.map(Refusal.init))
        case .notRequested:
          refusals.append(.init(.init(code: "not-requested", detail: measurement.engine.token)))
        }
      }
      let postconditions = files.map { file -> Postcondition in
        if let contents = file.contents {
          return .file(path: file.path, digest: Self.digest(contents))
        }
        return .absent(path: file.path)
      }
      return Plan(
        subject: binding,
        profile: profile,
        sources: sources,
        operations: operations,
        refusals: refusals,
        postconditions: postconditions
      )
    }

    private static func stage(
      _ edit: Source.Repair.Evidence.Edit,
      root: Swift.String,
      files: inout [Swift.String: Staged.File],
      affected: inout Swift.Set<Swift.String>
    ) throws(Source.Reason) -> Operation {
      switch edit {
      case .rewrite(let path, let contents):
        let path = try relative(path, root: root)
        try reserve(path, affected: &affected)
        guard let original = files[path]?.contents else {
          throw .init(code: "malformed-rewrite", detail: path)
        }
        let replacement = [UInt8](contents.utf8)
        files[path] = .init(path: path, contents: replacement)
        return .rewrite(path: path, expected: digest(original), replacement: replacement)
      case .create(let path, let contents):
        let path = try relative(path, root: root)
        try reserve(path, affected: &affected)
        guard files[path] == nil else { throw .init(code: "create-collision", detail: path) }
        let bytes = [UInt8](contents.utf8)
        files[path] = .init(path: path, contents: bytes)
        return .create(path: path, contents: bytes)
      case .move(let from, let to):
        let from = try relative(from, root: root)
        let to = try relative(to, root: root)
        try reserve(from, affected: &affected)
        try reserve(to, affected: &affected)
        guard let contents = files[from]?.contents else {
          throw .init(code: "move-source", detail: from)
        }
        guard files[to] == nil else { throw .init(code: "move-collision", detail: to) }
        files[from] = .init(path: from, contents: nil)
        files[to] = .init(path: to, contents: contents)
        return .move(from: from, to: to, expected: digest(contents))
      case .delete(let path):
        let path = try relative(path, root: root)
        try reserve(path, affected: &affected)
        guard let contents = files[path]?.contents else {
          throw .init(code: "delete-source", detail: path)
        }
        files[path] = .init(path: path, contents: nil)
        return .delete(path: path, expected: digest(contents))
      }
    }

    private static func reserve(
      _ path: Swift.String,
      affected: inout Swift.Set<Swift.String>
    ) throws(Source.Reason) {
      guard affected.insert(path).inserted else {
        throw .init(code: "overlapping-engine-conflict", detail: path)
      }
    }

    private static func relative(
      _ path: Swift.String,
      root: Swift.String
    ) throws(Source.Reason) -> Swift.String {
      let relative: Swift.String
      if path.hasPrefix("/") {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else {
          throw .init(code: "path-escape", detail: path)
        }
        relative = Swift.String(path.dropFirst(prefix.count))
      } else {
        relative = path
      }
      guard !relative.isEmpty,
        !relative.hasPrefix("/"),
        !relative.split(separator: "/").contains("..")
      else { throw .init(code: "path-escape", detail: path) }
      return relative
    }

    private static func digest(_ contents: [UInt8]) -> Swift.String {
      FIPS_180_4.SHA256.digest(contents.map(Byte.init)).hex
    }

    private static func rank(_ engine: Source.Engine.ID) -> Swift.Int {
      switch engine.token {
      case "swift-linter": 0
      case "swiftlint": 1
      case "swift-format": 2
      default: 3
      }
    }
  }
}
