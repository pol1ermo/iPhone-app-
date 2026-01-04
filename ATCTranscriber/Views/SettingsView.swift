//
//  SettingsView.swift
//  ATCTranscriber
//
//  App settings and training management
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("autoValidate") private var autoValidate = true
    @AppStorage("showConfidence") private var showConfidence = true
    @AppStorage("vadThreshold") private var vadThreshold: Double = -40
    @AppStorage("selectedLanguage") private var selectedLanguage = "en-US"

    @State private var showingAIRACUpdate = false
    @State private var showingTrainingStats = false

    var body: some View {
        NavigationView {
            Form {
                // Recognition Settings
                Section(header: Text("Recognition")) {
                    Picker("Language", selection: $selectedLanguage) {
                        Text("English (US)").tag("en-US")
                        Text("English (UK)").tag("en-GB")
                        Text("German").tag("de-DE")
                        Text("French").tag("fr-FR")
                        Text("Spanish").tag("es-ES")
                    }
                    .onChange(of: selectedLanguage) { _ in
                        appState.speechService.setLanguage(selectedLanguage)
                    }

                    Toggle("Auto-validate transcriptions", isOn: $autoValidate)

                    Toggle("Show confidence scores", isOn: $showConfidence)
                }

                // Audio Settings
                Section(header: Text("Audio")) {
                    VStack(alignment: .leading) {
                        Text("Voice Activity Threshold")
                            .font(.subheadline)

                        HStack {
                            Text("\(Int(vadThreshold)) dB")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(value: $vadThreshold, in: -60...(-20), step: 5)
                                .onChange(of: vadThreshold) { _ in
                                    appState.audioManager.setVADThreshold(Float(vadThreshold))
                                }
                        }
                    }

                    Button("Capture Noise Profile") {
                        appState.audioManager.captureNoiseProfile()
                    }

                    Button("Reset Noise Profile") {
                        appState.audioManager.resetNoiseProfile()
                    }
                }

                // AIRAC Settings
                Section(header: Text("AIRAC Data")) {
                    if let cycle = appState.airacCycle {
                        HStack {
                            Text("Current Cycle")
                            Spacer()
                            Text(cycle.cycleNumber)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            if cycle.isActive {
                                Text("Active")
                                    .foregroundColor(.green)
                            } else {
                                Text("Expired")
                                    .foregroundColor(.red)
                            }
                        }

                        if cycle.isActive {
                            HStack {
                                Text("Expires In")
                                Spacer()
                                Text("\(cycle.daysUntilExpiration) days")
                                    .foregroundColor(cycle.daysUntilExpiration < 7 ? .orange : .secondary)
                            }
                        }
                    }

                    Button("Check for Updates") {
                        showingAIRACUpdate = true
                    }
                }

                // Training Settings
                Section(header: Text("Model Training")) {
                    HStack {
                        Text("Model Version")
                        Spacer()
                        Text(appState.trainingManager.modelVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Training Examples")
                        Spacer()
                        Text("\(appState.trainingManager.totalCorrections)")
                            .foregroundColor(.secondary)
                    }

                    if let lastTraining = appState.trainingManager.lastTrainingDate {
                        HStack {
                            Text("Last Training")
                            Spacer()
                            Text(formattedDate(lastTraining))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("View Training Statistics") {
                        showingTrainingStats = true
                    }

                    if appState.trainingManager.totalCorrections >= 10 {
                        Button("Train Model Now") {
                            Task {
                                await appState.trainingManager.triggerTraining()
                            }
                        }
                        .disabled(appState.trainingManager.isTraining)
                    }

                    Button("Clear Training Data", role: .destructive) {
                        appState.trainingManager.clearTrainingData()
                    }
                }

                // About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    if let docsURL = URL(string: "https://example.com/docs") {
                        Link("Documentation", destination: docsURL)
                    }

                    if let privacyURL = URL(string: "https://example.com/privacy") {
                        Link("Privacy Policy", destination: privacyURL)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAIRACUpdate) {
                AIRACUpdateView()
            }
            .sheet(isPresented: $showingTrainingStats) {
                TrainingStatsView()
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - AIRAC Update View

struct AIRACUpdateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isChecking = false
    @State private var updateAvailable = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isChecking {
                    ProgressView("Checking for updates...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)

                        Text(error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if updateAvailable {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text("Update Available")
                            .font(.headline)

                        Text("A new AIRAC cycle is available for download")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Download Update") {
                            // Download update
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.green)

                        Text("Up to Date")
                            .font(.headline)

                        Text("You have the latest AIRAC data")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("AIRAC Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkForUpdates()
            }
        }
    }

    private func checkForUpdates() {
        isChecking = true

        // Simulate update check
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isChecking = false
            updateAvailable = false
        }
    }
}

// MARK: - Training Stats View

struct TrainingStatsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Training progress if active
                if appState.trainingManager.isTraining {
                    VStack(spacing: 16) {
                        ProgressView(value: appState.trainingManager.trainingProgress)
                            .progressViewStyle(LinearProgressViewStyle())

                        Text("Training in progress...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("\(Int(appState.trainingManager.trainingProgress * 100))%")
                            .font(.headline)
                    }
                    .padding()
                }

                // Statistics
                let stats = appState.trainingManager.getStatistics()

                VStack(alignment: .leading, spacing: 16) {
                    StatRow(label: "Total Examples", value: "\(stats.totalExamples)")
                    StatRow(label: "Pending Corrections", value: "\(stats.pendingCorrections)")
                    StatRow(label: "Model Version", value: stats.modelVersion)
                    StatRow(label: "Can Train", value: stats.canTrain ? "Yes" : "No")

                    if let lastDate = stats.lastTrainingDate {
                        StatRow(label: "Last Training", value: formatTrainingDate(lastDate))
                    }
                }
                .padding()

                Spacer()

                // Train button
                if stats.canTrain && !appState.trainingManager.isTraining {
                    Button("Start Training") {
                        Task {
                            await appState.trainingManager.triggerTraining()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .navigationTitle("Training Statistics")
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

    private func formatTrainingDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
