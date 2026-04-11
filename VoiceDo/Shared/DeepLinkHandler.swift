import Foundation
import VoiceDoShared

// MARK: - NavigationDestination

/// All deep-link destinations in the app.
enum NavigationDestination: Hashable {
    case reminderCard(id: UUID)
    case todoDetail(id: UUID)
    case voiceCapture
}

// MARK: - DeepLinkHandler

/// Parses `voicedo://` URLs into typed `NavigationDestination` values.
///
/// URL scheme: `voicedo://<host>/<path>`
/// Supported:
///   `voicedo://reminder/<uuid>`  → `.reminderCard(id:)`
///   `voicedo://todo/<uuid>`      → `.todoDetail(id:)`
///   `voicedo://capture`          → `.voiceCapture`
enum DeepLinkHandler {

    static func destination(from url: URL) -> NavigationDestination? {
        guard url.scheme == AppConstants.urlScheme else { return nil }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "reminder":
            guard let idString = pathComponents.first,
                  let id = UUID(uuidString: idString) else { return nil }
            return .reminderCard(id: id)

        case "todo":
            guard let idString = pathComponents.first,
                  let id = UUID(uuidString: idString) else { return nil }
            return .todoDetail(id: id)

        case "capture":
            return .voiceCapture

        default:
            return nil
        }
    }
}
