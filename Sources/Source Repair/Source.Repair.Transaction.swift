extension Source.Repair {
    public struct Transaction: Sendable {
        public let files: FileSystem

        public init(files: FileSystem) {
            self.files = files
        }

        public func apply(_ plan: Plan) -> Result<Void, Source.Reason> {
            guard plan.refusals.isEmpty else {
                return .failure(
                    .init(code: "repair-refusal", detail: plan.refusals[0].reason.detail)
                )
            }
            if let invalid = validate(plan.operations) { return .failure(invalid) }

            var journal: [Operation] = []
            for operation in plan.operations {
                switch publish(operation, journal: &journal) {
                case .success: break
                case .failure(let reason):
                    return rollback(journal, after: reason)
                }
            }
            for postcondition in plan.postconditions {
                switch files.read(postcondition.path) {
                case .success(let contents):
                    guard digest(contents) == postcondition.digest else {
                        return rollback(
                            journal,
                            after: .init(
                                code: "postcondition",
                                detail: "digest mismatch at \(postcondition.path)"
                            )
                        )
                    }
                case .failure(let reason): return rollback(journal, after: reason)
                }
            }
            return .success(())
        }

        private func validate(_ operations: [Operation]) -> Source.Reason? {
            var paths: Set<Swift.String> = []
            for operation in operations {
                let affected: [Swift.String]
                switch operation {
                case .rewrite(let path, _, _), .create(let path, _), .delete(let path, _):
                    affected = [path]
                case .move(let from, let to, _): affected = [from, to]
                }
                for path in affected {
                    guard !path.hasPrefix("/"),
                        !path.split(separator: "/").contains("..")
                    else {
                        return .init(code: "path-escape", detail: path)
                    }
                    guard paths.insert(path).inserted else {
                        return .init(code: "path-collision", detail: path)
                    }
                }
            }
            return nil
        }

        private func publish(
            _ operation: Operation,
            journal: inout [Operation]
        ) -> Result<Void, Source.Reason> {
            switch operation {
            case .rewrite(let path, let expected, let replacement):
                switch files.read(path) {
                case .failure(let reason): return .failure(reason)
                case .success(let original):
                    guard digest(original) == expected else {
                        return .failure(.init(code: "stale-file", detail: path))
                    }
                    switch files.write(path, replacement) {
                    case .failure(let reason): return .failure(reason)
                    case .success:
                        journal.append(
                            .rewrite(
                                path: path,
                                expected: digest(replacement),
                                replacement: original
                            )
                        )
                        return .success(())
                    }
                }

            case .create(let path, let contents):
                guard !files.exists(path) else {
                    return .failure(.init(code: "create-collision", detail: path))
                }
                switch files.write(path, contents) {
                case .failure(let reason): return .failure(reason)
                case .success:
                    journal.append(.delete(path: path, expected: digest(contents)))
                    return .success(())
                }

            case .move(let from, let to, let expected):
                guard !files.exists(to) else {
                    return .failure(.init(code: "move-collision", detail: to))
                }
                switch files.read(from) {
                case .failure(let reason): return .failure(reason)
                case .success(let contents):
                    guard digest(contents) == expected else {
                        return .failure(.init(code: "stale-file", detail: from))
                    }
                    switch files.move(from, to) {
                    case .failure(let reason): return .failure(reason)
                    case .success:
                        journal.append(.move(from: to, to: from, expected: expected))
                        return .success(())
                    }
                }

            case .delete(let path, let expected):
                switch files.read(path) {
                case .failure(let reason): return .failure(reason)
                case .success(let contents):
                    guard digest(contents) == expected else {
                        return .failure(.init(code: "stale-file", detail: path))
                    }
                    switch files.delete(path) {
                    case .failure(let reason): return .failure(reason)
                    case .success:
                        journal.append(.create(path: path, contents: contents))
                        return .success(())
                    }
                }
            }
        }

        private func rollback(
            _ journal: [Operation],
            after reason: Source.Reason
        ) -> Result<Void, Source.Reason> {
            var empty: [Operation] = []
            for operation in journal.reversed() {
                if case .failure(let rollback) = publish(operation, journal: &empty) {
                    return .failure(
                        .init(
                            code: "rollback",
                            detail: "\(reason.detail); rollback: \(rollback.detail)"
                        )
                    )
                }
            }
            return .failure(reason)
        }

        private func digest(_ contents: [UInt8]) -> Swift.String {
            FIPS_180_4.SHA256.digest(contents.map(Byte.init)).hex
        }
    }
}
