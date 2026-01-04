//
//  OnDeviceTrainingManager.swift
//  ATCTranscriber
//
//  Manages on-device model training and personalization
//  Uses CoreML for fine-tuning on user corrections
//

import Foundation
import CoreML
import Combine

/// Manages on-device training for ATC model personalization
class OnDeviceTrainingManager: ObservableObject {

    // MARK: - Properties

    @Published var isTraining = false
    @Published var trainingProgress: Double = 0
    @Published var totalCorrections: Int = 0
    @Published var lastTrainingDate: Date?
    @Published var modelVersion: String = "1.0.0"

    // Training data
    private var trainingExamples: [TrainingExample] = []
    private var pendingCorrections: [TranscriptionCorrection] = []

    // Storage
    private let fileManager = FileManager.default
    private var storageDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Training", isDirectory: true)
    }

    // Training configuration
    private let minExamplesForTraining = 10
    private let batchSize = 8
    private let learningRate: Float = 0.0001
    private let epochs = 3

    // Model updater
    private var modelUpdater: ATCModelUpdater?

    // MARK: - Initialization

    init() {
        createStorageDirectory()
        loadTrainingData()
        modelUpdater = ATCModelUpdater()
    }

    private func createStorageDirectory() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Training Example Management

    /// Add a user correction for training
    func addTrainingExample(_ correction: TranscriptionCorrection) {
        pendingCorrections.append(correction)
        totalCorrections += 1

        // Convert to training example
        let example = TrainingExample(
            id: correction.id,
            inputText: correction.originalTranscription.rawText,
            targetText: correction.correctedText,
            correctionType: correction.correctionType,
            timestamp: correction.timestamp
        )

        trainingExamples.append(example)

        // Save to disk
        saveTrainingData()

        // Check if we should trigger training
        if trainingExamples.count >= minExamplesForTraining && !isTraining {
            Task {
                await triggerTraining()
            }
        }
    }

    /// Remove a training example
    func removeTrainingExample(_ id: UUID) {
        trainingExamples.removeAll { $0.id == id }
        pendingCorrections.removeAll { $0.id == id }
        saveTrainingData()
    }

    /// Clear all training data
    func clearTrainingData() {
        trainingExamples.removeAll()
        pendingCorrections.removeAll()
        totalCorrections = 0
        saveTrainingData()
    }

    // MARK: - Training

    /// Trigger model training with accumulated corrections
    func triggerTraining() async {
        guard !isTraining else { return }
        guard trainingExamples.count >= minExamplesForTraining else {
            print("Not enough examples for training: \(trainingExamples.count)/\(minExamplesForTraining)")
            return
        }

        await MainActor.run {
            isTraining = true
            trainingProgress = 0
        }

        do {
            // Prepare training batch
            let batch = prepareTrainingBatch()

            // Run training
            try await trainModel(with: batch)

            // Update model version
            await MainActor.run {
                self.modelVersion = incrementVersion(self.modelVersion)
                self.lastTrainingDate = Date()
                self.isTraining = false
                self.trainingProgress = 1.0
            }

            // Clear processed examples
            trainingExamples.removeAll()
            saveTrainingData()

        } catch {
            print("Training failed: \(error)")
            await MainActor.run {
                self.isTraining = false
            }
        }
    }

    private func prepareTrainingBatch() -> TrainingBatch {
        // Prepare examples for training
        var inputs: [[Float]] = []
        var targets: [[Int]] = []

        let vocabulary = ATCVocabulary.shared

        for example in trainingExamples {
            // Tokenize input
            let inputTokens = vocabulary.encode(example.inputText)

            // Tokenize target
            let targetTokens = vocabulary.encode(example.targetText)

            // Convert to float array (embeddings would be used in actual implementation)
            let inputFloats = inputTokens.map { Float($0) }

            inputs.append(inputFloats)
            targets.append(targetTokens)
        }

        return TrainingBatch(inputs: inputs, targets: targets)
    }

    private func trainModel(with batch: TrainingBatch) async throws {
        guard let updater = modelUpdater else {
            throw TrainingError.noUpdater
        }

        let totalSteps = epochs * (batch.inputs.count / batchSize + 1)
        var currentStep = 0

        for epoch in 0..<epochs {
            // Shuffle batch
            var indices = Array(0..<batch.inputs.count)
            indices.shuffle()

            // Process in batches
            for batchStart in stride(from: 0, to: indices.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, indices.count)
                let batchIndices = Array(indices[batchStart..<batchEnd])

                let batchInputs = batchIndices.map { batch.inputs[$0] }
                let batchTargets = batchIndices.map { batch.targets[$0] }

                // Update model
                try await updater.updateWeights(
                    inputs: batchInputs,
                    targets: batchTargets,
                    learningRate: learningRate
                )

                currentStep += 1
                let progress = Double(currentStep) / Double(totalSteps)

                await MainActor.run {
                    self.trainingProgress = progress
                }
            }
        }

        // Save updated model
        try await updater.saveModel()
    }

    private func incrementVersion(_ version: String) -> String {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return "1.0.1" }

        return "\(parts[0]).\(parts[1]).\(parts[2] + 1)"
    }

    // MARK: - Persistence

    private func saveTrainingData() {
        let dataFile = storageDirectory.appendingPathComponent("training_examples.json")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(trainingExamples)
            try data.write(to: dataFile)
        } catch {
            print("Failed to save training data: \(error)")
        }
    }

    private func loadTrainingData() {
        let dataFile = storageDirectory.appendingPathComponent("training_examples.json")

        guard fileManager.fileExists(atPath: dataFile.path) else { return }

        do {
            let data = try Data(contentsOf: dataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            trainingExamples = try decoder.decode([TrainingExample].self, from: data)
            totalCorrections = trainingExamples.count
        } catch {
            print("Failed to load training data: \(error)")
        }
    }

    // MARK: - Export/Import

    /// Export training data for backup
    func exportTrainingData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(trainingExamples)
    }

    /// Import training data from backup
    func importTrainingData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([TrainingExample].self, from: data)
        trainingExamples.append(contentsOf: imported)
        saveTrainingData()
    }

    // MARK: - Statistics

    /// Get training statistics
    func getStatistics() -> TrainingStatistics {
        return TrainingStatistics(
            totalExamples: trainingExamples.count,
            pendingCorrections: pendingCorrections.count,
            lastTrainingDate: lastTrainingDate,
            modelVersion: modelVersion,
            canTrain: trainingExamples.count >= minExamplesForTraining
        )
    }
}

