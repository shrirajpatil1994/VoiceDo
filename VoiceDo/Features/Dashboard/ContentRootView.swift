import SwiftUI
import VoiceDoShared

/// Root container: tab bar + deep-link navigation handler.
struct ContentRootView: View {

    let persistence: PersistenceService
    let notificationService: NotificationService

    @Binding var showVoiceCapture: Bool
    @Binding var pendingDestination: NavigationDestination?

    @State private var selectedTab = 0
    @State private var reminderNavigationPath = NavigationPath()
    @State private var todoNavigationPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                persistence: persistence,
                notificationService: notificationService,
                showVoiceCapture: $showVoiceCapture
            )
            .tabItem { Label("Today", systemImage: "house") }
            .tag(0)

            NavigationStack(path: $todoNavigationPath) {
                TodoListView(persistence: persistence)
                    .navigationDestination(for: NavigationDestination.self) {
                        destinationView($0, persistence: persistence)
                    }
            }
            .tabItem { Label("Tasks", systemImage: "checklist") }
            .tag(1)

            NavigationStack(path: $reminderNavigationPath) {
                ReminderListView(
                    persistence: persistence,
                    notificationService: notificationService
                )
                .navigationDestination(for: NavigationDestination.self) {
                    destinationView($0, persistence: persistence)
                }
            }
            .tabItem { Label("Reminders", systemImage: "bell") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(3)
        }
        .tint(Color.vdInk)
        .onChange(of: pendingDestination) { _, dest in
            guard let dest else { return }
            navigateTo(dest)
            pendingDestination = nil
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ destination: NavigationDestination) {
        switch destination {
        case .reminderCard:
            selectedTab = 2
            reminderNavigationPath.append(destination)
        case .todoDetail:
            selectedTab = 1
            todoNavigationPath.append(destination)
        case .voiceCapture:
            showVoiceCapture = true
        }
    }

    @ViewBuilder
    private func destinationView(
        _ destination: NavigationDestination,
        persistence: PersistenceService
    ) -> some View {
        switch destination {
        case .reminderCard(let id):
            ReminderCardView(reminderId: id, persistence: persistence)
        case .todoDetail(let id):
            TodoItemDetailView(todoId: id, persistence: persistence)
        case .voiceCapture:
            EmptyView()
        }
    }
}
