//
//  AudioCaptureManager.swift
//  ATCTranscriber
//
//  Handles audio capture from device microphone
//  Optimized for aviation radio audio characteristics
//

import Foundation
import AVFoundation
import Accelerate

/// Manages audio capture and preprocessing for ATC communications
class AudioCaptureManager: NSObject, ObservableObject {

    // MARK: - Properties

    @Published var isCapturing = false
    @Published var audioLevel: Float = 0
    @Published var noiseFloor: Float = -60

    /// Callback when audio is captured
    var onAudioCaptured: ((AudioData) -> Void)?

    /// Callback for real-time audio level updates
    var onAudioLevelUpdate: ((Float) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []

    // Audio settings optimized for radio communications
    private let sampleRate: Double = 16000  // Optimal for speech
    private let bufferSize: AVAudioFrameCount = 4096

    // Voice Activity Detection
    private var vadThreshold: Float = -40
    private var silenceFrames = 0
    private let maxSilenceFrames = 30  // ~0.5 seconds at typical frame rate

    // Noise reduction
    private var noiseProfile: [Float] = []
    private var isNoiseProfileCaptured = false

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.01)  // 10ms buffer
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Capture Control

    /// Start capturing audio
    func startCapture() {
        guard !isCapturing else { return }

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        inputNode = engine.inputNode
        guard let input = inputNode else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            isCapturing = true
            audioBuffer.removeAll()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    /// Stop capturing audio
    func stopCapture() {
        guard isCapturing else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        isCapturing = false

        // Process remaining buffer
        if !audioBuffer.isEmpty {
            let audioData = createAudioData(from: audioBuffer)
            onAudioCaptured?(audioData)
            audioBuffer.removeAll()
        }
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Calculate audio level
        let level = calculateRMSLevel(samples)
        DispatchQueue.main.async {
            self.audioLevel = level
            self.onAudioLevelUpdate?(level)
        }

        // Apply preprocessing
        samples = applyPreprocessing(samples)

        // Voice Activity Detection
        if level > vadThreshold {
            // Voice detected
            audioBuffer.append(contentsOf: samples)
            silenceFrames = 0
        } else {
            // Silence
            silenceFrames += 1

            // Keep some trailing silence
            if silenceFrames <= 5 {
                audioBuffer.append(contentsOf: samples)
            }

            // If enough silence and we have data, trigger callback
            if silenceFrames >= maxSilenceFrames && !audioBuffer.isEmpty {
                let audioData = createAudioData(from: audioBuffer)
                onAudioCaptured?(audioData)
                audioBuffer.removeAll()
            }
        }
    }

    // MARK: - Preprocessing

    private func applyPreprocessing(_ samples: [Float]) -> [Float] {
        var processed = samples

        // Apply high-pass filter (remove low frequency noise)
        processed = applyHighPassFilter(processed, cutoff: 300)

        // Apply band-pass filter for voice frequencies
        processed = applyBandPassFilter(processed, lowCutoff: 300, highCutoff: 3400)

        // Apply noise reduction if profile is available
        if isNoiseProfileCaptured {
            processed = applyNoiseReduction(processed)
        }

        // Normalize amplitude
        processed = normalizeAmplitude(processed)

        return processed
    }

    /// High-pass filter to remove low-frequency rumble
    private func applyHighPassFilter(_ samples: [Float], cutoff: Float) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // Simple one-pole high-pass filter
        let rc = 1.0 / (2.0 * Float.pi * cutoff)
        let dt = 1.0 / Float(sampleRate)
        let alpha = rc / (rc + dt)

        output[0] = samples[0]
        for i in 1..<samples.count {
            output[i] = alpha * (output[i-1] + samples[i] - samples[i-1])
        }

        return output
    }

    /// Band-pass filter for voice frequencies (300Hz - 3400Hz typical for aviation radio)
    private func applyBandPassFilter(_ samples: [Float], lowCutoff: Float, highCutoff: Float) -> [Float] {
        // Apply high-pass then low-pass
        var output = applyHighPassFilter(samples, cutoff: lowCutoff)

        // Low-pass filter
        let rc = 1.0 / (2.0 * Float.pi * highCutoff)
        let dt = 1.0 / Float(sampleRate)
        let alpha = dt / (rc + dt)

        for i in 1..<output.count {
            output[i] = output[i-1] + alpha * (output[i] - output[i-1])
        }

        return output
    }

    /// Apply spectral noise reduction
    private func applyNoiseReduction(_ samples: [Float]) -> [Float] {
        guard !noiseProfile.isEmpty else { return samples }

        // Simplified spectral subtraction
        var output = samples

        // Apply gain reduction based on noise floor
        let noiseReduction: Float = 0.7
        for i in 0..<output.count {
            let reduction = noiseProfile.count > i ? noiseProfile[i] * noiseReduction : 0
            output[i] = max(output[i] - reduction, 0)
        }

        return output
    }

