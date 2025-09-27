import MapKit
import SwiftUI

final class LocationSearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Logger.log("Location search failed: \(error.localizedDescription)")
    }
}

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = LocationSearchController()

    let onSelect: (String) -> Void

    private var filteredResults: [MKLocalSearchCompletion] {
        let digits = CharacterSet.decimalDigits
        return controller.results.filter { completion in
            completion.subtitle.rangeOfCharacter(from: digits) == nil &&
            completion.title.rangeOfCharacter(from: digits) == nil
        }
    }

    var body: some View {
        NavigationStack {
            List(Array(filteredResults.enumerated()), id: \.offset) { _, completion in
                Button {
                    let displayName = formatted(completion)
                    onSelect(displayName)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(completion.title)
                            .font(.headline)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .overlay {
                if filteredResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: controller.query.isEmpty ? "magnifyingglass" : "hourglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(controller.query.isEmpty ? "Start typing to search for a location." : "Searching…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $controller.query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func formatted(_ completion: MKLocalSearchCompletion) -> String {
        if completion.subtitle.isEmpty {
            return completion.title
        }
        return "\(completion.title), \(completion.subtitle)"
    }
}
