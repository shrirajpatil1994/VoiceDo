import SwiftUI
import VoiceDoShared

/// Shown after transcription + parsing. User can edit before saving.
struct VoiceCaptureResultView: View {

    let intent: ParsedIntent
    let persistence: PersistenceService
    let notificationService: NotificationService
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var selectedDate: Date
    @State private var hasDate: Bool
    @State private var selectedCategory: TaskCategory
    @State private var selectedWorkspace: Workspace
    @State private var messageDraft: String
    @State private var messageBodyError: String?
    @State private var isSaving = false
    @State private var alertError: VoiceDoError?
    @State private var widgetReload = WidgetReloadService()

    init(
        intent: ParsedIntent,
        persistence: PersistenceService,
        notificationService: NotificationService,
        onSave: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.intent = intent
        self.persistence = persistence
        self.notificationService = notificationService
        self.onSave = onSave
        self.onDiscard = onDiscard
        _title = State(initialValue: intent.title)
        _notes = State(initialValue: intent.notes ?? "")
        let rawDate = intent.detectedDueDate ?? Date().addingTimeInterval(3600)
        _selectedDate = State(initialValue: OfflineIntentParser.roundToNearest30(rawDate))
        _hasDate = State(initialValue: intent.detectedDueDate != nil || intent.type == .reminder)
        _selectedCategory = State(initialValue: intent.detectedCategory)
        _selectedWorkspace = State(initialValue: intent.detectedWorkspace)
        _messageDraft = State(initialValue: intent.generatedMessageBody ?? "")
        _messageBodyError = State(initialValue: intent.messageBodyError)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vdBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Intent badge
                        intentBadge

                        // Title
                        fieldSection(label: "Title") {
                            TextField("Task title", text: $title)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.vdInk)
                                .foregroundColor(Color.vdInk)
                                .tint(Color.vdInk)
                                .padding(14)
                                .vdCard()
                                .accessibilityLabel("Task title")
                        }

                        // Notes
                        fieldSection(label: "Notes") {
                            TextField("Additional context (optional)", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.vdInk)
                                .foregroundColor(Color.vdInk)
                                .tint(Color.vdInk)
                                .padding(14)
                                .vdCard()
                        }

