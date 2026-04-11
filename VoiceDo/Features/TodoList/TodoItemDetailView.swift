import SwiftData
import SwiftUI

struct TodoItemDetailView: View {

    let todoId: UUID
    let persistence: PersistenceService

    @State private var todo: TodoItem?
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editNotes = ""
    @State private var alertError: VoiceDoError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            if let todo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title block
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.vdMuted)
                                .kerning(0.8)
                                .textCase(.uppercase)

                            if isEditing {
                                TextField("Title", text: $editTitle)
                                    .font(.system(size: 17))
                                    .padding(14)
                                    .vdCard()
                            } else {
                                Text(todo.title)
                                    .font(.system(size: 17))
                                    .foregroundStyle(todo.isCompleted ? Color.vdMuted : Color.vdInk)
                                    .strikethrough(todo.isCompleted, color: Color.vdMuted)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .vdCard()
                            }
                        }

                        // Notes block
                        if isEditing || todo.notes?.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.vdMuted)
                                    .kerning(0.8)
                                    .textCase(.uppercase)

                                if isEditing {
                                    TextField(
                                        "Notes (optional)",
                                        text: $editNotes,
                                        axis: .vertical
                                    )
                                    .lineLimit(3...8)
                                    .font(.system(size: 15))
                                    .padding(14)
                                    .vdCard()
                                } else if let notes = todo.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdMuted)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .vdCard()
                                }
                            }
                        }

                        // Meta
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.vdMuted)
                                .kerning(0.8)
                                .textCase(.uppercase)

                            VStack(spacing: 0) {
                                metaRow(
                                    label: "Created",
                                    value: todo.createdAt.formatted(date: .abbreviated, time: .shortened)
                                )
                                if todo.isCompleted, let completedAt = todo.completedAt {
                                    Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)
                                    metaRow(
                                        label: "Completed",
                                        value: completedAt.formatted(date: .abbreviated, time: .shortened)
                                    )
                                }
                                if todo.wasAIRefined {
                                    Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)
                                    HStack {
                                        Text("AI enhanced")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.vdMuted)
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.vdMuted)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            }
                            .vdCard()
                        }

                        // Action
                        Button {
                            toggleComplete(todo)
                        } label: {
                            Text(todo.isCompleted ? "Mark Incomplete" : "Mark Complete")
                                .vdSecondaryButton()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            } else {
                ProgressView()
                    .task { loadTodo() }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if todo != nil {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing, let todo { saveEdits(todo) } else { startEditing() }
                    }
                    .foregroundStyle(Color.vdInk)
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
        }
        .alert(error: $alertError)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.vdMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.vdInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadTodo() {
        todo = try? persistence.fetchAllTodos().first { $0.id == todoId }
    }

    private func startEditing() {
        editTitle = todo?.title ?? ""
        editNotes = todo?.notes ?? ""
        isEditing = true
    }

    private func saveEdits(_ todo: TodoItem) {
        guard !editTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            todo.title = editTitle.trimmingCharacters(in: .whitespaces)
            todo.notes = editNotes.isEmpty ? nil : editNotes
            try persistence.context.save()
            isEditing = false
        } catch {
            alertError = .persistence(error)
        }
    }

    private func toggleComplete(_ todo: TodoItem) {
        do {
            if todo.isCompleted {
                todo.markIncomplete()
                try persistence.context.save()
            } else {
                try persistence.markTodoComplete(todo)
            }
            self.todo = todo
        } catch {
            alertError = .persistence(error)
        }
    }
}