    /// Normalize amplitude to [-1, 1] range
    private func normalizeAmplitude(_ samples: [Float]) -> [Float] {
        var maxVal: Float = 0
        vDSP_maxmgv(samples, 1, &maxVal, vDSP_Length(samples.count))

        guard maxVal > 0 else { return samples }

        var output = samples
        var scale = 0.9 / maxVal  // Leave some headroom
        vDSP_vsmul(samples, 1, &scale, &output, 1, vDSP_Length(samples.count))

        return output
    }

    // MARK: - Audio Level

    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        // Convert to dB
        let db = 20 * log10(max(rms, 0.0001))
        return db
    }

    // MARK: - Noise Profile

    /// Capture noise profile for reduction
    func captureNoiseProfile() {
        guard !audioBuffer.isEmpty else { return }

        noiseProfile = audioBuffer.suffix(Int(sampleRate))  // Last second
        isNoiseProfileCaptured = true

        // Calculate noise floor
        noiseFloor = calculateRMSLevel(Array(noiseProfile))
        vadThreshold = noiseFloor + 10  // Set VAD threshold above noise floor
    }

    /// Reset noise profile
    func resetNoiseProfile() {
        noiseProfile.removeAll()
        isNoiseProfileCaptured = false
        vadThreshold = -40
    }

    // MARK: - Helper Methods

    private func createAudioData(from samples: [Float]) -> AudioData {
        let duration = Double(samples.count) / sampleRate

        return AudioData(
            samples: samples,
            sampleRate: sampleRate,
            duration: duration,
            timestamp: Date()
        )
    }

    /// Set Voice Activity Detection threshold
    func setVADThreshold(_ threshold: Float) {
        vadThreshold = threshold
    }

    /// Get current audio buffer duration
    var currentBufferDuration: TimeInterval {
        Double(audioBuffer.count) / sampleRate
    }
}

// MARK: - Audio Format Conversion

extension AudioCaptureManager {

    /// Convert audio to format suitable for ML model
    func convertToModelFormat(_ audioData: AudioData, targetSampleRate: Double = 16000) -> [Float] {
        guard audioData.sampleRate != targetSampleRate else {
            return audioData.samples
        }

        // Resample if needed
        let ratio = targetSampleRate / audioData.sampleRate
        let newLength = Int(Double(audioData.samples.count) * ratio)

        var output = [Float](repeating: 0, count: newLength)

        // Linear interpolation resampling
        for i in 0..<newLength {
            let srcIndex = Double(i) / ratio
            let srcIndexFloor = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexFloor))

            if srcIndexFloor + 1 < audioData.samples.count {
                output[i] = audioData.samples[srcIndexFloor] * (1 - fraction) +
                           audioData.samples[srcIndexFloor + 1] * fraction
            } else if srcIndexFloor < audioData.samples.count {
                output[i] = audioData.samples[srcIndexFloor]
            }
        }

        return output
    }

    /// Convert samples to mel spectrogram for Whisper-like models
    func computeMelSpectrogram(_ samples: [Float], nMels: Int = 80, hopLength: Int = 160) -> [[Float]] {
        let fftSize = 400
        var melSpectrogram: [[Float]] = []

        // Compute STFT
        let numFrames = (samples.count - fftSize) / hopLength + 1

        for frame in 0..<numFrames {
            let start = frame * hopLength
            let end = min(start + fftSize, samples.count)
            var windowedSamples = Array(samples[start..<end])

            // Apply Hanning window
            windowedSamples = applyHanningWindow(windowedSamples, size: fftSize)

            // Compute magnitude spectrum
            let magnitudes = computeFFTMagnitudes(windowedSamples)

            // Convert to mel scale
            let melFrame = applyMelFilterbank(magnitudes, nMels: nMels, sampleRate: Float(sampleRate))
            melSpectrogram.append(melFrame)
        }

        return melSpectrogram
    }

    private func applyHanningWindow(_ samples: [Float], size: Int) -> [Float] {
        var output = [Float](repeating: 0, count: size)
        var window = [Float](repeating: 0, count: size)

        // Generate Hanning window
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        // Apply window
        let count = min(samples.count, size)
        for i in 0..<count {
            output[i] = samples[i] * window[i]
        }

        return output
    }

    private func computeFFTMagnitudes(_ samples: [Float]) -> [Float] {
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

    private func applyMelFilterbank(_ magnitudes: [Float], nMels: Int, sampleRate: Float) -> [Float] {
        // Simplified mel filterbank application
        let nFft = magnitudes.count
        var melFrame = [Float](repeating: 0, count: nMels)

        let fMin: Float = 0
        let fMax = sampleRate / 2

        // Compute mel frequencies
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

        // Convert to FFT bins
        let fftFreqs = (0..<nFft).map { Float($0) * sampleRate / Float(nFft * 2) }

        // Apply triangular filters
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

        // Convert to log scale
        for i in 0..<nMels {
            melFrame[i] = log10(max(melFrame[i], 1e-10))
        }

        return melFrame
    }
}
