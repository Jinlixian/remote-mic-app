import Foundation
import Testing
@testable import RemoteMic

@Suite("Application scheme migration")
struct ApplicationSchemeMigrationTests {
    private func operations(action: ButtonAction) -> [String: ApplicationSchemeOperation] {
        ApplicationSchemeOperation.table { _, _ in
            .init(action: action, shortcut: nil)
        }
    }

    private func candidate(
        _ id: UUID,
        name: String,
        action: ButtonAction
    ) -> ApplicationSchemeMigrationCandidate {
        ApplicationSchemeMigrationCandidate(
            applicationProfileID: id,
            displayName: name,
            operations: operations(action: action),
            bindings: []
        )
    }

    @Test func identicalOperationTablesShareOneGroup() {
        let first = UUID()
        let second = UUID()
        let groups = ApplicationSchemeMigrationPlanner.groups(from: [
            candidate(first, name: "First", action: .commandCopy),
            candidate(second, name: "Second", action: .commandCopy),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].applicationProfileIDs == [first, second])
        #expect(groups[0].primaryDisplayName == "First")
    }

    @Test func differentOperationTablesStaySeparate() {
        let first = UUID()
        let second = UUID()
        let groups = ApplicationSchemeMigrationPlanner.groups(from: [
            candidate(first, name: "First", action: .commandCopy),
            candidate(second, name: "Second", action: .commandPaste),
        ])
        #expect(groups.count == 2)
        #expect(groups[0].applicationProfileIDs == [first])
        #expect(groups[1].applicationProfileIDs == [second])
    }

    @Test func laterDuplicateJoinsTheFirstMatchingGroup() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let groups = ApplicationSchemeMigrationPlanner.groups(from: [
            candidate(first, name: "A", action: .commandCopy),
            candidate(second, name: "B", action: .commandPaste),
            candidate(third, name: "C", action: .commandCopy),
        ])
        #expect(groups.count == 2)
        #expect(groups[0].applicationProfileIDs == [first, third])
        #expect(groups[1].applicationProfileIDs == [second])
    }
}
