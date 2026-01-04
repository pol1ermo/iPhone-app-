//
//  ATCModels.swift
//  ATCTranscriber
//
//  Core data models for ATC transcription
//

import Foundation

// MARK: - Audio Data

/// Raw audio data from capture
struct AudioData: Identifiable {
    let id = UUID()
    let samples: [Float]
    let sampleRate: Double
    let duration: TimeInterval
    let timestamp: Date

    var buffer: Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

// MARK: - Transcription

/// Transcribed ATC communication
struct ATCTranscription: Identifiable, Codable {
    let id: UUID
    let rawText: String
    let normalizedText: String
    let segments: [TranscriptionSegment]
    let confidence: Double
    let timestamp: Date
    let processingTime: TimeInterval

    /// Extracted ATC elements
    var callsign: String?
    var instructions: [ATCInstruction]
    var frequencies: [Frequency]
    var altitudes: [Altitude]
    var headings: [Int]
    var speeds: [Int]
    var waypoints: [String]

    init(
        id: UUID = UUID(),
        rawText: String,
        normalizedText: String,
        segments: [TranscriptionSegment] = [],
        confidence: Double,
        timestamp: Date = Date(),
        processingTime: TimeInterval = 0,
        callsign: String? = nil,
        instructions: [ATCInstruction] = [],
        frequencies: [Frequency] = [],
        altitudes: [Altitude] = [],
        headings: [Int] = [],
        speeds: [Int] = [],
        waypoints: [String] = []
    ) {
        self.id = id
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.segments = segments
        self.confidence = confidence
        self.timestamp = timestamp
        self.processingTime = processingTime
        self.callsign = callsign
        self.instructions = instructions
        self.frequencies = frequencies
        self.altitudes = altitudes
        self.headings = headings
        self.speeds = speeds
        self.waypoints = waypoints
    }
}

/// A segment of transcribed speech with timing
struct TranscriptionSegment: Identifiable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Double) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

// MARK: - ATC Instructions

/// Types of ATC instructions
enum ATCInstructionType: String, Codable, CaseIterable {
    case climb
    case descend
    case turnLeft
    case turnRight
    case maintain
    case contact
    case squawk
    case cleared
    case hold
    case proceed
    case expect
    case report
    case taxi
    case takeoff
    case land
    case goAround
    case expedite
    case reduce
    case increase
    case directTo
    case intercept
    case unknown
}

/// Parsed ATC instruction
struct ATCInstruction: Identifiable, Codable {
    let id: UUID
    let type: ATCInstructionType
    let rawText: String
    let parameters: [String: String]
    let isUrgent: Bool

    init(id: UUID = UUID(), type: ATCInstructionType, rawText: String, parameters: [String: String] = [:], isUrgent: Bool = false) {
        self.id = id
        self.type = type
        self.rawText = rawText
        self.parameters = parameters
        self.isUrgent = isUrgent
    }
}

// MARK: - Aviation Data Types

/// Radio frequency
struct Frequency: Codable, Hashable {
    let value: Double
    let type: FrequencyType

    enum FrequencyType: String, Codable {
        case vhf
        case uhf
        case hf
    }

    var formatted: String {
        String(format: "%.3f", value)
    }

    /// Validates frequency is within valid aviation bands
    var isValid: Bool {
        switch type {
        case .vhf:
            return value >= 118.0 && value <= 136.975
        case .uhf:
            return value >= 225.0 && value <= 399.9
        case .hf:
            return value >= 2.0 && value <= 30.0
        }
    }
}

/// Altitude representation
struct Altitude: Codable, Hashable {
    let value: Int
    let type: AltitudeType

    enum AltitudeType: String, Codable {
        case feet           // e.g., "5000 feet"
        case flightLevel    // e.g., "FL350"
        case metersQNH      // e.g., "3000 meters QNH"
    }

    var formatted: String {
        switch type {
        case .feet:
            return "\(value) feet"
        case .flightLevel:
            return "FL\(value)"
        case .metersQNH:
            return "\(value)m"
        }
    }

    /// Convert to feet for comparison
    var inFeet: Int {
        switch type {
        case .feet:
            return value
        case .flightLevel:
            return value * 100
        case .metersQNH:
            return Int(Double(value) * 3.28084)
        }
    }
}

// MARK: - Validation

/// Result of validation check
struct ValidationResult: Identifiable {
    let id = UUID()
    let type: ValidationType
    let severity: ValidationSeverity
    let message: String
    let suggestion: String?
    let relatedElement: String?

    enum ValidationType: String {
        case frequency
        case altitude
        case callsign
        case waypoint
        case procedure
        case phraseology
        case commonSense
        case airac
        case syntax
    }

    enum ValidationSeverity: String {
        case error      // Critical issue
        case warning    // Potential issue
        case info       // Informational
        case valid      // Passed validation
    }
}

// MARK: - Training

/// User correction for model training
struct TranscriptionCorrection: Identifiable, Codable {
    let id: UUID
    let originalTranscription: ATCTranscription
    let correctedText: String
    let correctionType: CorrectionType
    let timestamp: Date
    let audioReference: UUID?

    enum CorrectionType: String, Codable {
        case transcription  // Text was wrong
        case parsing        // Parsing was wrong
        case both           // Both were wrong
    }

    init(
        id: UUID = UUID(),
        originalTranscription: ATCTranscription,
        correctedText: String,
        correctionType: CorrectionType,
        timestamp: Date = Date(),
        audioReference: UUID? = nil
    ) {
        self.id = id
        self.originalTranscription = originalTranscription
        self.correctedText = correctedText
        self.correctionType = correctionType
        self.timestamp = timestamp
        self.audioReference = audioReference
    }
}

// MARK: - History

/// Historical transcription entry for review
struct TranscriptionHistoryEntry: Identifiable, Codable {
    let id: UUID
    let transcription: ATCTranscription
    let wasValidated: Bool
    let hadErrors: Bool
    let userCorrected: Bool
    let sessionId: UUID

    init(
        id: UUID = UUID(),
        transcription: ATCTranscription,
        wasValidated: Bool = false,
        hadErrors: Bool = false,
        userCorrected: Bool = false,
        sessionId: UUID
    ) {
        self.id = id
        self.transcription = transcription
        self.wasValidated = wasValidated
        self.hadErrors = hadErrors
        self.userCorrected = userCorrected
        self.sessionId = sessionId
    }
}
