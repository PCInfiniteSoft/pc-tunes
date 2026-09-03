import ServiceManagement

/// Wraps `SMAppService.mainApp`, which requires the app to run from a signed bundle.
/// `build.sh` ad-hoc signs `PC Tunes.app` so this works for a locally built copy.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[PC Tunes] login item toggle failed: \(error.localizedDescription)")
        }
    }
}
