# ATC Transcriber

An iOS application for real-time Air Traffic Control (ATC) audio transcription, validation, and analysis. Runs entirely on-device using CoreML for privacy and offline capability.

## Features

### 🎙️ Audio Capture & Processing
- Real-time audio capture with AVFoundation
- Voice Activity Detection (VAD) for automatic speech detection
- Noise reduction and audio preprocessing
- Band-pass filtering optimized for aviation radio frequencies (300-3400 Hz)

### 🗣️ Speech Recognition
- Hybrid recognition using Apple Speech + Custom CoreML model
- ATC-specific vocabulary and phraseology
- Automatic normalization of numbers, phonetic alphabet, and callsigns
- Support for multiple languages (EN-US, EN-GB, DE, FR, ES)

### ✈️ ATC Element Extraction
- Callsign detection (airline codes, N-numbers)
- Frequency parsing (VHF 118-136 MHz)
- Altitude extraction (feet, flight levels)
- Heading and speed recognition
- Waypoint/fix identification

### ✅ Validation Engine
- Common sense checks (altitude limits, speed ranges, heading validity)
- AIRAC compliance validation
- Phraseology correctness analysis
- Instruction sequence verification
- Conflicting instruction detection

### 📊 AIRAC Data Management
- Built-in navigation database
- Airport, waypoint, VOR, NDB data
- SID/STAR procedures
- Automatic cycle tracking (28-day updates)
- Data validation against current AIRAC

### 🧠 On-Device Training
- User correction collection
- Personalized model fine-tuning
- ATC-specific vocabulary learning
- Privacy-preserving local training

## Architecture

```
ATCTranscriber/
├── ATCTranscriberApp.swift      # App entry point & state management
├── Models/
│   ├── ATCModels.swift          # Core data models
│   └── AIRACModels.swift        # Navigation data structures
├── Services/
│   ├── AudioCaptureManager.swift        # Audio recording & preprocessing
│   ├── ATCSpeechRecognitionService.swift # Speech-to-text
│   ├── ATCValidationEngine.swift         # Validation rules
│   └── AIRACManager.swift               # Navigation data management
├── ML/
│   ├── ATCLanguageModel.swift           # CoreML model wrapper
│   └── OnDeviceTrainingManager.swift    # Training management
└── Views/
    ├── ContentView.swift         # Main transcription interface
    ├── HistoryView.swift         # Transcription history
    ├── SettingsView.swift        # App configuration
    └── CorrectionView.swift      # User corrections for training
```

## Requirements

- iOS 15.0+
- iPhone with A12 Bionic or later (for Neural Engine)
- Microphone access
- Speech recognition permission

## Installation

1. Clone the repository
2. Open `ATCTranscriber.xcodeproj` in Xcode
3. Select your development team for signing
4. Build and run on device or simulator

## Usage

### Recording ATC Communications

1. Tap the microphone button to start recording
2. The app will automatically detect speech and begin transcription
3. View real-time transcription and validation results
4. Tap again to stop recording

### Correcting Transcriptions

1. After transcription, tap "Correct" if errors are detected
2. Edit the transcription text
3. Select correction type (transcription error, parsing error, or both)
4. Submit to improve model accuracy

### Managing AIRAC Data

1. Go to Settings > AIRAC Data
2. View current cycle status and expiration
3. Check for and download updates
4. Data is validated against the current cycle

### Training the Model

1. Corrections are automatically collected for training
2. After 10+ corrections, training can be triggered
3. View training statistics in Settings
4. Model version increments after each training session

## Validation Rules

The validation engine checks for:

| Category | Checks |
|----------|--------|
| Altitude | Valid range (0-60,000 ft), flight level usage |
| Speed | Realistic values (60-600 kts), speed restrictions |
| Heading | Valid range (001-360°), proper 3-digit format |
| Frequency | VHF band (118-136 MHz), 25/8.33 kHz spacing |
| Phraseology | Standard terms, non-standard warnings |
| Common Sense | Conflicting instructions, missing elements |

## CoreML Model

The app uses a Whisper-style architecture optimized for ATC:

- **Encoder**: Audio to features (mel spectrogram → embeddings)
- **Decoder**: Autoregressive text generation with ATC vocabulary
- **Training**: On-device fine-tuning with user corrections

## Privacy

- All processing happens on-device
- No audio or transcriptions are sent to external servers
- Training data stays on your device
- AIRAC data is stored locally

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- ICAO for ATC phraseology standards
- OpenAI Whisper for model architecture inspiration
- Apple for CoreML and Speech frameworks
