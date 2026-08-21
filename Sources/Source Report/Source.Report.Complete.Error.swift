extension Source.Report.Complete {
    public enum Error: Swift.Error, Sendable, Equatable {
        case partial
        case references
        case engines(Swift.String)
        case coverage(Swift.String)
    }
}
