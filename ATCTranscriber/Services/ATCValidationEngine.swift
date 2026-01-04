//
//  ATCValidationEngine.swift
//  ATCTranscriber
//
//  Validates ATC transcriptions for correctness, common sense, and AIRAC compliance
//

import Foundation

/// Engine for validating ATC transcriptions
class ATCValidationEngine: ObservableObject {

    // MARK: - Properties

    @Published var lastValidationTime: TimeInterval = 0

    // Validation rules
    private var rules: [ValidationRule] = []

    // Common sense limits
    private let maxAltitudeFeet = 60000
    private let minAltitudeFeet = 0
    private let maxSpeedKnots = 600
    private let minSpeedKnots = 60
    private let maxHeading = 360
    private let minHeading = 1

    // MARK: - Initialization

    init() {
        loadDefaultRules()
    }

    private func loadDefaultRules() {
        rules = [
            // Altitude rules
            AltitudeRule(),
            FlightLevelRule(),

            // Speed rules
            SpeedRule(),

            // Heading rules
            HeadingRule(),

            // Frequency rules
            FrequencyRule(),

            // Phraseology rules
            PhraseologyRule(),

            // Callsign rules
            CallsignRule(),

            // Instruction sequence rules
            InstructionSequenceRule()
        ]
    }

    // MARK: - Validation

    /// Validate a transcription against all rules
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        let startTime = Date()

        var results: [ValidationResult] = []

        // Run all validation rules
        for rule in rules {
            let ruleResults = await rule.validate(transcription: transcription, airacCycle: airacCycle)
            results.append(contentsOf: ruleResults)
        }

        // Add common sense checks
        results.append(contentsOf: performCommonSenseChecks(transcription))

        // Sort by severity
        results.sort { $0.severity.rawValue < $1.severity.rawValue }

        lastValidationTime = Date().timeIntervalSince(startTime)

        return results
    }

    // MARK: - Common Sense Checks

    private func performCommonSenseChecks(_ transcription: ATCTranscription) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Check altitude values
        for altitude in transcription.altitudes {
            let feet = altitude.inFeet

            if feet > maxAltitudeFeet {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .error,
                    message: "Altitude \(altitude.formatted) exceeds maximum (\(maxAltitudeFeet) ft)",
                    suggestion: "Check altitude value - did you mean FL\(feet/1000)?",
                    relatedElement: altitude.formatted
                ))
            }

            if feet < minAltitudeFeet {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .error,
                    message: "Altitude \(altitude.formatted) is below ground level",
                    suggestion: "Check altitude value",
                    relatedElement: altitude.formatted
                ))
            }

            // Check for unrealistic values
            if altitude.type == .flightLevel && altitude.value < 18 {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .warning,
                    message: "Flight level \(altitude.value) is unusually low",
                    suggestion: "Flight levels typically start at FL180 (18,000ft) in the US",
                    relatedElement: altitude.formatted
                ))
            }
        }

        // Check speed values
        for speed in transcription.speeds {
            if speed > maxSpeedKnots {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .warning,
                    message: "Speed \(speed) knots exceeds typical maximum",
                    suggestion: "Check speed value - is this Mach number?",
                    relatedElement: "\(speed) knots"
                ))
            }

            if speed < minSpeedKnots && speed > 0 {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .warning,
                    message: "Speed \(speed) knots is below minimum safe airspeed",
                    suggestion: "Check speed value",
                    relatedElement: "\(speed) knots"
                ))
            }
        }

        // Check heading values
        for heading in transcription.headings {
            if heading > maxHeading || heading < minHeading {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .error,
                    message: "Heading \(heading) is invalid (must be 001-360)",
                    suggestion: "Check heading value",
                    relatedElement: "heading \(heading)"
                ))
            }
        }

        // Check frequency values
        for frequency in transcription.frequencies {
            if !frequency.isValid {
                results.append(ValidationResult(
                    type: .frequency,
                    severity: .error,
                    message: "Frequency \(frequency.formatted) is outside valid aviation band",
                    suggestion: "VHF: 118.000-136.975 MHz",
                    relatedElement: frequency.formatted
                ))
            }

            // Check for common frequency mistakes
            if frequency.value >= 100 && frequency.value < 118 {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .warning,
                    message: "Frequency \(frequency.formatted) is below aviation band",
                    suggestion: "Did you mean 1\(frequency.formatted)?",
                    relatedElement: frequency.formatted
                ))
            }
        }

        // Check instruction consistency
        results.append(contentsOf: checkInstructionConsistency(transcription.instructions))

        // Check for conflicting instructions
        results.append(contentsOf: checkConflictingInstructions(transcription.instructions))

        return results
    }

    private func checkInstructionConsistency(_ instructions: [ATCInstruction]) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Check for climb followed by descend without maintain
        var hasClimb = false
        var hasDescend = false

        for instruction in instructions {
            if instruction.type == .climb {
                hasClimb = true
            }
            if instruction.type == .descend {
                hasDescend = true
            }
        }

        if hasClimb && hasDescend {
            results.append(ValidationResult(
                type: .commonSense,
                severity: .warning,
                message: "Both climb and descend instructions detected",
                suggestion: "Verify instruction sequence is correct",
                relatedElement: nil
            ))
        }

        return results
    }

    private func checkConflictingInstructions(_ instructions: [ATCInstruction]) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Check for conflicting turn instructions
        var hasLeftTurn = false
        var hasRightTurn = false

        for instruction in instructions {
            if instruction.type == .turnLeft {
                hasLeftTurn = true
            }
            if instruction.type == .turnRight {
                hasRightTurn = true
            }
        }

        if hasLeftTurn && hasRightTurn {
            results.append(ValidationResult(
                type: .commonSense,
                severity: .error,
                message: "Conflicting turn instructions (left and right)",
                suggestion: "Review transcription for accuracy",
                relatedElement: nil
            ))
        }

        return results
    }
}

