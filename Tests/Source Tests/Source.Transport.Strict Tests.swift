import JSON
import Source_Repair
import Testing

@Suite
struct `Source transport strictness` {
  @Suite struct Unit {}
  @Suite struct `Edge Case` {}
  @Suite struct Integration {}
}

extension `Source transport strictness`.Unit {
  @Test
  func `repair evidence rejects foreign keys`() {
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Capability(
        json: ["state": "automatic", "foreign": true]
      )
    }
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Evidence.Disposition(
        json: ["status": "unchanged", "foreign": true]
      )
    }
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Evidence.Edit(
        json: [
          "operation": "delete",
          "path": "A.swift",
          "foreign": true,
        ]
      )
    }
  }
}

extension `Source transport strictness`.`Edge Case` {
  @Test
  func `repair transaction rejects foreign keys`() {
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Operation(
        json: [
          "kind": "delete",
          "path": "A.swift",
          "expected": "digest",
          "foreign": true,
        ]
      )
    }
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Postcondition(
        json: ["state": "absent", "path": "A.swift", "foreign": true]
      )
    }
    #expect(throws: JSON.Error.self) {
      try Source.Subject.Binding(
        json: ["identity": "subject", "digest": "digest", "foreign": true]
      )
    }
  }
}

extension `Source transport strictness`.Integration {
  @Test
  func `repair plan rejects foreign keys`() {
    #expect(throws: JSON.Error.self) {
      try Source.Repair.Plan(
        json: [
          "schema": Source.Repair.Plan.schema,
          "subject": ["identity": "subject", "digest": "digest"],
          "profile": "profile",
          "sources": "sources",
          "operations": [],
          "refusals": [],
          "postconditions": [],
          "foreign": true,
        ]
      )
    }
  }
}
