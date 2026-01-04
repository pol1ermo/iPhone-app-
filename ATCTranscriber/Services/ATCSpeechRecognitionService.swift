//
//  ATCSpeechRecognitionService.swift
//  ATCTranscriber
//
//  Hybrid speech recognition using Apple Speech + Custom CoreML model
//  Optimized for ATC phraseology and radio communications
//

import Foundation
import Speech
import CoreML
import NaturalLanguage

/// Speech recognition service specialized for ATC communications
class ATCSpeechRecognitionService: NSObject, ObservableObject {

    // MARK: - Properties

    @Published var isAvailable = false
    @Published var currentLanguage: String = "en-US"

    private var speechRecognizer: SFSpeechRecognizer?
    private var atcLanguageModel: ATCLanguageModel?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Model configuration
    private var useHybridMode = true  // Combine Apple + Custom model
    private var atcVocabulary: ATCVocabulary?

    // Performance tracking
    private var lastProcessingTime: TimeInterval = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupRecognizer()
        loadATCModel()
        loadVocabulary()
    }

    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLanguage))
        speechRecognizer?.delegate = self

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAvailable = (status == .authorized)
            }
        }
    }

    private func loadATCModel() {
        // Load custom CoreML model for ATC
        atcLanguageModel = ATCLanguageModel()
    }

    private func loadVocabulary() {
        atcVocabulary = ATCVocabulary.shared
    }

    // MARK: - Transcription

    /// Transcribe audio data to text with ATC-specific processing
    func transcribe(_ audioData: AudioData) async -> ATCTranscription {
        let startTime = Date()

        // Run both recognition methods in parallel if hybrid mode
        async let appleResult = transcribeWithAppleSpeech(audioData)
        async let customResult = transcribeWithCustomModel(audioData)

        let (appleTranscript, customTranscript) = await (appleResult, customResult)

        // Merge results with custom model prioritized for ATC terms
        let mergedText = mergeTranscriptions(apple: appleTranscript, custom: customTranscript)

        // Normalize ATC phraseology
        let normalizedText = normalizeATCPhraseology(mergedText)

        // Extract ATC elements
        let extraction = extractATCElements(from: normalizedText)

        let processingTime = Date().timeIntervalSince(startTime)
        lastProcessingTime = processingTime

        return ATCTranscription(
            rawText: mergedText,
            normalizedText: normalizedText,
            segments: extraction.segments,
            confidence: extraction.confidence,
            timestamp: audioData.timestamp,
            processingTime: processingTime,
            callsign: extraction.callsign,
            instructions: extraction.instructions,
            frequencies: extraction.frequencies,
            altitudes: extraction.altitudes,
            headings: extraction.headings,
            speeds: extraction.speeds,
            waypoints: extraction.waypoints
        )
    }

    // MARK: - Apple Speech Recognition

    private func transcribeWithAppleSpeech(_ audioData: AudioData) async -> String {
        guard isAvailable, let recognizer = speechRecognizer else {
            return ""
        }

        return await withCheckedContinuation { continuation in
            // Convert audio data to URL or buffer
            let tempURL = saveAudioToTempFile(audioData)
            guard let url = tempURL else {
                continuation.resume(returning: "")
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.taskHint = .dictation

            // Add ATC vocabulary hints if available (iOS 17+)
            if #available(iOS 17, *) {
                request.addsPunctuation = false
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                defer {
                    try? FileManager.default.removeItem(at: url)
                }

                if let error = error {
                    print("Speech recognition error: \(error)")
                    continuation.resume(returning: "")
                    return
                }

                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private func saveAudioToTempFile(_ audioData: AudioData) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        // Create WAV file header and data
        guard let wavData = createWAVData(from: audioData) else { return nil }

        do {
            try wavData.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to write audio file: \(error)")
            return nil
        }
    }

    private func createWAVData(from audioData: AudioData) -> Data? {
        var data = Data()

        let sampleRate = UInt32(audioData.sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * UInt32(channels) * UInt32(bytesPerSample)
        let blockAlign = channels * bytesPerSample

        // Convert float samples to Int16
        let int16Samples = audioData.samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        let dataSize = UInt32(int16Samples.count * Int(bytesPerSample))
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        for sample in int16Samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        return data
    }

    // MARK: - Custom CoreML Model Recognition

    private func transcribeWithCustomModel(_ audioData: AudioData) async -> String {
        guard let model = atcLanguageModel else { return "" }

        return await model.transcribe(audioData)
    }

    // MARK: - Result Merging

    private func mergeTranscriptions(apple: String, custom: String) -> String {
        guard !apple.isEmpty && !custom.isEmpty else {
            return apple.isEmpty ? custom : apple
        }

        // Use custom model for ATC-specific terms, Apple for general speech
        let appleWords = apple.lowercased().split(separator: " ").map(String.init)
        let customWords = custom.lowercased().split(separator: " ").map(String.init)

        var merged: [String] = []
        let maxLen = max(appleWords.count, customWords.count)

        for i in 0..<maxLen {
            let appleWord = i < appleWords.count ? appleWords[i] : nil
            let customWord = i < customWords.count ? customWords[i] : nil

            if let custom = customWord, atcVocabulary?.isATCTerm(custom) == true {
                // Prefer custom model for ATC terms
                merged.append(custom)
            } else if let apple = appleWord {
                merged.append(apple)
            } else if let custom = customWord {
                merged.append(custom)
            }
        }

        return merged.joined(separator: " ")
    }

    // MARK: - ATC Normalization

    private func normalizeATCPhraseology(_ text: String) -> String {
        var normalized = text.uppercased()

        // Normalize numbers (spoken to digits)
        normalized = normalizeNumbers(normalized)

        // Normalize phonetic alphabet
        normalized = normalizePhonetics(normalized)

        // Normalize common ATC phrases
        normalized = normalizeATCPhrases(normalized)

        // Normalize callsigns
        normalized = normalizeCallsigns(normalized)

        return normalized
    }

    private func normalizeNumbers(_ text: String) -> String {
        var result = text

        // Number words to digits
        let numberMap: [String: String] = [
            "ZERO": "0", "ONE": "1", "TWO": "2", "THREE": "3",
            "FOUR": "4", "FIVE": "5", "SIX": "6", "SEVEN": "7",
            "EIGHT": "8", "NINER": "9", "NINE": "9",
            "HUNDRED": "00", "THOUSAND": "000"
        ]

        for (word, digit) in numberMap {
            result = result.replacingOccurrences(of: word, with: digit)
        }

        // Clean up multiple spaces
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return result
    }

    private func normalizePhonetics(_ text: String) -> String {
        var result = text

        // ICAO phonetic alphabet to letters
        let phoneticMap: [String: String] = [
            "ALFA": "A", "ALPHA": "A", "BRAVO": "B", "CHARLIE": "C",
            "DELTA": "D", "ECHO": "E", "FOXTROT": "F", "GOLF": "G",
            "HOTEL": "H", "INDIA": "I", "JULIET": "J", "JULIETT": "J",
            "KILO": "K", "LIMA": "L", "MIKE": "M", "NOVEMBER": "N",
            "OSCAR": "O", "PAPA": "P", "QUEBEC": "Q", "ROMEO": "R",
            "SIERRA": "S", "TANGO": "T", "UNIFORM": "U", "VICTOR": "V",
            "WHISKEY": "W", "XRAY": "X", "X-RAY": "X", "YANKEE": "Y",
            "ZULU": "Z"
        ]

        for (phonetic, letter) in phoneticMap {
            // Only replace when followed by another phonetic or number
            result = result.replacingOccurrences(of: phonetic + " ", with: letter)
        }

        return result
    }

    private func normalizeATCPhrases(_ text: String) -> String {
        var result = text

        // Common phrase normalizations
        let phraseMap: [String: String] = [
            "FLIGHT LEVEL": "FL",
            "SQUAWK IDENT": "SQUAWK IDENT",
            "READ BACK": "READBACK",
            "SAY AGAIN": "SAY AGAIN",
            "STAND BY": "STANDBY",
            "GO AHEAD": "GO AHEAD",
            "CLEARED FOR": "CLEARED",
            "CLEARED TO": "CLEARED",
            "CONTACT TOWER": "CONTACT TOWER",
            "CONTACT APPROACH": "CONTACT APPROACH",
            "CONTACT DEPARTURE": "CONTACT DEPARTURE",
            "CONTACT CENTER": "CONTACT CENTER",
            "RADAR CONTACT": "RADAR CONTACT",
            "RADAR SERVICE TERMINATED": "RADAR SERVICE TERMINATED"
        ]

        for (phrase, normalized) in phraseMap {
            result = result.replacingOccurrences(of: phrase, with: normalized)
        }

        return result
    }

    private func normalizeCallsigns(_ text: String) -> String {
        var result = text

        // Airline callsign patterns
        let airlines: [String: String] = [
            "AMERICAN": "AAL", "UNITED": "UAL", "DELTA": "DAL",
            "SOUTHWEST": "SWA", "JETBLUE": "JBU", "ALASKA": "ASA",
            "SPIRIT": "NKS", "FRONTIER": "FFT", "HAWAIIAN": "HAL",
            "LUFTHANSA": "DLH", "BRITISH": "BAW", "AIR FRANCE": "AFR",
            "SPEEDBIRD": "BAW", "CACTUS": "AWE"
        ]

        for (spoken, code) in airlines {
            result = result.replacingOccurrences(of: spoken, with: code)
        }

        return result
    }

    // MARK: - Element Extraction

    private struct ATCExtraction {
        var segments: [TranscriptionSegment]
        var confidence: Double
        var callsign: String?
        var instructions: [ATCInstruction]
        var frequencies: [Frequency]
        var altitudes: [Altitude]
        var headings: [Int]
        var speeds: [Int]
        var waypoints: [String]
    }

    private func extractATCElements(from text: String) -> ATCExtraction {
        var extraction = ATCExtraction(
            segments: [],
            confidence: 0.85,
            callsign: nil,
            instructions: [],
            frequencies: [],
            altitudes: [],
            headings: [],
            speeds: [],
            waypoints: []
        )

        // Extract callsign
        extraction.callsign = extractCallsign(from: text)

        // Extract frequencies
        extraction.frequencies = extractFrequencies(from: text)

        // Extract altitudes
        extraction.altitudes = extractAltitudes(from: text)

        // Extract headings
        extraction.headings = extractHeadings(from: text)

        // Extract speeds
        extraction.speeds = extractSpeeds(from: text)

        // Extract waypoints
        extraction.waypoints = extractWaypoints(from: text)

        // Parse instructions
        extraction.instructions = parseInstructions(from: text)

        // Create segments
        extraction.segments = [
            TranscriptionSegment(
                text: text,
                startTime: 0,
                endTime: 0,
                confidence: extraction.confidence
            )
        ]

        return extraction
    }

    private func extractCallsign(from text: String) -> String? {
        // Pattern: airline code + flight number or N-number
        let patterns = [
            // Airline callsign: DAL1234, UAL567
            "\\b([A-Z]{3})(\\d{1,4})\\b",
            // N-number: N12345
            "\\b(N\\d{1,5}[A-Z]*)\\b",
            // European: BAW123A
            "\\b([A-Z]{3})(\\d{1,4}[A-Z]?)\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) {
                    return String(text[range])
                }
            }
        }

        return nil
    }

    private func extractFrequencies(from text: String) -> [Frequency] {
        var frequencies: [Frequency] = []

        // Pattern: 118.0 to 136.975 MHz
        let pattern = "\\b(1[12][0-9]|13[0-6])\\.\\d{1,3}\\b"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if let range = Range(match.range, in: text),
                   let value = Double(text[range]) {
                    frequencies.append(Frequency(value: value, type: .vhf))
                }
            }
        }

        return frequencies
    }

    private func extractAltitudes(from text: String) -> [Altitude] {
        var altitudes: [Altitude] = []

        // Flight levels: FL350, FL 350
        let flPattern = "FL\\s?(\\d{2,3})"
        if let regex = try? NSRegularExpression(pattern: flPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text),
                   let value = Int(text[range]) {
                    altitudes.append(Altitude(value: value, type: .flightLevel))
                }
            }
        }

        // Feet: 5000 feet, 5000ft
        let feetPattern = "(\\d{3,5})\\s?(FEET|FT)"
        if let regex = try? NSRegularExpression(pattern: feetPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text),
                   let value = Int(text[range]) {
                    altitudes.append(Altitude(value: value, type: .feet))
                }
            }
        }

        return altitudes
    }

    private func extractHeadings(from text: String) -> [Int] {
        var headings: [Int] = []

        // Pattern: heading 270, turn heading 180
        let pattern = "HEADING\\s+(\\d{3})"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text),
                   let value = Int(text[range]),
                   value >= 0 && value <= 360 {
                    headings.append(value)
                }
            }
        }

        return headings
    }

    private func extractSpeeds(from text: String) -> [Int] {
        var speeds: [Int] = []

        // Pattern: 250 knots, speed 180
        let patterns = [
            "(\\d{2,3})\\s*KNOTS",
            "SPEED\\s+(\\d{2,3})",
            "MACH\\s+(\\.\\d{2})"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: text) {
                        if pattern.contains("MACH") {
                            if let mach = Double(text[range]) {
                                speeds.append(Int(mach * 1000))  // Store as Mach * 1000
                            }
                        } else if let value = Int(text[range]) {
                            speeds.append(value)
                        }
                    }
                }
            }
        }

        return speeds
    }

    private func extractWaypoints(from text: String) -> [String] {
        var waypoints: [String] = []

        // 5-letter fixes: BETTE, JEBBY, etc.
        let pattern = "\\b([A-Z]{5})\\b"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if let range = Range(match.range, in: text) {
                    let waypoint = String(text[range])
                    // Filter out common non-waypoint 5-letter words
                    let excluded = ["CLIMB", "CLEAR", "RADAR", "TOWER", "LEVEL", "SPEED", "HEAVY", "SUPER", "LIGHT"]
                    if !excluded.contains(waypoint) {
                        waypoints.append(waypoint)
                    }
                }
            }
        }

        return waypoints
    }

    private func parseInstructions(from text: String) -> [ATCInstruction] {
        var instructions: [ATCInstruction] = []

        let instructionPatterns: [(pattern: String, type: ATCInstructionType)] = [
            ("CLIMB AND MAINTAIN", .climb),
            ("CLIMB TO", .climb),
            ("DESCEND AND MAINTAIN", .descend),
            ("DESCEND TO", .descend),
            ("TURN LEFT", .turnLeft),
            ("TURN RIGHT", .turnRight),
            ("MAINTAIN", .maintain),
            ("CONTACT", .contact),
            ("SQUAWK", .squawk),
            ("CLEARED", .cleared),
            ("HOLD", .hold),
            ("PROCEED DIRECT", .directTo),
            ("DIRECT", .directTo),
            ("EXPECT", .expect),
            ("REPORT", .report),
            ("TAXI TO", .taxi),
            ("TAXI VIA", .taxi),
            ("CLEARED FOR TAKEOFF", .takeoff),
            ("CLEARED TO LAND", .land),
            ("GO AROUND", .goAround),
            ("EXPEDITE", .expedite),
            ("REDUCE SPEED", .reduce),
            ("INCREASE SPEED", .increase),
            ("INTERCEPT", .intercept)
        ]

        for (pattern, type) in instructionPatterns {
            if text.contains(pattern) {
                instructions.append(ATCInstruction(
                    type: type,
                    rawText: pattern,
                    parameters: [:],
                    isUrgent: pattern.contains("EXPEDITE") || pattern.contains("IMMEDIATELY")
                ))
            }
        }

        return instructions
    }

    // MARK: - Language Configuration

    func setLanguage(_ languageCode: String) {
        currentLanguage = languageCode
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
        speechRecognizer?.delegate = self
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension ATCSpeechRecognitionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available
        }
    }
}
