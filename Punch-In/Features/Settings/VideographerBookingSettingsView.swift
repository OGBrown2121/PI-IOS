import SwiftUI

struct VideographerBookingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideographerBookingSettingsViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case location
        case budget
        case projectTemplate
        case gear
    }

    init(viewModel: VideographerBookingSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                Text("Set the details that appear pre-filled when someone opens your booking sheet. Artists can still edit everything before sending their request.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("Schedule") {
                Picker("Preferred production length", selection: $viewModel.defaultDurationSelection) {
                    Text("No preset").tag(nil as Int?)
                    ForEach(viewModel.durationOptions, id: \.self) { value in
                        Text(durationLabel(for: value)).tag(Optional(value))
                    }
                }
                Text("Used as the default session length when the request sheet opens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Location & budget") {
                TextField("Example: Shoots primarily in Atlanta", text: $viewModel.locationNote)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .location)
                TextField("Example: Packages start at $1,200", text: $viewModel.budgetNote)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .budget)
                Text("These answers pre-fill the request form but remain editable for artists.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Project template") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.projectTemplate)
                        .frame(minHeight: 140)
                        .focused($focusedField, equals: .projectTemplate)
                    if viewModel.projectTemplate.isEmpty {
                        Text("Outline your typical workflow, turnaround times, or delivery expectations.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                Text("Appears inside the project details field for artists to review and adjust.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Gear requirements") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.gearRequirements)
                        .frame(minHeight: 120)
                        .focused($focusedField, equals: .gear)
                    if viewModel.gearRequirements.isEmpty {
                        Text("List the gear you bring or need on set—cameras, lighting, audio, crew, or add-ons.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                Text("Displayed as a read-only note so artists know what to account for.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                PrimaryButton(title: viewModel.isSaving ? "Saving…" : "Save Preferences") {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.canSave)

                if viewModel.canClear {
                    Button("Clear All Defaults", role: .destructive) {
                        Task { await viewModel.clearAll() }
                    }
                    .disabled(viewModel.isSaving)
                }

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Booking Defaults")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .background(Theme.appBackground)
        .onChange(of: viewModel.defaultDurationSelection) { _ in viewModel.clearTransientMessages() }
        .onChange(of: viewModel.locationNote) { _ in viewModel.clearTransientMessages() }
        .onChange(of: viewModel.budgetNote) { _ in viewModel.clearTransientMessages() }
        .onChange(of: viewModel.projectTemplate) { _ in viewModel.clearTransientMessages() }
        .onChange(of: viewModel.gearRequirements) { _ in viewModel.clearTransientMessages() }
    }

    private func durationLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours == 0 {
            return "\(remaining)m"
        }
        if remaining == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remaining)m"
    }
}
