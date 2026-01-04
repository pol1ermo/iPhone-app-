//
//  ATCLanguageModel.swift
//  ATCTranscriber
//
//  Custom CoreML-based language model for ATC speech recognition
//  Runs entirely on-device using Neural Engine
//

import Foundation
import CoreML
import Accelerate

/// Custom on-device language model for ATC transcription
class ATCLanguageModel: ObservableObject {

    // MARK: - Properties

    @Published var isLoaded = false
    @Published var modelVersion: String = "1.0.0"

    private var whisperModel: WhisperATCModel?
    private var decoderModel: ATCDecoderModel?
    private var vocabulary: ATCVocabulary?

    // Model configuration
    private let maxSequenceLength = 448
    private let audioContextLength = 1500  // 30 seconds at 50 tokens/sec
    private let nMels = 80
    private let sampleRate = 16000


    // MARK: - Initialization

    init() {
        Task {
            await loadModels()
        }
        vocabulary = ATCVocabulary.shared
    }

    private func loadModels() async {
        // Configuration for CoreML model loading
        // Will be used when actual model files are bundled
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use .all for iOS 15 compatibility

        // Try to load the model if it exists
        if let modelURL = Bundle.main.url(forResource: "WhisperATCEncoder", withExtension: "mlmodelc") {
            print("Loading WhisperATC model from: \(modelURL)")
            // TODO: Load actual model with: try? MLModel(contentsOf: modelURL, configuration: config)
        }

        // For now, we'll use a simulated model
        // In production, this would load the actual CoreML model
        whisperModel = WhisperATCModel()
        decoderModel = ATCDecoderModel()
        _ = config  // Silence unused variable warning until model loading is implemented

        await MainActor.run {
            self.isLoaded = true
        }
    }

    // MARK: - Transcription

    /// Transcribe audio using the on-device model
    func transcribe(_ audioData: AudioData) async -> String {
        guard isLoaded else { return "" }

        // Preprocess audio to mel spectrogram
        let melSpectrogram = preprocessAudio(audioData)

        // Encode audio features
        let audioFeatures = await encodeAudio(melSpectrogram)

        // Decode to text tokens
        let tokens = await decodeTokens(audioFeatures)

        // Convert tokens to text
        let text = tokensToText(tokens)

        return text
    }

    // MARK: - Audio Preprocessing

    private func preprocessAudio(_ audioData: AudioData) -> [[Float]] {
        // Ensure correct sample rate
        var samples = audioData.samples
        if audioData.sampleRate != Double(sampleRate) {
            samples = resample(samples, from: audioData.sampleRate, to: Double(sampleRate))
        }

        // Pad or trim to 30 seconds
        let targetLength = sampleRate * 30
        if samples.count < targetLength {
            samples.append(contentsOf: [Float](repeating: 0, count: targetLength - samples.count))
        } else if samples.count > targetLength {
            samples = Array(samples.prefix(targetLength))
        }

        // Compute mel spectrogram
        let melSpec = computeMelSpectrogram(samples)

        return melSpec
    }

    private func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let newLength = Int(Double(samples.count) * ratio)

        var output = [Float](repeating: 0, count: newLength)

