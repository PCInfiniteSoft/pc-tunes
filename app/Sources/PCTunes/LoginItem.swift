import ServiceManagement

/// Wraps `SMAppService.mainApp`, which requires the app to run from a signed bundle.
/// `build.sh` ad-hoc signs `PC Tunes.app` so this works for a locally built copy.
enum LoginItem {
    /// `true` once the app is registered, even while macOS is still waiting for the
    /// user to approve it in System Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    /// `true` when registration succeeded but the user has not yet approved the item
    /// in System Settings, so it will not actually launch until they do.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Applies the requested state and reports what the system actually ended up with,
    /// which is not always what was asked for.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[PC Tunes] login item toggle failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