                        // Category + Workspace
                        fieldSection(label: "Organize") {
                            VStack(spacing: 0) {
                                HStack {
                                    Image(systemName: selectedCategory.systemImageName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.vdMuted)
                                        .frame(width: 20)
                                    Text("Category")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdInk)
                                    Spacer()
                                    Picker("", selection: $selectedCategory) {
                                        ForEach(TaskCategory.allCases, id: \.self) { cat in
                                            Text(cat.displayName).tag(cat)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.vdInk)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider().padding(.leading, 52).foregroundStyle(Color.vdBorder)

                                HStack {
                                    Image(systemName: selectedWorkspace.systemImageName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.vdMuted)
                                        .frame(width: 20)
                                    Text("Workspace")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdInk)
                                    Spacer()
                                    Picker("", selection: $selectedWorkspace) {
                                        ForEach(Workspace.allCases, id: \.self) { ws in
                                            Text(ws.displayName).tag(ws)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.vdInk)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .vdCard()
                        }

                        // Reminder toggle
                        fieldSection(label: "Reminder") {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Set a reminder")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdInk)
                                    Spacer()
                                    Toggle("", isOn: $hasDate)
                                        .labelsHidden()
                                        .tint(Color.vdInk)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                if hasDate {
                                    Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)
                                    DatePicker(
                                        "Due date",
                                        selection: $selectedDate,
                                        in: Date()...,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.compact)
                                    .tint(Color.vdInk)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            }
                            .vdCard()
                        }

                        // Message body (always visible)
                        fieldSection(label: "Message Body") {
                            // Error banner — shown when AI generation failed
                            if let error = messageBodyError, messageDraft.isEmpty {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(white: 0.5))
                                    Text(error)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(white: 0.45))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.vdSubtle, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(white: 0.8), lineWidth: 0.5)
                                )
                            }

                            TextField(
                                messageDraft.isEmpty
                                    ? "Write a message draft manually, or let AI generate one."
                                    : "",
                                text: $messageDraft,
                                axis: .vertical
                            )
                            .lineLimit(4...10)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.vdInk)
                            .foregroundColor(Color.vdInk)
                            .tint(Color.vdInk)
                            .padding(14)
                            .vdCard()
                            // Clear the error banner once the user starts typing
                            .onChange(of: messageDraft) { _, newValue in
                                if !newValue.isEmpty { messageBodyError = nil }
                            }

                            if !messageDraft.isEmpty {
                                Button {
                                    UIPasteboard.general.string = messageDraft
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.vdInk)
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 14)
                                        .background(Color.vdCard, in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(Color.vdBorder, lineWidth: 0.5)
                                        )
                                }
                            }
                        }

                        // AI badge
                        if intent.confidence >= AppConstants.offlineConfidenceThreshold {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                Text("Enhanced with AI")
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Color.vdMuted)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .environment(\.colorScheme, .light)
            .navigationTitle("Review & Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { onDiscard() }
                        .foregroundStyle(Color.vdMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Color.vdInk)
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.vdInk)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert(error: $alertError)
        }
    }

    // MARK: - Field Section Builder

    @ViewBuilder
    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.vdMuted)
                .kerning(0.8)
            content()
        }
    }

    // MARK: - Intent Badge

    private var intentBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: intentIcon)
                .font(.system(size: 13))
            Text(intentLabel)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color.vdMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.vdSubtle, in: Capsule())
    }

    private var intentLabel: String {
        if let task = intent.detectedTaskType { return task.displayName }
        switch intent.type {
        case .todo: return "To-Do"
        case .reminder: return "Reminder"
        case .ambiguous: return "Task"
        }
    }

    private var intentIcon: String {
        if let task = intent.detectedTaskType { return task.systemImageName }
        switch intent.type {
        case .todo: return "checkmark.circle"
        case .reminder: return "bell"
        case .ambiguous: return "questionmark.circle"
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if hasDate {
                try await saveAsReminder()
            } else {
                try saveAsTodo()
            }
            let todos = (try? persistence.fetchAllTodos()) ?? []
            let reminders = (try? persistence.fetchAllReminders()) ?? []
            widgetReload.update(todos: todos, reminders: reminders)
            onSave()
        } catch {
            alertError = .persistence(error)
        }
    }

    private func saveAsTodo() throws {
        let todo = TodoItem(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            category: selectedCategory,
            workspace: selectedWorkspace,
            sourceTranscript: intent.messageContextNotes ?? intent.title,
            wasAIRefined: intent.confidence >= AppConstants.offlineConfidenceThreshold
        )
        try persistence.saveTodo(todo)
    }

    private func saveAsReminder() async throws {
        let reminder = ReminderItem(
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: selectedDate,
            sourceTranscript: intent.messageContextNotes ?? intent.title,
            notes: notes.isEmpty ? nil : notes,
            category: selectedCategory,
            workspace: selectedWorkspace,
            wasAIRefined: intent.confidence >= AppConstants.offlineConfidenceThreshold
        )
        if let taskType = intent.detectedTaskType {
            reminder.associatedTask = AssociatedTask(
                taskType: taskType,
                taskDescription: intent.title
            )
        }
        let draftBody = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftBody.isEmpty {
            reminder.messageDraft = MessageDraft(
                body: draftBody,
                contextNotes: intent.messageContextNotes ?? "",
                recipientHint: intent.recipientHint,
                platformHint: intent.platformHint,
                subject: intent.messageSubject
            )
        }
        try persistence.saveReminder(reminder)
        do {
            try await notificationService.scheduleReminder(reminder)
        } catch {
            alertError = .notification(error)
        }
    }
}

// MARK: - IntentTypeBadge (kept for compatibility)

struct IntentTypeBadge: View {
    let intentType: ParsedIntent.IntentType
    let taskType: AssociatedTaskType?

    var body: some View {
        HStack {
            if let task = taskType {
                Label(task.displayName, systemImage: task.systemImageName)
            } else {
                Label(intentLabel, systemImage: intentIcon)
            }
            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.vdMuted)
    }

    private var intentLabel: String {
        switch intentType {
        case .todo: return "To-Do"
        case .reminder: return "Reminder"
        case .ambiguous: return "Task"
        }
    }

    private var intentIcon: String {
        switch intentType {
        case .todo: return "checkmark.circle"
        case .reminder: return "bell"
        case .ambiguous: return "questionmark.circle"
        }
    }
}

// MARK: - MessageDraftPreviewView (kept for ReminderCardView usage)

struct MessageDraftPreviewView: View {
    let messageBody: String
    let recipientHint: String?
    let platformHint: String?
    let subject: String?

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recipient = recipientHint {
                Text("To: \(recipient)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.vdMuted)
            }
            if let subject {
                Text("Subject: \(subject)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.vdMuted)
            }
            Text(messageBody)
                .font(.system(size: 15))
                .foregroundStyle(Color.vdInk)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.vdSubtle, in: RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = messageBody
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(
                    copied ? "Copied" : "Copy Text",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vdInk)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Color.vdCard, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.vdBorder, lineWidth: 0.5))
            }
            .animation(.easeInOut(duration: 0.15), value: copied)
        }
        .padding(16)
        .vdCard()
    }
}
