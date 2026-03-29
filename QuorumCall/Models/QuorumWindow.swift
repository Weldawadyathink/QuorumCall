import Foundation
import SwiftData

@Model
final class QuorumWindow {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var windowTitle: String
    /// CGWindowID (UInt32) for stable window identity across title changes. Nil if unavailable.
    var cgWindowID: UInt32?
    var quorum: Quorum?

    init(appBundleID: String, appName: String, windowTitle: String, cgWindowID: UInt32? = nil) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.cgWindowID = cgWindowID
    }
}
