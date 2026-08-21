extension Source.Repair {
    public struct Postcondition: Sendable, JSON.Serializable {
        public let path: Swift.String
        public let digest: Swift.String

        public init(path: Swift.String, digest: Swift.String) {
            self.path = path
            self.digest = digest
        }

        public static func serialize(_ value: Self) -> JSON {
            ["path": value.path.json, "digest": value.digest.json]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard let path = object["path"] else { throw .missingKey("path") }
            guard let digest = object["digest"] else { throw .missingKey("digest") }
            return try Self(path: Swift.String(json: path), digest: Swift.String(json: digest))
        }
    }
}
