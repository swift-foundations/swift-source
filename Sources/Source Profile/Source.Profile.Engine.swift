extension Source.Profile {
    public struct Engine: Equatable, Sendable, JSON.Serializable {
        public let id: Source.Engine.ID
        public let executable: Swift.String
        public let tool: Digest
        public let configuration: Digest
        public let rules: [Source.Rule.ID]

        public init(
            id: Source.Engine.ID,
            executable: Swift.String,
            tool: Digest,
            configuration: Digest,
            rules: [Source.Rule.ID]
        ) {
            self.id = id
            self.executable = executable
            self.tool = tool
            self.configuration = configuration
            self.rules = rules.sorted {
                ($0.engine.token, $0.token) < ($1.engine.token, $1.token)
            }
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "id": value.id.json,
                "executable": value.executable.json,
                "tool": value.tool.json,
                "configuration": value.configuration.json,
                "rules": value.rules.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard let id = object["id"] else { throw .missingKey("id") }
            guard let executable = object["executable"] else { throw .missingKey("executable") }
            guard let tool = object["tool"] else { throw .missingKey("tool") }
            guard let configuration = object["configuration"] else {
                throw .missingKey("configuration")
            }
            guard let rules = object["rules"] else { throw .missingKey("rules") }
            return try Self(
                id: Source.Engine.ID(json: id),
                executable: Swift.String(json: executable),
                tool: Digest(json: tool),
                configuration: Digest(json: configuration),
                rules: [Source.Rule.ID](json: rules)
            )
        }
    }
}
