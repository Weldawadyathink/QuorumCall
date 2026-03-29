import Foundation
import SwiftData

@Model
final class QuorumWindow {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var windowTitle: String
    var quorum: Quorum?

    init(appBundleID: String, appName: String, windowTitle: String) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
    }
}
