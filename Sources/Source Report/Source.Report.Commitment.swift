extension Source.Report {
    public struct Commitment: Equatable, Sendable, JSON.Serializable {
        public let subjects: [Source.Subject]
        public let engines: [Engine]
        public let predicates: [Predicate]

        public init(
            subjects: [Source.Subject],
            engines: [Engine],
            predicates: [Predicate]
        ) {
            self.subjects = subjects.sorted { $0.identity < $1.identity }
            self.engines = engines.sorted { $0.id.token < $1.id.token }
            self.predicates = predicates.sorted {
                ($0.id.engine.token, $0.id.token) < ($1.id.engine.token, $1.id.token)
            }
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "subjects": value.subjects.json,
                "engines": value.engines.json,
                "predicates": value.predicates.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            func required(_ key: Swift.String) throws(JSON.Error) -> JSON {
                guard let value = object[key] else { throw .missingKey(key) }
                return value
            }
            return try Self(
                subjects: [Source.Subject](json: required("subjects")),
                engines: [Engine](json: required("engines")),
                predicates: [Predicate](json: required("predicates"))
            )
        }
    }
}
