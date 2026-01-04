//
//  AIRACManager.swift
//  ATCTranscriber
//
//  Manages AIRAC (Aeronautical Information Regulation And Control) data
//  Updates every 28 days per AIRAC cycle
//

import Foundation
import Combine

/// Manages AIRAC navigation data for validation
class AIRACManager: ObservableObject {

    // MARK: - Properties

    @Published var currentCycle: AIRACCycle?
    @Published var isDataLoaded = false
    @Published var lastUpdateDate: Date?
    @Published var updateProgress: Double = 0

    private var airacData: AIRACData?
    private var cancellables = Set<AnyCancellable>()

    // Storage
    private let fileManager = FileManager.default
    private var dataDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIRAC", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        createDataDirectory()
        loadStoredData()
        checkForUpdates()
    }

    private func createDataDirectory() {
        try? fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Data Loading

    private func loadStoredData() {
        let dataFile = dataDirectory.appendingPathComponent("airac_data.json")

        guard fileManager.fileExists(atPath: dataFile.path) else {
            loadBundledData()
            return
        }

        do {
            let data = try Data(contentsOf: dataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            airacData = try decoder.decode(AIRACData.self, from: data)
            currentCycle = airacData?.cycle
            isDataLoaded = true
            lastUpdateDate = try? fileManager.attributesOfItem(atPath: dataFile.path)[.modificationDate] as? Date
        } catch {
            print("Failed to load stored AIRAC data: \(error)")
            loadBundledData()
        }
    }

    private func loadBundledData() {
        // Load bundled AIRAC data from app bundle
        guard let bundleURL = Bundle.main.url(forResource: "airac_data", withExtension: "json") else {
            // Create default empty data
            let defaultCycle = createDefaultCycle()
            airacData = AIRACData(cycle: defaultCycle)
            populateDefaultData()
            currentCycle = defaultCycle
            isDataLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: bundleURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            airacData = try decoder.decode(AIRACData.self, from: data)
            currentCycle = airacData?.cycle
            isDataLoaded = true
        } catch {
            print("Failed to load bundled AIRAC data: \(error)")
        }
    }

    private func createDefaultCycle() -> AIRACCycle {
        // Calculate current AIRAC cycle
        // AIRAC cycles are 28 days, starting from a known reference
        // Reference: Cycle 2401 started January 25, 2024

        let calendar = Calendar.current
        let referenceDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 25))!
        let now = Date()

        let daysSinceReference = calendar.dateComponents([.day], from: referenceDate, to: now).day ?? 0
        let cyclesSinceReference = daysSinceReference / 28

        let currentCycleStart = calendar.date(byAdding: .day, value: cyclesSinceReference * 28, to: referenceDate)!
        let currentCycleEnd = calendar.date(byAdding: .day, value: 28, to: currentCycleStart)!

        // Calculate cycle number (YYMM format)
        let year = calendar.component(.year, from: currentCycleStart) % 100
        let cycleInYear = (cyclesSinceReference % 13) + 1
        let cycleNumber = String(format: "%02d%02d", year, cycleInYear)

        return AIRACCycle(
            cycleNumber: cycleNumber,
            effectiveDate: currentCycleStart,
            expirationDate: currentCycleEnd
        )
    }

    private func populateDefaultData() {
        guard var data = airacData else { return }

        // Add some example airports
        let sampleAirports: [Airport] = [
            Airport(icao: "KJFK", iata: "JFK", name: "John F Kennedy Intl", city: "New York", country: "USA",
                   latitude: 40.6398, longitude: -73.7789, elevation: 13, transitionAltitude: 18000,
                   frequencies: [
                       AirportFrequency(type: .tower, frequency: 119.1, name: "JFK Tower"),
                       AirportFrequency(type: .ground, frequency: 121.9, name: "JFK Ground"),
                       AirportFrequency(type: .approach, frequency: 123.9, name: "New York Approach"),
                       AirportFrequency(type: .atis, frequency: 128.725, name: "JFK ATIS")
                   ],
                   runways: [
                       Runway(identifier: "04L", heading: 44, length: 11351, width: 150, surface: "Asphalt"),
                       Runway(identifier: "22R", heading: 224, length: 11351, width: 150, surface: "Asphalt"),
                       Runway(identifier: "13L", heading: 134, length: 10000, width: 150, surface: "Asphalt"),
                       Runway(identifier: "31R", heading: 314, length: 10000, width: 150, surface: "Asphalt")
                   ]),
            Airport(icao: "KLAX", iata: "LAX", name: "Los Angeles Intl", city: "Los Angeles", country: "USA",
                   latitude: 33.9425, longitude: -118.4081, elevation: 128, transitionAltitude: 18000),
            Airport(icao: "EGLL", iata: "LHR", name: "Heathrow", city: "London", country: "UK",
                   latitude: 51.4706, longitude: -0.4619, elevation: 83, transitionAltitude: 6000),
            Airport(icao: "LFPG", iata: "CDG", name: "Charles de Gaulle", city: "Paris", country: "France",
                   latitude: 49.0097, longitude: 2.5478, elevation: 392, transitionAltitude: 5000)
        ]

        for airport in sampleAirports {
            data.airports[airport.icao] = airport
        }

        // Add some sample waypoints
        let sampleWaypoints: [Waypoint] = [
            Waypoint(identifier: "BETTE", type: .fix, latitude: 40.5, longitude: -73.8),
            Waypoint(identifier: "JEBBY", type: .fix, latitude: 40.6, longitude: -73.7),
            Waypoint(identifier: "MERIT", type: .fix, latitude: 40.7, longitude: -73.6),
            Waypoint(identifier: "WAVEY", type: .fix, latitude: 40.3, longitude: -73.9),
            Waypoint(identifier: "SHIPP", type: .fix, latitude: 40.4, longitude: -74.0)
        ]

        for waypoint in sampleWaypoints {
            data.waypoints[waypoint.identifier] = waypoint
        }

        // Add sample VORs
        let sampleVORs: [VOR] = [
            VOR(identifier: "JFK", name: "Kennedy", frequency: 115.9, latitude: 40.6398, longitude: -73.7789, hasDME: true),
            VOR(identifier: "LGA", name: "La Guardia", frequency: 113.1, latitude: 40.7772, longitude: -73.8726, hasDME: true),
            VOR(identifier: "EWR", name: "Newark", frequency: 108.95, latitude: 40.6925, longitude: -74.1687, hasDME: true)
        ]

        for vor in sampleVORs {
            data.vors[vor.identifier] = vor
        }

        airacData = data
    }

    // MARK: - Update Check

    private func checkForUpdates() {
        guard let cycle = currentCycle else { return }

        // Check if current cycle is expired
        if !cycle.isActive {
            // Would trigger update download in production
            print("AIRAC cycle \(cycle.cycleNumber) is expired. Update needed.")
        }

        // Check days until expiration
        if cycle.daysUntilExpiration < 7 {
            print("AIRAC cycle expires in \(cycle.daysUntilExpiration) days")
        }
    }

    // MARK: - Data Access

    /// Validate a waypoint exists in current AIRAC
    func isValidWaypoint(_ identifier: String) -> Bool {
        return airacData?.isValidWaypoint(identifier) ?? false
    }

    /// Get airport by ICAO code
    func getAirport(_ icao: String) -> Airport? {
        return airacData?.airports[icao.uppercased()]
    }

    /// Get waypoint by identifier
    func getWaypoint(_ identifier: String) -> Waypoint? {
        return airacData?.waypoints[identifier.uppercased()]
    }

    /// Get VOR by identifier
    func getVOR(_ identifier: String) -> VOR? {
        return airacData?.vors[identifier.uppercased()]
    }

    /// Validate a frequency for a given airport
    func isValidFrequency(_ frequency: Double, forAirport icao: String) -> Bool {
        guard let airport = getAirport(icao) else { return false }

        // Check if frequency matches any airport frequency
        for freq in airport.frequencies {
            if abs(freq.frequency - frequency) < 0.005 {  // Within 5kHz
                return true
            }
        }

        return false
    }

    /// Get SIDs for an airport
    func getSIDs(forAirport icao: String) -> [SID] {
        return airacData?.sids[icao.uppercased()] ?? []
    }

    /// Get STARs for an airport
    func getSTARs(forAirport icao: String) -> [STAR] {
        return airacData?.stars[icao.uppercased()] ?? []
    }

    /// Get approaches for an airport
    func getApproaches(forAirport icao: String) -> [ApproachProcedure] {
        return airacData?.approaches[icao.uppercased()] ?? []
    }

    /// Search for navaids by partial identifier
    func searchNavaids(_ query: String, limit: Int = 10) -> [(type: String, identifier: String)] {
        var results: [(String, String)] = []
        let upperQuery = query.uppercased()

        if let data = airacData {
            // Search waypoints
            for (id, _) in data.waypoints where id.hasPrefix(upperQuery) {
                results.append(("FIX", id))
            }

            // Search VORs
            for (id, _) in data.vors where id.hasPrefix(upperQuery) {
                results.append(("VOR", id))
            }

            // Search NDBs
            for (id, _) in data.ndbs where id.hasPrefix(upperQuery) {
                results.append(("NDB", id))
            }

            // Search airports
            for (id, _) in data.airports where id.hasPrefix(upperQuery) {
                results.append(("APT", id))
            }
        }

        return Array(results.prefix(limit))
    }

    // MARK: - Data Update

    /// Update AIRAC data from downloaded file
    func updateData(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let newData = try decoder.decode(AIRACData.self, from: data)

        // Validate new data
        guard newData.cycle.effectiveDate > (currentCycle?.effectiveDate ?? .distantPast) else {
            throw AIRACError.outdatedData
        }

        // Save to storage
        let storageURL = dataDirectory.appendingPathComponent("airac_data.json")
        try data.write(to: storageURL)

        await MainActor.run {
            self.airacData = newData
            self.currentCycle = newData.cycle
            self.lastUpdateDate = Date()
        }
    }

    /// Export current AIRAC data
    func exportData() throws -> Data {
        guard let data = airacData else {
            throw AIRACError.noData
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        return try encoder.encode(data)
    }
}

