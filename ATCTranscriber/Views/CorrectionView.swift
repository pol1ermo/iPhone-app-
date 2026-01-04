//
//  CorrectionView.swift
//  ATCTranscriber
//
//  View for correcting transcriptions to improve model training
//

import SwiftUI

struct CorrectionView: View {
    let transcription: ATCTranscription
    let onSubmit: (TranscriptionCorrection) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var correctedText: String
    @State private var correctionType: TranscriptionCorrection.CorrectionType = .transcription
    @State private var showingConfirmation = false

    init(transcription: ATCTranscription, onSubmit: @escaping (TranscriptionCorrection) -> Void) {
        self.transcription = transcription
        self.onSubmit = onSubmit
        _correctedText = State(initialValue: transcription.normalizedText)
    }

    var body: some View {
        NavigationView {
            Form {
                // Original transcription
                Section(header: Text("Original Transcription")) {
                    Text(transcription.normalizedText)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Corrected transcription
                Section(header: Text("Corrected Transcription")) {
                    TextEditor(text: $correctedText)
                        .frame(minHeight: 100)
                        .font(.body)

                    // Quick correction buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickCorrectionButton(text: "FL", action: { insertText("FL") })
                            QuickCorrectionButton(text: "CLEARED", action: { insertText("CLEARED ") })
                            QuickCorrectionButton(text: "CONTACT", action: { insertText("CONTACT ") })
                            QuickCorrectionButton(text: "SQUAWK", action: { insertText("SQUAWK ") })
                            QuickCorrectionButton(text: "MAINTAIN", action: { insertText("MAINTAIN ") })
                        }
                    }
                }

                // Correction type
                Section(header: Text("Correction Type")) {
                    Picker("Type", selection: $correctionType) {
                        Text("Text Error").tag(TranscriptionCorrection.CorrectionType.transcription)
                        Text("Parsing Error").tag(TranscriptionCorrection.CorrectionType.parsing)
                        Text("Both").tag(TranscriptionCorrection.CorrectionType.both)
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text(correctionTypeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Extracted elements comparison
                if hasChanges {
                    Section(header: Text("Changes Preview")) {
                        VStack(alignment: .leading, spacing: 8) {
                            if transcription.normalizedText != correctedText {
                                ChangeRow(label: "Text", original: transcription.normalizedText, corrected: correctedText)
                            }
                        }
                    }
                }

                // Training info
                Section(footer: Text("Your corrections help improve the model's accuracy for future transcriptions.")) {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundColor(.blue)
                        Text("This correction will be used for training")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Correct Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        showingConfirmation = true
                    }
                    .disabled(!hasChanges)
                }
            }
            .alert("Submit Correction?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Submit") {
                    submitCorrection()
                }
            } message: {
                Text("This correction will be used to improve the model.")
            }
        }
    }

    private var hasChanges: Bool {
        correctedText != transcription.normalizedText
    }

    private var correctionTypeDescription: String {
        switch correctionType {
        case .transcription:
            return "The words were incorrectly recognized (e.g., 'flight level' heard as 'fly devil')"
        case .parsing:
            return "The words were correct but extracted data was wrong (e.g., altitude parsed incorrectly)"
        case .both:
            return "Both transcription and parsing had errors"
        }
    }

    private func insertText(_ text: String) {
        correctedText += text
    }

    private func submitCorrection() {
        let correction = TranscriptionCorrection(
            originalTranscription: transcription,
            correctedText: correctedText,
            correctionType: correctionType
        )

        onSubmit(correction)
        dismiss()
    }
}

// MARK: - Quick Correction Button

struct QuickCorrectionButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
    }
}

// MARK: - Change Row

struct ChangeRow: View {
    let label: String
    let original: String
    let corrected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(original)
                    .font(.caption)
                    .strikethrough()
                    .foregroundColor(.red)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(corrected)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Transcription Details View

struct TranscriptionDetailsView: View {
    let transcription: ATCTranscription
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Raw text
                    DetailSection(title: "Raw Transcription") {
                        Text(transcription.rawText)
                            .font(.body)
                    }

                    // Normalized text
                    DetailSection(title: "Normalized Text") {
                        Text(transcription.normalizedText)
                            .font(.body)
                    }

