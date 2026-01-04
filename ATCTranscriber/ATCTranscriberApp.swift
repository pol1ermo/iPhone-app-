//
//  ATCTranscriberApp.swift
//  ATCTranscriber
//
//  ATC Audio Transcription and Validation System
//  Runs locally on iPhone with CoreML
//

import SwiftUI

@main
struct ATCTranscriberApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Global application state
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var currentTranscription: ATCTranscription?
    @Published var validationResults: [ValidationResult] = []
    @Published var airacCycle: AIRACCycle?

    let audioManager: AudioCaptureManager
    let speechService: ATCSpeechRecognitionService
    let validationEngine: ATCValidationEngine
    let airacManager: AIRACManager
    let trainingManager: OnDeviceTrainingManager

    init() {
        self.audioManager = AudioCaptureManager()
        self.speechService = ATCSpeechRecognitionService()
        self.validationEngine = ATCValidationEngine()
        self.airacManager = AIRACManager()
        self.trainingManager = OnDeviceTrainingManager()

        setupBindings()
    }

    private func setupBindings() {
        // Sync AIRAC cycle from manager
        airacCycle = airacManager.currentCycle

        // Audio manager callbacks
        audioManager.onAudioCaptured = { [weak self] audioData in
            self?.processAudio(audioData)
        }
    }

    func startRecording() {
        isRecording = true
        audioManager.startCapture()
    }

    func stopRecording() {
        isRecording = false
        audioManager.stopCapture()
    }

    private func processAudio(_ audioData: AudioData) {
        Task { @MainActor in
            self.isProcessing = true
        }

        Task {
            // Transcribe audio using local model
            let transcription = await speechService.transcribe(audioData)

            // Validate against AIRAC and common sense rules
            let validation = await validationEngine.validate(
                transcription: transcription,
                airacCycle: airacManager.currentCycle
            )

            await MainActor.run {
                self.currentTranscription = transcription
                self.validationResults = validation
                self.isProcessing = false
            }
        }
    }

    /// Submit a correction for training
    func submitCorrection(_ correction: TranscriptionCorrection) {
        trainingManager.addTrainingExample(correction)
    }
}
