//
//  ContentView.swift
//  ATCTranscriber
//
//  Main view for ATC transcription interface
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptionView()
                .tabItem {
                    Label("Transcribe", systemImage: "waveform")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .accentColor(.blue)
    }
}

// MARK: - Transcription View

struct TranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingCorrection = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // AIRAC Status
                AIRACStatusBanner()

                // Audio Level Meter
                AudioLevelMeter(level: appState.audioManager.audioLevel)
                    .frame(height: 30)
                    .padding(.horizontal)

                // Record Button
                RecordButton(
                    isRecording: appState.isRecording,
                    isProcessing: appState.isProcessing
                ) {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                }

                // Status Text
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Transcription Result
                if let transcription = appState.currentTranscription {
                    TranscriptionResultView(
                        transcription: transcription,
                        validationResults: appState.validationResults,
                        onCorrect: { showingCorrection = true }
                    )
                } else {
                    PlaceholderView()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("ATC Transcriber")
            .sheet(isPresented: $showingCorrection) {
                if let transcription = appState.currentTranscription {
                    CorrectionView(transcription: transcription) { correction in
                        appState.submitCorrection(correction)
                    }
                }
            }
        }
    }

    private var statusText: String {
        if appState.isProcessing {
            return "Processing audio..."
        } else if appState.isRecording {
            return "Listening for ATC communications..."
        } else {
            return "Tap the button to start recording"
        }
    }
}

// MARK: - AIRAC Status Banner

struct AIRACStatusBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let cycle = appState.airacCycle {
            HStack {
                Image(systemName: cycle.isActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(cycle.isActive ? .green : .orange)

                VStack(alignment: .leading) {
                    Text("AIRAC \(cycle.cycleNumber)")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(cycle.isActive ? "Valid until \(formattedDate(cycle.expirationDate))" : "Expired - Update Required")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if cycle.daysUntilExpiration <= 7 && cycle.daysUntilExpiration > 0 {
                    Text("\(cycle.daysUntilExpiration)d")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    let level: Float

    private var normalizedLevel: CGFloat {
        // Convert dB to 0-1 range (-60dB to 0dB)
        let normalized = CGFloat((level + 60) / 60)
        return max(0, min(1, normalized))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                // Level indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * normalizedLevel)
                    .animation(.easeOut(duration: 0.1), value: normalizedLevel)
            }
        }
    }

    private var levelColor: Color {
        if normalizedLevel > 0.8 {
            return .red
        } else if normalizedLevel > 0.6 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Record Button

struct RecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.blue)
                    .frame(width: 80, height: 80)
                    .shadow(color: (isRecording ? Color.red : Color.blue).opacity(0.3), radius: 10)

                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(isProcessing)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }
}

// MARK: - Placeholder View

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No transcription yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Record ATC communications to see transcription and validation results")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}

// MARK: - Transcription Result View

struct TranscriptionResultView: View {
    let transcription: ATCTranscription
    let validationResults: [ValidationResult]
    let onCorrect: () -> Void

    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                // Confidence indicator
                ConfidenceBadge(confidence: transcription.confidence)
            }

            // Main transcription text
            Text(transcription.normalizedText)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(10)

            // Extracted elements
            if transcription.callsign != nil ||
               !transcription.frequencies.isEmpty ||
               !transcription.altitudes.isEmpty {
                ExtractedElementsView(transcription: transcription)
            }

            // Validation results
            if !validationResults.isEmpty {
                ValidationResultsView(results: validationResults)
            }

            // Action buttons
            HStack {
                Button(action: onCorrect) {
                    Label("Correct", systemImage: "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { showingDetails.toggle() }) {
                    Label("Details", systemImage: "info.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5)
        .padding(.horizontal)
        .sheet(isPresented: $showingDetails) {
            TranscriptionDetailsView(transcription: transcription)
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: confidenceIcon)
                .foregroundColor(confidenceColor)

            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.15))
        .cornerRadius(8)
    }

    private var confidenceIcon: String {
        if confidence >= 0.9 {
            return "checkmark.circle.fill"
        } else if confidence >= 0.7 {
            return "exclamationmark.circle.fill"
        } else {
            return "questionmark.circle.fill"
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.9 {
            return .green
        } else if confidence >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Extracted Elements View

struct ExtractedElementsView: View {
    let transcription: ATCTranscription

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extracted Elements")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let callsign = transcription.callsign {
                        ElementChip(icon: "airplane", text: callsign, color: .blue)
                    }

                    ForEach(transcription.frequencies, id: \.self) { freq in
                        ElementChip(icon: "antenna.radiowaves.left.and.right", text: freq.formatted, color: .purple)
                    }

                    ForEach(transcription.altitudes, id: \.self) { alt in
                        ElementChip(icon: "arrow.up.and.down", text: alt.formatted, color: .orange)
                    }

                    ForEach(transcription.headings, id: \.self) { hdg in
                        ElementChip(icon: "safari", text: "HDG \(hdg)", color: .green)
                    }

                    ForEach(transcription.waypoints, id: \.self) { wpt in
                        ElementChip(icon: "mappin", text: wpt, color: .red)
                    }
                }
            }
        }
    }
}

struct ElementChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(16)
    }
}

// MARK: - Validation Results View

struct ValidationResultsView: View {
    let results: [ValidationResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Validation")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(results.prefix(3)) { result in
                ValidationResultRow(result: result)
            }

            if results.count > 3 {
                Text("+ \(results.count - 3) more...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ValidationResultRow: View {
    let result: ValidationResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.message)
                    .font(.caption)

                if let suggestion = result.suggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var severityIcon: String {
        switch result.severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        case .valid:
            return "checkmark.circle.fill"
        }
    }

    private var severityColor: Color {
        switch result.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        case .valid:
            return .green
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