// MARK: - Validation Rule Protocol

protocol ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult]
}

// MARK: - Altitude Rules

class AltitudeRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        for altitude in transcription.altitudes {
            // Check for proper altitude format
            if altitude.type == .feet {
                // Below transition altitude, should use feet
                if altitude.value >= 18000 {
                    results.append(ValidationResult(
                        type: .altitude,
                        severity: .info,
                        message: "Altitude \(altitude.value) ft - consider using flight level",
                        suggestion: "Above 18,000 ft typically expressed as FL\(altitude.value / 100)",
                        relatedElement: altitude.formatted
                    ))
                }
            }
        }

        return results
    }
}

class FlightLevelRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        for altitude in transcription.altitudes where altitude.type == .flightLevel {
            // Check for valid IFR cruising altitudes (NEODD/SWEVEN)
            let isOdd = (altitude.value / 10) % 2 == 1
            let isEven = !isOdd

            // This is informational - direction-based altitude selection
            results.append(ValidationResult(
                type: .altitude,
                severity: .info,
                message: "FL\(altitude.value) - \(isOdd ? "odd" : "even") flight level",
                suggestion: isOdd ? "Eastbound (000-179°)" : "Westbound (180-359°)",
                relatedElement: altitude.formatted
            ))
        }

        return results
    }
}

// MARK: - Speed Rules

class SpeedRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        for speed in transcription.speeds {
            // Check for 250 knot speed restriction below 10,000 ft
            // This would need context of current altitude to fully validate

            // Check for unrealistic speeds
            if speed > 250 && speed < 300 {
                results.append(ValidationResult(
                    type: .commonSense,
                    severity: .info,
                    message: "Speed \(speed) knots",
                    suggestion: "Remember 250 knot limit below 10,000 ft in Class B/C",
                    relatedElement: "\(speed) kts"
                ))
            }
        }

        return results
    }
}

// MARK: - Heading Rules

class HeadingRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        for heading in transcription.headings {
            // Check for valid heading format (should be 3 digits)
            if heading < 10 {
                results.append(ValidationResult(
                    type: .syntax,
                    severity: .info,
                    message: "Heading should be spoken as three digits",
                    suggestion: "Heading \(heading) should be 'zero zero \(heading)'",
                    relatedElement: "heading \(heading)"
                ))
            }
        }

        return results
    }
}

// MARK: - Frequency Rules

class FrequencyRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        for frequency in transcription.frequencies {
            // Check for valid VHF range
            if frequency.type == .vhf && !frequency.isValid {
                results.append(ValidationResult(
                    type: .frequency,
                    severity: .error,
                    message: "Frequency \(frequency.formatted) outside VHF band",
                    suggestion: "VHF frequencies: 118.000 - 136.975 MHz",
                    relatedElement: frequency.formatted
                ))
            }

            // Check for 8.33 kHz spacing (European requirement)
            let decimal = frequency.value.truncatingRemainder(dividingBy: 1)
            let kHz = Int(decimal * 1000)
            let isValid833Spacing = kHz % 5 == 0 || kHz % 25 == 0

            if !isValid833Spacing {
                results.append(ValidationResult(
                    type: .frequency,
                    severity: .warning,
                    message: "Frequency \(frequency.formatted) may have incorrect spacing",
                    suggestion: "Standard spacing is 25 kHz or 8.33 kHz",
                    relatedElement: frequency.formatted
                ))
            }
        }

        return results
    }
}

// MARK: - Phraseology Rules

class PhraseologyRule: ValidationRule {

    private let requiredReadbacks = [
        "runway", "altitude", "heading", "speed", "squawk", "frequency"
    ]

    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        let text = transcription.normalizedText.uppercased()

        // Check for proper acknowledgment
        if text.contains("CLEARED") && !text.contains("ROGER") && !text.contains("WILCO") {
            results.append(ValidationResult(
                type: .phraseology,
                severity: .info,
                message: "Clearance detected without readback confirmation",
                suggestion: "Readback is required for clearances",
                relatedElement: nil
            ))
        }

        // Check for "WITH YOU" (non-standard phraseology)
        if text.contains("WITH YOU") {
            results.append(ValidationResult(
                type: .phraseology,
                severity: .info,
                message: "'With you' is non-standard phraseology",
                suggestion: "Use: '[Callsign], [altitude]' on initial contact",
                relatedElement: "with you"
            ))
        }

        // Check for "PLEASE" (non-standard)
        if text.contains("PLEASE") {
            results.append(ValidationResult(
                type: .phraseology,
                severity: .info,
                message: "'Please' is non-standard phraseology",
                suggestion: "Use 'REQUEST' for requests",
                relatedElement: "please"
            ))
        }

        return results
    }
}

// MARK: - Callsign Rules

class CallsignRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        if let callsign = transcription.callsign {
            // Check callsign format
            let pattern = "^[A-Z]{3}\\d{1,4}[A-Z]?$|^N\\d{1,5}[A-Z]*$"
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(callsign.startIndex..., in: callsign)

            if regex?.firstMatch(in: callsign, range: range) == nil {
                results.append(ValidationResult(
                    type: .callsign,
                    severity: .warning,
                    message: "Callsign '\(callsign)' format may be incorrect",
                    suggestion: "Expected format: AAL123 or N12345",
                    relatedElement: callsign
                ))
            }
        } else {
            // No callsign detected
            results.append(ValidationResult(
                type: .callsign,
                severity: .info,
                message: "No callsign detected in transcription",
                suggestion: "Verify callsign was spoken",
                relatedElement: nil
            ))
        }

        return results
    }
}

// MARK: - Instruction Sequence Rules

class InstructionSequenceRule: ValidationRule {
    func validate(transcription: ATCTranscription, airacCycle: AIRACCycle?) async -> [ValidationResult] {
        var results: [ValidationResult] = []

        let instructions = transcription.instructions

        // Check for proper instruction ordering
        // Typically: altitude, heading, speed

        var hasAltitudeInstruction = false
        var hasHeadingAfterAltitude = false

        for instruction in instructions {
            if instruction.type == .climb || instruction.type == .descend || instruction.type == .maintain {
                hasAltitudeInstruction = true
            }

            if (instruction.type == .turnLeft || instruction.type == .turnRight) && hasAltitudeInstruction {
                hasHeadingAfterAltitude = true
            }
        }

        // Check for contact instruction with frequency
        let hasContact = instructions.contains { $0.type == .contact }
        let hasFrequency = !transcription.frequencies.isEmpty

        if hasContact && !hasFrequency {
            results.append(ValidationResult(
                type: .commonSense,
                severity: .warning,
                message: "Contact instruction without frequency",
                suggestion: "Expected frequency with contact instruction",
                relatedElement: nil
            ))
        }

        return results
    }
}
