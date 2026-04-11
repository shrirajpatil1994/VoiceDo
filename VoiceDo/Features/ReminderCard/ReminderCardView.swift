import SwiftData
import SwiftUI

/// Full reminder detail — opened via notification deep-link or list tap.
struct ReminderCardView: View {

    let reminderId: UUID
    let persistence: PersistenceService

    @State private var reminder: ReminderItem?
    @State private var messageCopied = false
    @State private var alertError: VoiceDoError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            if let reminder {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard(reminder)
                        if let notes = reminder.notes, !notes.isEmpty {
                            fieldBlock(label: "Notes") {
                                Text(notes)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.vdInk)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .vdCard()
                            }
                        }
                        if let draft = reminder.messageDraft {
                            messageDraftCard(draft)
                        } else if !reminder.sourceTranscript.isEmpty {
                            fieldBlock(label: "Captured From") {
                                Text(reminder.sourceTranscript)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.vdMuted)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .vdCard()
                            }
                        }
                        if !reminder.isCompleted {
                            Button {
                                markDone(reminder)
                            } label: {
                                Text("Mark as Done")
                                    .vdPrimaryButton()
                            }
                            .accessibilityLabel("Mark reminder as done")
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Completed")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.vdMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            } else {
                ProgressView()
                    .task { loadReminder() }
            }
        }
        .navigationTitle(reminder?.isCompleted == true ? "Completed" : "Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .alert(error: $alertError)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerCard(_ reminder: ReminderItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let task = reminder.associatedTask {
                Text(task.taskType.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                    .kerning(1)
            }

            Text(reminder.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(reminder.isCompleted ? Color.vdMuted : Color.vdInk)
                .strikethrough(reminder.isCompleted, color: Color.vdMuted)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                Text(reminder.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14))
                if reminder.isOverdue && !reminder.isCompleted {
                    Text("· Overdue")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(reminder.isOverdue && !reminder.isCompleted ? Color(white: 0.3) : Color.vdMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vdCard()
    }

    // MARK: - Message Draft

    @ViewBuilder
    private func messageDraftCard(_ draft: MessageDraft) -> some View {
        fieldBlock(label: draft.platformDisplayName + " Draft") {
            VStack(alignment: .leading, spacing: 10) {
                if let recipient = draft.recipientHint {
                    Text("To: \(recipient)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.vdMuted)
                }
                if let subject = draft.subject {
                    Text("Subject: \(subject)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.vdMuted)
                }
                Text(draft.body)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.vdInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.vdSubtle, in: RoundedRectangle(cornerRadius: 10))

                Button {
                    UIPasteboard.general.string = draft.body
                    messageCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        messageCopied = false
                    }
                } label: {
                    Label(
                        messageCopied ? "Copied" : "Copy Message",
                        systemImage: messageCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vdInk)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.vdCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(Color.vdBorder, lineWidth: 0.5)
                    )
                }
                .animation(.easeInOut(duration: 0.15), value: messageCopied)
            }
            .padding(16)
            .vdCard()
        }
    }

    // MARK: - Field Block

    @ViewBuilder
    private func fieldBlock<Content: View>(
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

    // MARK: - Actions

    private func loadReminder() {
        do {
            reminder = try persistence.fetchReminder(by: reminderId)
        } catch {
            alertError = .persistence(error)
        }
    }

    private func markDone(_ reminder: ReminderItem) {
        do {
            try persistence.markReminderComplete(reminder)
            self.reminder = reminder
            dismiss()
        } catch {
            alertError = .persistence(error)
        }
    }
}

// MARK: - InfoRow (kept for Module4Tests compatibility)

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.vdMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.vdMuted)
                Text(value)
                    .font(.body)
                    .foregroundStyle(Color.vdInk)
            }
        }
        .padding()
        .background(Color.vdSubtle, in: RoundedRectangle(cornerRadius: 12))
    }
}
