import SwiftUI

struct MultiSelectListView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [String]
    let selectionLimit: Int
    @Binding var selections: [String]

    private var selectionRows: [SelectionRow] {
        options.enumerated().map { SelectionRow(id: $0.offset, title: $0.element) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(selectionRows) { row in
                    SelectionButtonRow(
                        title: row.title,
                        isSelected: selections.contains(row.title),
                        isDisabled: isDisabled(for: row.title)
                    ) {
                        toggle(row.title)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(selections.isEmpty)
                }
            }
        }
    }

    private func toggle(_ option: String) {
        if let index = selections.firstIndex(of: option) {
            selections.remove(at: index)
        } else if selections.count < selectionLimit {
            selections.append(option)
        }
    }

    private func isDisabled(for option: String) -> Bool {
        !selections.contains(option) && selections.count >= selectionLimit
    }
}

private struct SelectionRow: Identifiable {
    let id: Int
    let title: String
}

private struct SelectionButtonRow: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .disabled(isDisabled)
    }
}
