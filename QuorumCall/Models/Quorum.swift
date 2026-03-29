import Foundation
import SwiftData

@Model
final class Quorum {
    var id: UUID = UUID()
    var name: String
    var order: Int
    var shortcutKeyCode: Int?
    var shortcutModifiers: UInt32?

    @Relationship(deleteRule: .cascade, inverse: \QuorumWindow.quorum)
    var windows: [QuorumWindow] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }
}
