# swift-source

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Source-file loading and caching for lexers, parsers, and diagnostics — typed errors, UTF-8 BOM stripping, and byte buffers whose offsets map directly to source positions.

## Quick Start

```swift
import Source

// Load raw UTF-8 bytes. A leading BOM (0xEF 0xBB 0xBF) is stripped,
// so byte offsets in the buffer correspond directly to lexer positions.
let bytes = try Source.Loader.load(contentsOf: "Sources/App/main.swift")

// Cache repeated loads: the second call is a dictionary lookup, not disk I/O.
var cache = Source.Cache()
let first = try cache.load(contentsOf: "Sources/App/main.swift")
let second = try cache.load(contentsOf: "Sources/App/main.swift") // cached
```

Both `load` entry points use typed throws — the compiler knows the complete failure surface is `Source.Error`, so exhaustive handling needs no `default` arm and no `any Error` casts.

---

## Key Features

- **Typed throws end-to-end** — every throwing function throws `Source.Error`; no `any Error` escapes the API surface.
- **Byte-exact offsets** — the UTF-8 BOM is stripped on load, so offsets in the returned `[UInt8]` match source positions without adjustment.
- **No Foundation import** — file loading goes through POSIX `open(2)`/`fstat(2)`/`read(2)` directly.
- **Value-type cache** — `Source.Cache` is a `Sendable` struct with no hidden synchronization; concurrent mutation is coordinated by the owner (e.g., an actor).

---

## Installation

Add swift-source to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-source.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Source", package: "swift-source")
    ]
)
```

### Requirements

- Swift 6.3.1+ toolchain
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, visionOS 26+, or Linux (glibc, musl)

---

## Architecture

Single module (`Source`), three types:

| Type | Purpose |
|------|---------|
| `Source.Loader` | Reads a file into `[UInt8]` via POSIX `open`/`fstat`/`read`; strips the UTF-8 BOM |
| `Source.Cache` | Path-keyed content cache; delegates to `Source.Loader` on miss |
| `Source.Error` | Typed error covering the full loading failure surface |

Importing `Source` also re-exports the `Source` namespace from [swift-source-primitives](https://github.com/swift-primitives/swift-source-primitives): `Source.File`, `Source.File.ID`, `Source.Position`, `Source.Location`, `Source.Range`, and `Source.Manager` are available without a second import.

---

## Error Handling

```
Source.Error
├── .fileNotFound(path:)         // No file exists at the given path
├── .openFailed(path:errno:)     // open(2) failed (permissions, descriptor limits, …)
└── .readFailed(path:errno:)     // fstat(2) or read(2) failed after a successful open
```

Exhaustive matching:

```swift
do throws(Source.Error) {
    let bytes = try Source.Loader.load(contentsOf: path)
    process(bytes)
} catch {
    switch error {
    case .fileNotFound(let path):
        report("missing source file: \(path)")
    case .openFailed(let path, let errno):
        report("cannot open \(path) (errno \(errno))")
    case .readFailed(let path, let errno):
        report("read failed for \(path) (errno \(errno))")
    }
}
```

`Source.Error` is `Equatable`, so tests can assert specific failures with `#expect(throws:)`.

---

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Supported |
| Linux (glibc, musl) | Supported |
| iOS / tvOS / watchOS / visionOS | Supported |
| Windows | Not supported |

`Source.Loader.load` traps on platforms without a POSIX layer; Windows support requires a separate loading path that does not exist yet.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE](LICENSE.md).
