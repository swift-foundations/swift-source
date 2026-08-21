extension Source {
    public struct Subject: Hashable, Sendable {
        public let identity: Swift.String
        public let root: Swift.String
        public let files: [Swift.String]

        public init(identity: Swift.String, root: Swift.String, files: [Swift.String]) {
            self.identity = identity
            self.root = root
            self.files = files.sorted()
        }
    }
}
