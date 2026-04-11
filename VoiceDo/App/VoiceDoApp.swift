import SwiftData
import SwiftUI
import VoiceDoShared

@main
struct VoiceDoApp: App {

    @State private var persistenceService: PersistenceService?
    @State private var notificationService = NotificationService()
    @State private var navigationPath = NavigationPath()
    @State private var pendingDestination: NavigationDestination?
    @State private var showVoiceCapture = false

    /// True when the app was opened from the widget — show MinimalCaptureView instead of ContentRootView.
    @State private var isMinimalMode = false
    /// Stores the deep-link intent while services are still initialising.
    @State private var pendingMinimalMode = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let persistence = persistenceService {
                    if isMinimalMode {
                        MinimalCaptureView(
                            persistence: persistence,
                            notificationService: notificationService,
                            onDone: { isMinimalMode = false }
                        )
                        .modelContainer(persistence.container)
                    } else {
                        ContentRootView(
                            persistence: persistence,
                            notificationService: notificationService,
                            showVoiceCapture: $showVoiceCapture,
                            pendingDestination: $pendingDestination
                        )
                        .modelContainer(persistence.container)
                    }
                } else {
                    ProgressView("Loading…")
                        .task { await initializeServices() }
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .reminderMarkedDoneFromNotification
                )
            ) { notification in
                guard let id = notification.userInfo?["reminderId"] as? UUID else { return }
                Task { @MainActor in
                    guard let service = persistenceService,
                          let reminder = try? service.fetchReminder(by: id) else { return }
                    try? service.markReminderComplete(reminder)
                }
            }
        }
    }

    // MARK: - Initialization

    @MainActor
    private func initializeServices() async {
        notificationService.registerCategories()
        // Request notification permission at every launch (idempotent — returns fast if already granted).
        _ = try? await notificationService.requestPermission()
        do {
            persistenceService = try PersistenceService()
        } catch {
            // Catastrophic — show error UI in production; for now crash-loudly in debug
            fatalError("Failed to initialize SwiftData: \(error)")
        }
        // Handle deep-link that arrived before services were ready.
        if pendingMinimalMode {
            pendingMinimalMode = false
            isMinimalMode = true
        }
    }

    // MARK: - Deep Link

    private func handleDeepLink(_ url: URL) {
        guard let destination = DeepLinkHandler.destination(from: url) else { return }
        switch destination {
        case .voiceCapture:
            if persistenceService != nil {
                // App already running — switch to minimal capture mode.
                isMinimalMode = true
            } else {
                // App is still starting up — flag it and handle after init.
                pendingMinimalMode = true
            }
        default:
            pendingDestination = destination
        }
    }
}
