import SwiftUI

struct EngineerAvailabilityManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EngineerAvailabilityManagementViewModel

    @State private var blockStart = Date()
    @State private var blockEnd = Date().addingTimeInterval(3600)
    @State private var blockNotes: String = ""

    init(
        engineer: UserProfile,
        firestore: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?,
        onProfileUpdate: @escaping (UserProfile) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: EngineerAvailabilityManagementViewModel(
                engineer: engineer,
                firestore: firestore,
                currentUserProvider: currentUserProvider,
                onProfileUpdate: onProfileUpdate
            )
        )
    }

    var body: some View {
        List {
            premiumSection
            studiosSection
            availabilitySection
            addBlockSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Engineer Availability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task { await viewModel.load() }
        .alert("Update", isPresented: Binding(
            get: { viewModel.statusMessage != nil },
            set: { newValue in
                if newValue == false { viewModel.statusMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) { viewModel.statusMessage = nil }
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
    }

    private var premiumSection: some View {
        Section("Session Approvals") {
            Toggle("Premium plan", isOn: Binding(
                get: { viewModel.engineer.engineerSettings.isPremium },
                set: { newValue in Task { await viewModel.togglePremium(newValue) } }
            ))
            .toggleStyle(.switch)

            Toggle("Engineer must approve sessions", isOn: Binding(
                get: { !viewModel.engineer.engineerSettings.instantBookEnabled },
                set: { newValue in Task { await viewModel.setEngineerRequiresApproval(newValue) } }
            ))
            .toggleStyle(.switch)

            Text("Turn this off to auto-confirm sessions when your premium plan is active and the studio already approved.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Allow other studios", isOn: Binding(
                get: { viewModel.engineer.engineerSettings.allowOtherStudios },
                set: { newValue in Task { await viewModel.toggleAllowOtherStudios(newValue) } }
            ))

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var studiosSection: some View {
        Section("Studios") {
            if viewModel.linkedStudios.isEmpty {
                Text("No studios connected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Main studio", selection: Binding(
                    get: { viewModel.engineer.engineerSettings.mainStudioId ?? "" },
                    set: { newValue in
                        Task { await viewModel.setMainStudio(newValue.isEmpty ? nil : newValue) }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(viewModel.linkedStudios) { studio in
                        Text(studio.name).tag(studio.id)
                    }
                }
                if let selectedAt = viewModel.engineer.engineerSettings.mainStudioSelectedAt {
                    Text("Selected on \(selectedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var availabilitySection: some View {
        Section("Blocks & Holds") {
            if viewModel.availabilityEntries.isEmpty {
                Text("No blocks yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.availabilityEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: entry))
                            .font(.subheadline.weight(.semibold))
                        if let start = entry.startDate, let end = entry.endDate {
                            Text("\(formatted(date: start)) – \(formatted(date: end))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let note = entry.notes, note.isEmpty == false {
                            Text(note)
                                .font(.footnote)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteEntry(entry) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var addBlockSection: some View {
        Section("Schedule Block") {
            DatePicker("Start", selection: $blockStart, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $blockEnd, displayedComponents: [.date, .hourAndMinute])
                .onChangeCompatibility(of: blockStart) { newValue in
                    if blockEnd <= newValue {
                        blockEnd = newValue.addingTimeInterval(3600)
                    }
                }
            TextField("Note", text: $blockNotes)
            Button("Add Block") {
                Task { await viewModel.addBlock(start: blockStart, end: blockEnd, note: blockNotes) }
            }
            Button("Add Self-Booking") {
                Task { await viewModel.addSelfBooking(start: blockStart, end: blockEnd, note: blockNotes) }
            }
            .tint(.orange)
        }
    }

    private func title(for entry: AvailabilityEntry) -> String {
        switch entry.kind {
        case .block:
            return "Block"
        case .bookingHold:
            return "Booking hold"
        case .selfBooking:
            return "Self booking"
        case .recurring:
            return "Recurring"
        }
    }

    private func formatted(date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