        for i in 0..<newLength {
            let srcIndex = Double(i) / ratio
            let srcIndexFloor = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexFloor))

            if srcIndexFloor + 1 < samples.count {
                output[i] = samples[srcIndexFloor] * (1 - fraction) +
                           samples[srcIndexFloor + 1] * fraction
            } else if srcIndexFloor < samples.count {
                output[i] = samples[srcIndexFloor]
            }
        }

        return output
    }

    private func computeMelSpectrogram(_ samples: [Float]) -> [[Float]] {
        let nFft = 400
        let hopLength = 160
        let numFrames = (samples.count - nFft) / hopLength + 1

        var melSpec: [[Float]] = []

        for frame in 0..<numFrames {
            let start = frame * hopLength
            let end = min(start + nFft, samples.count)

            var window = Array(samples[start..<end])
            if window.count < nFft {
                window.append(contentsOf: [Float](repeating: 0, count: nFft - window.count))
            }

            // Apply Hanning window
            window = applyHanningWindow(window)

            // Compute FFT magnitudes
            let magnitudes = computeFFT(window)

            // Apply mel filterbank
            let melFrame = applyMelFilterbank(magnitudes)

            melSpec.append(melFrame)
        }

        // Normalize
        melSpec = normalizeMelSpectrogram(melSpec)

        return melSpec
    }

    private func applyHanningWindow(_ samples: [Float]) -> [Float] {
        var output = samples
        let n = samples.count

        for i in 0..<n {
            let window = 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(n - 1)))
            output[i] *= window
        }

        return output
    }

    private func computeFFT(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let log2n = vDSP_Length(log2(Float(n)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: n/2)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = samples
        var imagPart = [Float](repeating: 0, count: n)

        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

        var magnitudes = [Float](repeating: 0, count: n/2)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))

        return magnitudes
    }

    private func applyMelFilterbank(_ magnitudes: [Float]) -> [Float] {
        var melFrame = [Float](repeating: 0, count: nMels)

        let fMin: Float = 0
        let fMax = Float(sampleRate) / 2
        let nFft = magnitudes.count

        func hzToMel(_ hz: Float) -> Float {
            return 2595 * log10(1 + hz / 700)
        }

        func melToHz(_ mel: Float) -> Float {
            return 700 * (pow(10, mel / 2595) - 1)
        }

        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)
        let melPoints = (0...nMels+1).map { i in
            melToHz(melMin + Float(i) * (melMax - melMin) / Float(nMels + 1))
        }

        let fftFreqs = (0..<nFft).map { Float($0) * Float(sampleRate) / Float(nFft * 2) }

        for m in 0..<nMels {
            let fLeft = melPoints[m]
            let fCenter = melPoints[m + 1]
            let fRight = melPoints[m + 2]

            for k in 0..<nFft {
                let freq = fftFreqs[k]

                if freq >= fLeft && freq <= fCenter {
                    let weight = (freq - fLeft) / (fCenter - fLeft)
                    melFrame[m] += magnitudes[k] * weight
                } else if freq > fCenter && freq <= fRight {
                    let weight = (fRight - freq) / (fRight - fCenter)
                    melFrame[m] += magnitudes[k] * weight
                }
            }
        }

        // Log scale
        for i in 0..<nMels {
            melFrame[i] = log10(max(melFrame[i], 1e-10))
        }

        return melFrame
    }

    private func normalizeMelSpectrogram(_ melSpec: [[Float]]) -> [[Float]] {
        guard !melSpec.isEmpty else { return melSpec }

        var normalized = melSpec

        // Global normalization
        var allValues: [Float] = melSpec.flatMap { $0 }
        var mean: Float = 0
        var std: Float = 0
        vDSP_normalize(&allValues, 1, nil, 1, &mean, &std, vDSP_Length(allValues.count))

        if std > 0 {
            for i in 0..<normalized.count {
                for j in 0..<normalized[i].count {
                    normalized[i][j] = (normalized[i][j] - mean) / std
                }
            }
        }

        return normalized
    }

    // MARK: - Model Inference

    private func encodeAudio(_ melSpectrogram: [[Float]]) async -> [Float] {
        // Flatten mel spectrogram for model input
        let flattened = melSpectrogram.flatMap { $0 }

        // In production, this would run the actual CoreML encoder
        // For now, return simulated features
        guard let model = whisperModel else {
            return Array(repeating: 0, count: 512)
        }

        return await model.encode(flattened)
    }

    private func decodeTokens(_ audioFeatures: [Float]) async -> [Int] {
        guard let decoder = decoderModel else {
            return []
        }

        return await decoder.decode(audioFeatures, vocabulary: vocabulary)
    }

    private func tokensToText(_ tokens: [Int]) -> String {
        guard let vocab = vocabulary else { return "" }

        return vocab.decode(tokens)
    }
}

// MARK: - Whisper Encoder Model Wrapper

/// Wrapper for the Whisper-style audio encoder
class WhisperATCModel {

    private var encoderModel: MLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        // Load the CoreML encoder model
        // In production, this would load the actual .mlmodelc file
    }

    func encode(_ melSpectrogram: [Float]) async -> [Float] {
        // Run encoder inference
        // For now, return simulated audio features

        // This simulates the encoder output
        // Actual implementation would use CoreML prediction
        return Array(repeating: Float.random(in: -1...1), count: 512)
    }
}

// MARK: - Decoder Model Wrapper

