extension Source {

    public struct Cache: Sendable {

        @usableFromInline
        internal var _loaded: [Swift.String: [UInt8]]

        @inlinable
        public init() {
            self._loaded = [:]
        }
    }
}

extension Source.Cache {

    @inlinable
    public mutating func load(
        contentsOf path: Swift.String
    ) throws(Source.Error) -> [UInt8] {
        if let cached = _loaded[path] {
            return cached
        }
        let content = try Source.Loader.load(contentsOf: path)
        _loaded[path] = content
        return content
    }

    @inlinable
    public var count: Int {
        _loaded.count
    }

    @inlinable
    public func contains(path: Swift.String) -> Bool {
        _loaded[path] != nil
    }

    @inlinable
    @discardableResult
    public mutating func remove(path: Swift.String) -> [UInt8]? {
        _loaded.removeValue(forKey: path)
    }

    @inlinable
    public mutating func removeAll() {
        _loaded.removeAll()
    }
}
