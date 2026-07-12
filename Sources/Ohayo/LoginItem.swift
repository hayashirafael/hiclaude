import Foundation
import ServiceManagement

/// SMAppService exige app bundleado; em `swift run` o toggle fica oculto.
enum LoginItem {
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("HiYashi LoginItem: \(error)")
        }
    }
}