                    // Metadata
                    DetailSection(title: "Metadata") {
                        MetadataRow(label: "Timestamp", value: formattedDate)
                        MetadataRow(label: "Confidence", value: "\(Int(transcription.confidence * 100))%")
                        MetadataRow(label: "Processing Time", value: String(format: "%.3f s", transcription.processingTime))
                    }

                    // Extracted callsign
                    if let callsign = transcription.callsign {
                        DetailSection(title: "Callsign") {
                            Text(callsign)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }

                    // Instructions
                    if !transcription.instructions.isEmpty {
                        DetailSection(title: "Instructions") {
                            ForEach(transcription.instructions) { instruction in
                                InstructionRow(instruction: instruction)
                            }
                        }
                    }

                    // Frequencies
                    if !transcription.frequencies.isEmpty {
                        DetailSection(title: "Frequencies") {
                            ForEach(transcription.frequencies, id: \.self) { freq in
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(.purple)
                                    Text(freq.formatted + " MHz")
                                    Spacer()
                                    Text(freq.isValid ? "Valid" : "Invalid")
                                        .font(.caption)
                                        .foregroundColor(freq.isValid ? .green : .red)
                                }
                            }
                        }
                    }

                    // Altitudes
                    if !transcription.altitudes.isEmpty {
                        DetailSection(title: "Altitudes") {
                            ForEach(transcription.altitudes, id: \.self) { alt in
                                HStack {
                                    Image(systemName: "arrow.up.and.down")
                                        .foregroundColor(.orange)
                                    Text(alt.formatted)
                                    Spacer()
                                    Text("\(alt.inFeet) ft")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Headings
                    if !transcription.headings.isEmpty {
                        DetailSection(title: "Headings") {
                            ForEach(transcription.headings, id: \.self) { hdg in
                                HStack {
                                    Image(systemName: "safari")
                                        .foregroundColor(.green)
                                    Text("\(hdg)°")
                                }
                            }
                        }
                    }

                    // Speeds
                    if !transcription.speeds.isEmpty {
                        DetailSection(title: "Speeds") {
                            ForEach(transcription.speeds, id: \.self) { speed in
                                HStack {
                                    Image(systemName: "speedometer")
                                        .foregroundColor(.blue)
                                    Text("\(speed) knots")
                                }
                            }
                        }
                    }

                    // Waypoints
                    if !transcription.waypoints.isEmpty {
                        DetailSection(title: "Waypoints") {
                            ForEach(transcription.waypoints, id: \.self) { wpt in
                                HStack {
                                    Image(systemName: "mappin")
                                        .foregroundColor(.red)
                                    Text(wpt)
                                }
                            }
                        }
                    }

                    // Segments
                    if !transcription.segments.isEmpty {
                        DetailSection(title: "Segments") {
                            ForEach(transcription.segments) { segment in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(segment.text)
                                        .font(.body)

                                    HStack {
                                        Text("\(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
                                        Spacer()
                                        Text("\(Int(segment.confidence * 100))%")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
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
        return formatter.string(from: transcription.timestamp)
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
        }
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
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

// MARK: - Instruction Row

struct InstructionRow: View {
    let instruction: ATCInstruction

    var body: some View {
        HStack {
            Image(systemName: instructionIcon)
                .foregroundColor(instruction.isUrgent ? .red : .blue)
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(instruction.type.rawValue.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(instruction.rawText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if instruction.isUrgent {
                Text("URGENT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    private var instructionIcon: String {
        switch instruction.type {
        case .climb:
            return "arrow.up"
        case .descend:
            return "arrow.down"
        case .turnLeft:
            return "arrow.turn.up.left"
        case .turnRight:
            return "arrow.turn.up.right"
        case .maintain:
            return "equal"
        case .contact:
            return "antenna.radiowaves.left.and.right"
        case .squawk:
            return "wave.3.right"
        case .cleared:
            return "checkmark.circle"
        case .hold:
            return "pause.circle"
        case .proceed, .directTo:
            return "arrow.right"
        case .expect:
            return "clock"
        case .report:
            return "text.bubble"
        case .taxi:
            return "car"
        case .takeoff:
            return "airplane.departure"
        case .land:
            return "airplane.arrival"
        case .goAround:
            return "arrow.uturn.up"
        case .expedite:
            return "hare"
        case .reduce:
            return "minus.circle"
        case .increase:
            return "plus.circle"
        case .intercept:
            return "arrow.merge"
        case .unknown:
            return "questionmark.circle"
        }
    }
}
