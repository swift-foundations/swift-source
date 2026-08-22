extension Source.Engine.Process {
  public static func fixed(_ result: Result) -> Self {
    Self { _, _, _, _ in result }
  }
}