// MARK: - Errors

enum AIRACError: LocalizedError {
    case noData
    case outdatedData
    case invalidFormat
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .noData:
            return "No AIRAC data available"
        case .outdatedData:
            return "AIRAC data is outdated"
        case .invalidFormat:
            return "Invalid AIRAC data format"
        case .downloadFailed:
            return "Failed to download AIRAC update"
        }
    }
}

// MARK: - AIRAC Validation Protocol

protocol AIRACValidatable {
    func validate(against airacData: AIRACData?) -> [ValidationResult]
}

extension Frequency: AIRACValidatable {
    func validate(against airacData: AIRACData?) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Check frequency is in valid range
        if !isValid {
            results.append(ValidationResult(
                type: .frequency,
                severity: .error,
                message: "Frequency \(formatted) is outside valid aviation band",
                suggestion: "VHF frequencies should be 118.000-136.975 MHz",
                relatedElement: formatted
            ))
        }

        return results
    }
}

extension Waypoint: AIRACValidatable {
    func validate(against airacData: AIRACData?) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Check waypoint exists in AIRAC
        if let data = airacData, !data.isValidWaypoint(identifier) {
            results.append(ValidationResult(
                type: .waypoint,
                severity: .warning,
                message: "Waypoint \(identifier) not found in current AIRAC",
                suggestion: "Verify waypoint identifier",
                relatedElement: identifier
            ))
        }

        return results
    }
}
