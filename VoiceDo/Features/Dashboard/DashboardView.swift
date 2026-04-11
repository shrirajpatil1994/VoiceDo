import SwiftData
import SwiftUI
import VoiceDoShared

struct DashboardView: View {

    let persistence: PersistenceService
    let notificationService: NotificationService

    @Binding var showVoiceCapture: Bool

    @Query(
        filter: #Predicate<TodoItem> { !$0.isCompleted },
        sort: \TodoItem.createdAt, order: .reverse
    )
    private var incompleteTodos: [TodoItem]

    @Query(
        filter: #Predicate<ReminderItem> { !$0.isCompleted },
        sort: \ReminderItem.dueDate
    )
    private var upcomingReminders: [ReminderItem]

    // MARK: - Recording State

    @State private var captureViewModel = VoiceCaptureViewModel()
    @State private var isLocked = false
    @State private var dragOffset: CGFloat = 0
    @State private var showResult = false
    @State private var alertError: VoiceDoError?
    @State private var showManualCreate = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.vdBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !todayReminders.isEmpty {
                            sectionBlock(title: "Due today") {
                                ForEach(todayReminders) { reminder in
                                    NavigationLink(
                                        value: NavigationDestination.reminderCard(id: reminder.id)
                                    ) {
                                        ReminderRow(reminder: reminder)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Todos grouped by category
                        let grouped = Dictionary(grouping: incompleteTodos.prefix(20)) { $0.category }
                        ForEach(TaskCategory.allCases, id: \.self) { cat in
                            if let items = grouped[cat], !items.isEmpty {
                                sectionBlock(
                                    title: cat.displayName,
                                    icon: cat.systemImageName
                                ) {
                                    ForEach(items) { todo in
                                        NavigationLink(
                                            value: NavigationDestination.todoDetail(id: todo.id)
                                        ) {
                                            TodoRow(todo: todo) { completeTodo(todo) }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if incompleteTodos.isEmpty && upcomingReminders.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mic")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(Color.vdMuted)
                                Text("Nothing here yet")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(Color.vdInk)
                                Text("Press and hold the mic to capture your first task.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.vdMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    await recategoriseAll()
                }

                // Recording FAB
                recordingFAB
            }
            .navigationTitle("VoiceDo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManualCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.vdInk)
                    }
                    .accessibilityLabel("Create item manually")
                }
            }
            .navigationDestination(for: NavigationDestination.self) { dest in
                switch dest {
                case .reminderCard(let id):
                    ReminderCardView(reminderId: id, persistence: persistence)
                case .todoDetail(let id):
                    TodoItemDetailView(todoId: id, persistence: persistence)
                case .voiceCapture:
                    EmptyView()
                }
            }
            .alert(error: $alertError)
        }
        .sheet(
            isPresented: $showResult,
            onDismiss: {
                captureViewModel.resetToIdle()
                isLocked = false
            },
            content: {
                if let intent = captureViewModel.parsedResult {
                    VoiceCaptureResultView(
                        intent: intent,
                        persistence: persistence,
                        notificationService: notificationService,
                        onSave: { showResult = false },
                        onDiscard: { showResult = false }
                    )
                }
            }
        )
        .sheet(isPresented: $showManualCreate) {
            VoiceCaptureResultView(
                intent: ParsedIntent.blank,
                persistence: persistence,
                notificationService: notificationService,
                onSave: { showManualCreate = false },
                onDiscard: { showManualCreate = false }
            )
        }
        .onChange(of: captureViewModel.parsedResult) { _, result in
            if result != nil { showResult = true }
        }
        .onChange(of: captureViewModel.error?.id) { _, errId in
            if errId != nil { alertError = captureViewModel.error }
        }
        // Handle URL-triggered recording (from widget or Siri)
        .onChange(of: showVoiceCapture) { _, shouldStart in
            if shouldStart && captureViewModel.state == .idle {
                showVoiceCapture = false
                Task { await captureViewModel.startCapture() }
            }
        }
        .task {
            await captureViewModel.requestPermissions()
        }
    }

    // MARK: - Recording FAB

    private var recordingFAB: some View {
        VStack(spacing: 12) {
            // Lock indicator — slides up when dragging up
            if captureViewModel.state == .recording {
                lockHint
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Send button when locked
            if isLocked && captureViewModel.state == .recording {
                sendButton
                    .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                // Pulse ring when recording
                if captureViewModel.state == .recording {
                    Circle()
                        .stroke(Color.vdInk.opacity(0.15), lineWidth: 2)
                        .frame(width: 88, height: 88)
                        .scaleEffect(1.0)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: captureViewModel.state == .recording
                        )
                }

                // State feedback ring
                if captureViewModel.state == .processing || captureViewModel.state == .refining {
                    ProgressView()
                        .tint(Color.vdInk)
                        .scaleEffect(1.2)
                        .frame(width: 88, height: 88)
                }

                // Mic button
                Circle()
                    .fill(captureViewModel.state == .recording ? Color(white: 0.15) : Color.vdInk)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .overlay {
                        Image(systemName: captureViewModel.state == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(dragOffset < -20 ? 1.1 : 1.0)
                    .animation(.spring(duration: 0.2), value: dragOffset)
            }
            .gesture(recordGesture)
            .accessibilityLabel(
                captureViewModel.state == .recording
                    ? "Release to stop recording"
                    : "Press and hold to record"
            )
            .disabled(
                captureViewModel.state == .processing ||
                captureViewModel.state == .refining ||
                captureViewModel.state == .done
            )
        }
        .animation(.spring(duration: 0.25), value: isLocked)
        .animation(.spring(duration: 0.25), value: captureViewModel.state)
        .padding(.bottom, 32)
    }

    private var lockHint: some View {
        HStack(spacing: 6) {
            Image(systemName: isLocked ? "lock.fill" : "arrow.up")
                .font(.system(size: 11))
            Text(isLocked ? "Locked — tap Send" : "Drag up to lock")
                .font(.system(size: 12))
        }
        .foregroundStyle(Color.vdMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.vdCard, in: Capsule())
        .overlay(Capsule().stroke(Color.vdBorder, lineWidth: 0.5))
    }

    private var sendButton: some View {
        Button {
            Task { await captureViewModel.stopCapture() }
            isLocked = false
        } label: {
            Text("Send")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.vdInk, in: Capsule())
        }
    }

    // MARK: - Gesture

    private var recordGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.height
                // Start recording on first touch
                if captureViewModel.state == .idle {
                    Task { await captureViewModel.startCapture() }
                }
                // Lock if dragged up beyond threshold
                if value.translation.height < -60 && !isLocked {
                    isLocked = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { _ in
                dragOffset = 0
                // Only auto-stop if not locked
                if !isLocked && captureViewModel.state == .recording {
                    Task { await captureViewModel.stopCapture() }
                }
            }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func sectionBlock<Content: View>(
        title: String,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.vdMuted)
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                    .kerning(0.8)
            }

            VStack(spacing: 0) {
                content()
            }
            .vdCard()
        }
    }

    // MARK: - Computed

    private var todayReminders: [ReminderItem] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return upcomingReminders.filter { $0.dueDate >= start && $0.dueDate < end }
    }

    // MARK: - Actions

    private func completeTodo(_ todo: TodoItem) {
        do {
            try persistence.markTodoComplete(todo)
        } catch {
            alertError = .persistence(error)
        }
    }

    // MARK: - Pull-to-Refresh Re-categorisation

    @MainActor
    private func recategoriseAll() async {
        let todos = (try? persistence.fetchAllTodos()) ?? []
        for todo in todos {
            let result = OfflineIntentParser.quickParse(todo.sourceTranscript)
            if result.category != todo.category || result.workspace != todo.workspace {
                todo.category = result.category
                todo.workspace = result.workspace
            }
        }
        let reminders = (try? persistence.fetchAllReminders()) ?? []
        for reminder in reminders {
            let result = OfflineIntentParser.quickParse(reminder.sourceTranscript)
            if result.category != reminder.category || result.workspace != reminder.workspace {
                reminder.category = result.category
                reminder.workspace = result.workspace
            }
        }
    }
}

// MARK: - TodoRow

struct TodoRow: View {
    let todo: TodoItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onComplete) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(todo.isCompleted ? Color.vdMuted : Color.vdInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.system(size: 15))
                    .foregroundStyle(todo.isCompleted ? Color.vdMuted : Color.vdInk)
                    .strikethrough(todo.isCompleted, color: Color.vdMuted)
                if let notes = todo.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Color.vdMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.vdBorder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - ReminderRow

struct ReminderRow: View {
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reminder.associatedTask.map { taskIcon($0.taskType) } ?? "bell")
                .font(.system(size: 16))
                .foregroundStyle(Color.vdMuted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 15))
                    .foregroundStyle(reminder.isCompleted ? Color.vdMuted : Color.vdInk)
                    .strikethrough(reminder.isCompleted, color: Color.vdMuted)
                Text(reminder.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(reminder.isOverdue ? Color(white: 0.3) : Color.vdMuted)
            }

            Spacer()

            if reminder.messageDraft != nil {
                Image(systemName: "envelope")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.vdMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.vdBorder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func taskIcon(_ type: AssociatedTaskType) -> String {
        switch type {
        case .message: return "envelope"
        case .purchase: return "bag"
        case .deadline: return "calendar"
        case .call: return "phone"
        case .other: return "bell"
        }
    }
}

// MARK: - SectionHeader (kept for backwards compat)

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(Color.vdInk)
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.vdMuted)
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.vdInk)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.vdMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
