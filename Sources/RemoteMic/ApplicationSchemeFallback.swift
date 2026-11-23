import Foundation

/// 宿主侧按键方案。仅在私有按键方案组件不可用时使用，
/// 用来承接旧 APP 逐项覆盖和 APP 页的方案选择。
struct HostApplicationScheme: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var bindings: [UnifiedButtonBinding]
    var deviceProfileID: UUID?
    var createdAt: Date
}
