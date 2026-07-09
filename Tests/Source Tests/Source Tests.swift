// Source Tests.swift
// swift-source
//
// Tests for Source.Loader, Source.Cache, and Source.Error.

import Testing

@testable import Source

extension Source.Loader {
    @Suite
    struct Test {

        // MARK: - Loader

        @Suite
        struct Loader {
            @Test
            func `load Nonexistent File Throws File Not Found`() throws {
                #expect(throws: Source.Error.fileNotFound(path: "/nonexistent/path/to/file.swift")) {
                    try Source.Loader.load(contentsOf: "/nonexistent/path/to/file.swift")
                }
            }

            @Test
            func `load Existing File Returns Bytes`() throws {
                // /usr/bin/true exists on all POSIX systems and is a small binary.
                // We just verify it loads without error and returns non-empty data.
                let bytes = try Source.Loader.load(contentsOf: "/usr/bin/true")
                #expect(!bytes.isEmpty)
            }

            @Test
            func `load Empty File Returns Empty Array`() throws {
                // /dev/null reads as empty.
                let bytes = try Source.Loader.load(contentsOf: "/dev/null")
                #expect(bytes.isEmpty)
            }
        }

        // MARK: - BOM Stripping

        @Suite
        struct BOMStripping {
            @Test
            func `strip BOM From Prefixed Buffer`() {
                let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
                let content: [UInt8] = [0x41, 0x42, 0x43]  // "ABC"
                let input = bom + content
                let result = Source.Loader._stripBOM(from: input)
                #expect(result == content)
            }

            @Test
            func `preserve Buffer Without BOM`() {
                let content: [UInt8] = [0x41, 0x42, 0x43]  // "ABC"
                let result = Source.Loader._stripBOM(from: content)
                #expect(result == content)
            }

            @Test
            func `preserve Empty Buffer`() {
                let result = Source.Loader._stripBOM(from: [])
                #expect(result.isEmpty)
            }

            @Test
            func `preserve Partial BOM Prefix`() {
                // Only 2 of 3 BOM bytes — should NOT strip.
                let content: [UInt8] = [0xEF, 0xBB, 0x41]
                let result = Source.Loader._stripBOM(from: content)
                #expect(result == content)
            }

            @Test
            func `strip BOM From BOM Only Buffer`() {
                let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
                let result = Source.Loader._stripBOM(from: bom)
                #expect(result.isEmpty)
            }
        }
    }
}

// MARK: - Cache

extension Source.Cache {
    @Suite
    struct Test {
        @Test
        func `empty Cache Has Zero Count`() {
            let cache = Source.Cache()
            #expect(cache.count == 0)
        }

        @Test
        func `load Caches Result`() throws {
            var cache = Source.Cache()
            let first = try cache.load(contentsOf: "/dev/null")
            #expect(cache.count == 1)
            #expect(cache.contains(path: "/dev/null"))

            let second = try cache.load(contentsOf: "/dev/null")
            #expect(first == second)
            #expect(cache.count == 1)  // No additional entry.
        }

        @Test
        func `remove Evicts Entry`() throws {
            var cache = Source.Cache()
            _ = try cache.load(contentsOf: "/dev/null")
            #expect(cache.count == 1)

            let removed = cache.remove(path: "/dev/null")
            #expect(removed != nil)
            #expect(cache.count == 0)
            #expect(!cache.contains(path: "/dev/null"))
        }

        @Test
        func `remove Nonexistent Path Returns Nil`() {
            var cache = Source.Cache()
            let removed = cache.remove(path: "/does/not/exist")
            #expect(removed == nil)
        }

        @Test
        func `remove All Clears Cache`() throws {
            var cache = Source.Cache()
            _ = try cache.load(contentsOf: "/dev/null")
            cache.removeAll()
            #expect(cache.count == 0)
        }

        @Test
        func `cache Passes Through Load Errors`() {
            var cache = Source.Cache()
            #expect(throws: Source.Error.fileNotFound(path: "/nonexistent")) {
                try cache.load(contentsOf: "/nonexistent")
            }
            #expect(cache.count == 0)
        }
    }
}

// MARK: - Error

extension Source.Error {
    @Suite
    struct Test {
        @Test
        func `error Descriptions`() {
            let notFound = Source.Error.fileNotFound(path: "/some/path")
            #expect(notFound.description.contains("/some/path"))

            let openFailed = Source.Error.openFailed(path: "/some/path", errno: 13)
            #expect(openFailed.description.contains("13"))

            let readFailed = Source.Error.readFailed(path: "/some/path", errno: 5)
            #expect(readFailed.description.contains("5"))
        }

        @Test
        func `error Equality`() {
            let a = Source.Error.fileNotFound(path: "/a")
            let b = Source.Error.fileNotFound(path: "/a")
            let c = Source.Error.fileNotFound(path: "/b")
            #expect(a == b)
            #expect(a != c)
        }
    }
}
