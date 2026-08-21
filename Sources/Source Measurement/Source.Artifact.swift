extension Source {
    public struct Artifact: Hashable, Sendable, JSON.Serializable {
        public let path: Swift.String
        public let kind: Kind
        public let provenance: Provenance

        public init(
            path: Swift.String,
            kind: Kind,
            provenance: Provenance
        ) {
            self.path = path
            self.kind = kind
            self.provenance = provenance
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "path": value.path.json,
                "kind": value.kind.json,
                "provenance": value.provenance.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard let path = object["path"] else { throw .missingKey("path") }
            guard let kind = object["kind"] else { throw .missingKey("kind") }
            guard let provenance = object["provenance"] else {
                throw .missingKey("provenance")
            }
            return try Self(
                path: Swift.String(json: path),
                kind: Kind(json: kind),
                provenance: Provenance(json: provenance)
            )
        }
    }
}
