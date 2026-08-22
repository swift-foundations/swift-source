import Testing

@testable import Source

extension Source.Loader {
  @Suite
  struct Test {

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

      @Suite
      struct Loader {
        @Test
        func `load Nonexistent File Throws File Not Found`() throws {
          #expect(
            throws: Source.Error.fileNotFound(
              path: "/nonexistent/path/to/file.swift"
            )
          ) {
            try Source.Loader.load(contentsOf: "/nonexistent/path/to/file.swift")
          }
        }

        @Test
        func `load Existing File Returns Bytes`() throws {

          let bytes = try Source.Loader.load(contentsOf: "/usr/bin/true")
          #expect(!bytes.isEmpty)
        }

        @Test
        func `load Empty File Returns Empty Array`() throws {

          let bytes = try Source.Loader.load(contentsOf: "/dev/null")
          #expect(bytes.isEmpty)
        }
      }

    #else

      @Suite
      struct Loader {
        @Test
        func `load reports the platform as unsupported`() throws {
          #expect(throws: Source.Error.unsupportedPlatform) {
            try Source.Loader.load(contentsOf: "any/path.swift")
          }
        }
      }

    #endif

    @Suite
    struct `BOM Stripping` {
      @Test
      func `strip BOM From Prefixed Buffer`() {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let content: [UInt8] = [0x41, 0x42, 0x43]
        let input = bom + content
        let result = Source.Loader._stripBOM(from: input)
        #expect(result == content)
      }

      @Test
      func `preserve Buffer Without BOM`() {
        let content: [UInt8] = [0x41, 0x42, 0x43]
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

extension Source.Cache {
  @Suite
  struct Test {
    @Test
    func `empty Cache Has Zero Count`() {
      let cache = Source.Cache()
      #expect(cache.count == 0)
    }

    @Test
    func `remove Nonexistent Path Returns Nil`() {
      var cache = Source.Cache()
      let removed = cache.remove(path: "/does/not/exist")
      #expect(removed == nil)
    }

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

      @Test
      func `load Caches Result`() throws {
        var cache = Source.Cache()
        let first = try cache.load(contentsOf: "/dev/null")
        #expect(cache.count == 1)
        #expect(cache.contains(path: "/dev/null"))

        let second = try cache.load(contentsOf: "/dev/null")
        #expect(first == second)
        #expect(cache.count == 1)
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

    #else

      @Test
      func `cache Passes Through The Unsupported Platform`() {
        var cache = Source.Cache()
        #expect(throws: Source.Error.unsupportedPlatform) {
          try cache.load(contentsOf: "any/path.swift")
        }
        #expect(cache.count == 0)
      }

    #endif
  }
}

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
    func `unsupported platform is a representable typed failure`() {

      let unsupported = Source.Error.unsupportedPlatform
      #expect(unsupported.description.contains("not implemented"))
      #expect(unsupported == .unsupportedPlatform)
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
