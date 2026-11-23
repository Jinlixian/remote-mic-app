import Foundation

/// 旧版「按 APP 设置按键」只保存 `buttonBindings`，没有方案引用。
/// 升级时把这类配置物化为键位方案；比较只使用「按键 × 手势 → 操作」，
/// 名称、APP、时间和绑定顺序都不参与，保证相同配置只生成一个方案。
struct ApplicationSchemeMigrationCandidate {
    var applicationProfileID: UUID
    var displayName: String
    var operations: [String: ApplicationSchemeOperation]
    var bindings: [UnifiedButtonBinding]
}

struct ApplicationSchemeMigrationGroup: Equatable {
    var applicationProfileIDs: [UUID]
    var primaryDisplayName: String
    var operations: [String: ApplicationSchemeOperation]
    var bindings: [UnifiedButtonBinding]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.applicationProfileIDs == rhs.applicationProfileIDs &&
            lhs.primaryDisplayName == rhs.primaryDisplayName &&
            lhs.operations == rhs.operations &&
            lhs.bindings == rhs.bindings
    }
}

enum ApplicationSchemeMigrationPlanner {
    /// 同一个操作表只保留一组；组内 APP 共用这一个方案。
    static func groups(from candidates: [ApplicationSchemeMigrationCandidate]) -> [ApplicationSchemeMigrationGroup] {
        var groups: [ApplicationSchemeMigrationGroup] = []
        for candidate in candidates {
            if let index = groups.firstIndex(where: { $0.operations == candidate.operations }) {
                groups[index].applicationProfileIDs.append(candidate.applicationProfileID)
            } else {
                groups.append(ApplicationSchemeMigrationGroup(
                    applicationProfileIDs: [candidate.applicationProfileID],
                    primaryDisplayName: candidate.displayName,
                    operations: candidate.operations,
                    bindings: candidate.bindings
                ))
            }
        }
        return groups
    }
}
