//
//  HistoryView.swift
//  ATCTranscriber
//
//  View for browsing transcription history
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var historyManager = TranscriptionHistoryManager()

    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedEntry: TranscriptionHistoryEntry?

    var body: some View {
        NavigationView {
            VStack {
                // Filter buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(HistoryFilter.allCases, id: \.self) { filter in
                            FilterButton(
                                title: filter.title,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                // History list
                if filteredEntries.isEmpty {
                    EmptyHistoryView()
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            HistoryEntryRow(entry: entry)
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: historyManager.exportHistory) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive, action: historyManager.clearHistory) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                HistoryDetailView(entry: entry)
            }
        }
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        var entries = historyManager.entries

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .validated:
            entries = entries.filter { $0.wasValidated }
        case .errors:
            entries = entries.filter { $0.hadErrors }
        case .corrected:
            entries = entries.filter { $0.userCorrected }
        }

        // Apply search
        if !searchText.isEmpty {
            entries = entries.filter { entry in
                entry.transcription.normalizedText.localizedCaseInsensitiveContains(searchText) ||
                (entry.transcription.callsign?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return entries
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            historyManager.delete(filteredEntries[index])
        }
    }
}

// MARK: - History Filter

enum HistoryFilter: CaseIterable {
    case all
    case validated
    case errors
    case corrected

    var title: String {
        switch self {
        case .all: return "All"
        case .validated: return "Validated"
        case .errors: return "With Errors"
        case .corrected: return "Corrected"
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: TranscriptionHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if let callsign = entry.transcription.callsign {
                    Text(callsign)
                        .font(.headline)
                }

                Spacer()

                Text(formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Transcription preview
            Text(entry.transcription.normalizedText)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(.secondary)

            // Status indicators
            HStack(spacing: 8) {
                if entry.wasValidated {
                    StatusBadge(icon: "checkmark.shield", text: "Validated", color: .green)
                }

                if entry.hadErrors {
                    StatusBadge(icon: "exclamationmark.triangle", text: "Errors", color: .orange)
                }

                if entry.userCorrected {
                    StatusBadge(icon: "pencil", text: "Corrected", color: .blue)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.transcription.timestamp, relativeTo: Date())
    }
}

struct StatusBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(8)
    }
}

// MARK: - Empty History View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No History")
                .font(.headline)

            Text("Transcriptions will appear here after you record ATC communications")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - History Detail View

struct HistoryDetailView: View {
    let entry: TranscriptionHistoryEntry
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Transcription
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcription")
                            .font(.headline)

                        Text(entry.transcription.normalizedText)
                            .font(.body)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.headline)

                        DetailRow(label: "Time", value: formattedDate)
                        DetailRow(label: "Confidence", value: "\(Int(entry.transcription.confidence * 100))%")
                        DetailRow(label: "Processing Time", value: String(format: "%.2fs", entry.transcription.processingTime))

                        if let callsign = entry.transcription.callsign {
                            DetailRow(label: "Callsign", value: callsign)
                        }
                    }

                    // Extracted data
                    if !entry.transcription.frequencies.isEmpty ||
                       !entry.transcription.altitudes.isEmpty ||
                       !entry.transcription.waypoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted Data")
                                .font(.headline)

                            if !entry.transcription.frequencies.isEmpty {
                                DetailRow(
                                    label: "Frequencies",
                                    value: entry.transcription.frequencies.map { $0.formatted }.joined(separator: ", ")
                                )
                            }

                            if !entry.transcription.altitudes.isEmpty {
                                DetailRow(
                                    label: "Altitudes",
                                    value: entry.transcription.altitudes.map { $0.formatted }.joined(separator: ", ")
                                )
                            }

                            if !entry.transcription.waypoints.isEmpty {
                                DetailRow(
                                    label: "Waypoints",
                                    value: entry.transcription.waypoints.joined(separator: ", ")
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: entry.transcription.timestamp)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

// MARK: - History Manager

class TranscriptionHistoryManager: ObservableObject {
    @Published var entries: [TranscriptionHistoryEntry] = []

    private let fileManager = FileManager.default
    private var storageURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history.json")
    }

    init() {
        loadHistory()
    }

    func add(_ transcription: ATCTranscription, validated: Bool, hadErrors: Bool) {
        let entry = TranscriptionHistoryEntry(
            transcription: transcription,
            wasValidated: validated,
            hadErrors: hadErrors,
            sessionId: UUID()
        )
        entries.insert(entry, at: 0)
        saveHistory()
    }

    func delete(_ entry: TranscriptionHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        entries.removeAll()
        saveHistory()
    }

    func exportHistory() {
        // Export functionality
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([TranscriptionHistoryEntry].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
