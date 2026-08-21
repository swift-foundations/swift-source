extension Source.Report {
    public struct Commitment: Equatable, Sendable, JSON.Serializable {
        public let subjects: [Source.Subject]
        public let engines: [Engine]
        public let requirements: [Requirement]
        public let predicates: [Predicate]

        public init(
            subjects: [Source.Subject],
            engines: [Engine],
            requirements: [Requirement],
            predicates: [Predicate]
        ) {
            self.subjects = subjects.sorted { $0.identity < $1.identity }
            self.engines = engines.sorted { $0.id.token < $1.id.token }
            self.requirements = requirements.sorted {
                ($0.subject, $0.engine.token) < ($1.subject, $1.engine.token)
            }
            self.predicates = predicates.sorted {
                ($0.id.engine.token, $0.id.token) < ($1.id.engine.token, $1.id.token)
            }
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "subjects": value.subjects.json,
                "engines": value.engines.json,
                "requirements": value.requirements.json,
                "predicates": value.predicates.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            let expected: Set<Swift.String> = [
                "subjects", "engines", "requirements", "predicates",
            ]
            guard Set(object.keys) == expected else {
                throw .typeMismatch(expected: "commitment keys", got: "foreign keys")
            }
            func required(_ key: Swift.String) throws(JSON.Error) -> JSON {
                guard let value = object[key] else { throw .missingKey(key) }
                return value
            }
            return try Self(
                subjects: [Source.Subject](json: required("subjects")),
                engines: [Engine](json: required("engines")),
                requirements: [Requirement](json: required("requirements")),
                predicates: [Predicate](json: required("predicates"))
            )
        }
    }
}
