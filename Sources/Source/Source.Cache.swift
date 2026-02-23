// Source.Cache.swift
// swift-source
//
// Path-keyed content cache for loaded source files.

extension Source {
    /// A simple path-to-content cache for source files.
    ///
    /// `Cache` wraps a `Dictionary<String, [UInt8]>` and delegates to
    /// ``Source.Loader`` on cache miss. Once a file is loaded, subsequent
    /// requests for the same path return the cached bytes without disk I/O.
    ///
    /// ## Thread Safety
    ///
    /// `Cache` is a value type (`struct`) and is `Sendable`. It does not
    /// provide internal synchronization — concurrent mutation requires
    /// external coordination (e.g., wrapping in an actor).
    ///
    /// ## Example
    ///
    /// ```swift
    /// var cache = Source.Cache()
    /// let bytes = try cache.load(contentsOf: "/path/to/file.swift")
    /// // Second call returns cached result — no disk I/O.
    /// let same = try cache.load(contentsOf: "/path/to/file.swift")
    /// ```
    ///
    /// ## Future Evolution
    ///
    /// - LRU eviction for memory pressure
    /// - Actor-based variant for concurrent access
    /// - Integration with `Source.File.ID` when source-primitives stabilizes
    public struct Cache: Sendable {
        /// Loaded file contents keyed by path.
        @usableFromInline
        internal var _loaded: [Swift.String: [UInt8]]

        /// Creates an empty cache.
        @inlinable
        public init() {
            self._loaded = [:]
        }

        /// Loads the contents of a source file, returning cached data if available.
        ///
        /// On cache miss, delegates to ``Source.Loader.load(contentsOf:)`` and
        /// stores the result for future lookups.
        ///
        /// - Parameter path: Absolute or relative file system path.
        /// - Returns: The file contents as raw UTF-8 bytes (BOM-stripped).
        /// - Throws: `Source.Error` on I/O failure (only on cache miss).
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

        /// The number of files currently cached.
        @inlinable
        public var count: Int {
            _loaded.count
        }

        /// Whether the cache contains data for the given path.
        @inlinable
        public func contains(path: Swift.String) -> Bool {
            _loaded[path] != nil
        }

        /// Removes the cached content for the given path.
        ///
        /// Returns the previously cached bytes, or `nil` if the path was not cached.
        @inlinable
        @discardableResult
        public mutating func remove(path: Swift.String) -> [UInt8]? {
            _loaded.removeValue(forKey: path)
        }

        /// Removes all cached content.
        @inlinable
        public mutating func removeAll() {
            _loaded.removeAll()
        }
    }
}
