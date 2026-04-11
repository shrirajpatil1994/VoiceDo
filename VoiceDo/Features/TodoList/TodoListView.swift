import SwiftData
import SwiftUI
import VoiceDoShared

struct TodoListView: View {

    let persistence: PersistenceService

    @Query(sort: \TodoItem.createdAt, order: .reverse)
    private var todos: [TodoItem]

    @State private var showCompleted = false
    @State private var alertError: VoiceDoError?

    private var filtered: [TodoItem] {
        showCompleted ? todos : todos.filter { !$0.isCompleted }
    }

    private var grouped: [(TaskCategory, [TodoItem])] {
        let dict = Dictionary(grouping: filtered) { $0.category }
        return TaskCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: showCompleted ? "tray" : "checkmark.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.vdMuted)
                    Text(showCompleted ? "No tasks" : "All done")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.vdInk)
                    Text(
                        showCompleted
                            ? "Press and hold the mic on the home screen to create a task."
                            : "No incomplete tasks."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.vdMuted)
                    .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(grouped, id: \.0) { category, items in
                            categorySection(category: category, items: items)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCompleted.toggle()
                } label: {
                    Text(showCompleted ? "Hide done" : "Show done")
                        .font(.subheadline)
                        .foregroundStyle(Color.vdInk)
                }
            }
        }
        .alert(error: $alertError)
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(category: TaskCategory, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImageName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                Text(category.displayName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                    .kerning(0.8)
            }

            VStack(spacing: 0) {
                ForEach(items) { todo in
                    NavigationLink(value: NavigationDestination.todoDetail(id: todo.id)) {
                        TodoRow(todo: todo) { toggleComplete(todo) }
                    }
                    .buttonStyle(.plain)

                    if todo.id != items.last?.id {
                        Divider()
                            .padding(.leading, 54)
                            .foregroundStyle(Color.vdBorder)
                    }
                }
            }
            .vdCard()
        }
    }

    // MARK: - Actions

    private func toggleComplete(_ todo: TodoItem) {
        do {
            if todo.isCompleted {
                todo.markIncomplete()
                try persistence.context.save()
            } else {
                try persistence.markTodoComplete(todo)
            }
        } catch {
            alertError = .persistence(error)
        }
    }
}