/// Wrapper for the text decoder with ATC vocabulary
class ATCDecoderModel {

    private var decoderModel: MLModel?
    private let beamWidth = 5
    private let maxTokens = 448

    init() {
        loadModel()
    }

    private func loadModel() {
        // Load the CoreML decoder model
    }

    func decode(_ audioFeatures: [Float], vocabulary: ATCVocabulary?) async -> [Int] {
        // Run autoregressive decoding with beam search
        // For demonstration, return empty - actual implementation would run the decoder

        var tokens: [Int] = []

        // Start token
        tokens.append(vocabulary?.startToken ?? 50258)

        // Decode loop would go here
        // Using beam search for better results

        return tokens
    }
}

// MARK: - ATC Vocabulary

/// Vocabulary for ATC-specific tokens and terms
class ATCVocabulary {

    static let shared = ATCVocabulary()

    // Special tokens
    let startToken = 50258
    let endToken = 50257
    let padToken = 50259
    let transcribeToken = 50260

    // Token mappings
    private var tokenToWord: [Int: String] = [:]
    private var wordToToken: [String: Int] = [:]

    // ATC-specific terms
    private var atcTerms: Set<String> = []

    init() {
        loadVocabulary()
        loadATCTerms()
    }

    private func loadVocabulary() {
        // Load base vocabulary from bundled file
        // This would contain ~50k tokens for Whisper-style models

        // For demo, add common words
        let commonWords = [
            "the", "a", "is", "to", "and", "of", "in", "for", "on", "at",
            "climb", "descend", "maintain", "turn", "left", "right", "heading",
            "altitude", "flight", "level", "contact", "tower", "approach",
            "departure", "center", "ground", "cleared", "runway", "taxi",
            "takeoff", "landing", "speed", "knots", "feet", "thousand",
            "hundred", "zero", "one", "two", "three", "four", "five",
            "six", "seven", "eight", "nine", "niner", "decimal"
        ]

        for (index, word) in commonWords.enumerated() {
            tokenToWord[index] = word
            wordToToken[word] = index
        }
    }

    private func loadATCTerms() {
        atcTerms = Set([
            // Instructions
            "climb", "descend", "maintain", "turn", "contact", "squawk",
            "cleared", "hold", "proceed", "expect", "report", "taxi",
            "takeoff", "land", "go-around", "expedite", "reduce", "increase",

            // Positions/Facilities
            "tower", "approach", "departure", "center", "ground", "atis",
            "clearance", "radar", "control",

            // Altitudes
            "flight", "level", "feet", "altitude", "thousand", "hundred",

            // Headings/Directions
            "heading", "left", "right", "direct", "intercept", "radial",

            // Speeds
            "knots", "mach", "speed", "airspeed", "groundspeed",

            // Runways
            "runway", "localizer", "glideslope", "approach", "departure",
            "final", "base", "downwind", "crosswind",

            // Numbers (spoken)
            "zero", "one", "two", "three", "four", "five",
            "six", "seven", "eight", "nine", "niner",

            // Phonetic alphabet
            "alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
            "golf", "hotel", "india", "juliet", "kilo", "lima", "mike",
            "november", "oscar", "papa", "quebec", "romeo", "sierra",
            "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",

            // Common phrases
            "roger", "wilco", "affirmative", "negative", "standby",
            "say again", "read back", "unable", "request"
        ])
    }

    /// Check if a term is ATC-specific
    func isATCTerm(_ term: String) -> Bool {
        return atcTerms.contains(term.lowercased())
    }

    /// Encode text to tokens
    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = [startToken]

        let words = text.lowercased().split(separator: " ")
        for word in words {
            if let token = wordToToken[String(word)] {
                tokens.append(token)
            } else {
                // Unknown word - use subword tokenization in production
                tokens.append(0)  // UNK token
            }
        }

        tokens.append(endToken)
        return tokens
    }

    /// Decode tokens to text
    func decode(_ tokens: [Int]) -> String {
        var words: [String] = []

        for token in tokens {
            if token == startToken || token == endToken || token == padToken {
                continue
            }

            if let word = tokenToWord[token] {
                words.append(word)
            }
        }

        return words.joined(separator: " ")
    }

    /// Get vocabulary size
    var size: Int {
        return tokenToWord.count
    }
}