// MARK: - Supporting Types

/// A single training example
struct TrainingExample: Codable, Identifiable {
    let id: UUID
    let inputText: String
    let targetText: String
    let correctionType: TranscriptionCorrection.CorrectionType
    let timestamp: Date
}

/// A batch of training data
struct TrainingBatch {
    let inputs: [[Float]]
    let targets: [[Int]]
}

/// Training statistics
struct TrainingStatistics {
    let totalExamples: Int
    let pendingCorrections: Int
    let lastTrainingDate: Date?
    let modelVersion: String
    let canTrain: Bool
}

/// Training errors
enum TrainingError: LocalizedError {
    case noUpdater
    case insufficientData
    case modelUpdateFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noUpdater:
            return "Model updater not initialized"
        case .insufficientData:
            return "Not enough training examples"
        case .modelUpdateFailed:
            return "Failed to update model weights"
        case .saveFailed:
            return "Failed to save updated model"
        }
    }
}

// MARK: - Model Updater

/// Handles the actual model weight updates
class ATCModelUpdater {

    private var modelURL: URL?
    private var compiledModelURL: URL?

    init() {
        loadModel()
    }

    private func loadModel() {
        // Load the updateable CoreML model
        // In production, this would load the .mlmodelc that supports updates
    }

    /// Update model weights with a training step
    func updateWeights(
        inputs: [[Float]],
        targets: [[Int]],
        learningRate: Float
    ) async throws {
        // In production, this would:
        // 1. Forward pass through the model
        // 2. Calculate loss
        // 3. Backward pass (gradient computation)
        // 4. Update weights with gradient descent

        // CoreML on-device training uses MLUpdateTask for this
        // The actual implementation depends on the model architecture

        // Simulate training delay
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    /// Save the updated model
    func saveModel() async throws {
        // Save the updated model to disk
        // This preserves the fine-tuned weights

        guard let modelURL = modelURL else {
            throw TrainingError.saveFailed
        }

        // The updated model would be saved here
        print("Model saved to: \(modelURL)")
    }
}

// MARK: - ATC-Specific Training

extension OnDeviceTrainingManager {

    /// Add vocabulary term learned from corrections
    func learnVocabularyTerm(_ term: String, context: String) {
        // Add to custom vocabulary
        // This helps the model recognize ATC-specific terms

        let example = TrainingExample(
            id: UUID(),
            inputText: context,
            targetText: term,
            correctionType: .transcription,
            timestamp: Date()
        )

        trainingExamples.append(example)
        saveTrainingData()
    }

    /// Train on specific ATC patterns
    func trainOnATCPattern(
        pattern: String,
        examples: [(input: String, output: String)]
    ) async throws {
        for (input, output) in examples {
            let example = TrainingExample(
                id: UUID(),
                inputText: input,
                targetText: output,
                correctionType: .transcription,
                timestamp: Date()
            )
            trainingExamples.append(example)
        }

        saveTrainingData()

        if trainingExamples.count >= minExamplesForTraining {
            await triggerTraining()
        }
    }

    /// Get suggested corrections based on learned patterns
    func getSuggestedCorrection(for text: String) -> String? {
        // Look for similar patterns in training data
        let lowercased = text.lowercased()

        for example in trainingExamples {
            if example.inputText.lowercased().contains(lowercased) ||
               lowercased.contains(example.inputText.lowercased()) {
                return example.targetText
            }
        }

        return nil
    }
}

// MARK: - Create ML Integration (iOS 15+)

@available(iOS 15.0, *)
extension OnDeviceTrainingManager {

    /// Create a custom vocabulary model using Create ML
    func createCustomVocabularyModel(terms: [String]) async throws {
        // This would use Create ML to create a text classifier
        // trained on ATC-specific vocabulary

        // In production:
        // 1. Create training data with labeled ATC terms
        // 2. Train a text classifier
        // 3. Export as CoreML model
        // 4. Integrate with main transcription model

        print("Creating custom vocabulary model with \(terms.count) terms")
    }
}
