//
//  AIRACModels.swift
//  ATCTranscriber
//
//  AIRAC (Aeronautical Information Regulation And Control) data models
//

import Foundation

// MARK: - AIRAC Cycle

/// AIRAC cycle information
struct AIRACCycle: Identifiable, Codable {
    let id: UUID
    let cycleNumber: String      // e.g., "2401" for first cycle of 2024
    let effectiveDate: Date
    let expirationDate: Date
    let version: String

    /// Check if cycle is currently active
    var isActive: Bool {
        let now = Date()
        return now >= effectiveDate && now < expirationDate
    }

    /// Days until expiration
    var daysUntilExpiration: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
    }

    init(
        id: UUID = UUID(),
        cycleNumber: String,
        effectiveDate: Date,
        expirationDate: Date,
        version: String = "1.0"
    ) {
        self.id = id
        self.cycleNumber = cycleNumber
        self.effectiveDate = effectiveDate
        self.expirationDate = expirationDate
        self.version = version
    }
}

// MARK: - Navigation Data

/// Airport data
struct Airport: Identifiable, Codable, Hashable {
    let id: UUID
    let icao: String            // e.g., "KJFK"
    let iata: String?           // e.g., "JFK"
    let name: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let elevation: Int          // feet
    let transitionAltitude: Int // feet
    let frequencies: [AirportFrequency]
    let runways: [Runway]

    init(
        id: UUID = UUID(),
        icao: String,
        iata: String? = nil,
        name: String,
        city: String,
        country: String,
        latitude: Double,
        longitude: Double,
        elevation: Int,
        transitionAltitude: Int = 18000,
        frequencies: [AirportFrequency] = [],
        runways: [Runway] = []
    ) {
        self.id = id
        self.icao = icao
        self.iata = iata
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.transitionAltitude = transitionAltitude
        self.frequencies = frequencies
        self.runways = runways
    }
}

/// Airport frequency
struct AirportFrequency: Codable, Hashable {
    let type: FrequencyPurpose
    let frequency: Double
    let name: String?

    enum FrequencyPurpose: String, Codable {
        case ground
        case tower
        case approach
        case departure
        case center
        case atis
        case clearance
        case unicom
        case emergency
    }
}

/// Runway data
struct Runway: Identifiable, Codable, Hashable {
    let id: UUID
    let identifier: String      // e.g., "09L"
    let heading: Int
    let length: Int             // feet
    let width: Int              // feet
    let surface: String
    let ilsFrequency: Double?
    let ilsCategory: String?

    init(
        id: UUID = UUID(),
        identifier: String,
        heading: Int,
        length: Int,
        width: Int,
        surface: String,
        ilsFrequency: Double? = nil,
        ilsCategory: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.heading = heading
        self.length = length
        self.width = width
        self.surface = surface
        self.ilsFrequency = ilsFrequency
        self.ilsCategory = ilsCategory
    }
}

/// Navigation waypoint/fix
struct Waypoint: Identifiable, Codable, Hashable {
    let id: UUID
    let identifier: String      // e.g., "BETTE"
    let type: WaypointType
    let latitude: Double
    let longitude: Double
    let region: String
    let country: String

    enum WaypointType: String, Codable {
        case fix            // Named fix
        case vor            // VOR station
        case vorDme         // VOR/DME
        case ndb            // Non-directional beacon
        case dme            // DME only
        case tacan          // TACAN
        case waypoint       // RNAV waypoint
    }

    init(
        id: UUID = UUID(),
        identifier: String,
        type: WaypointType,
        latitude: Double,
        longitude: Double,
        region: String = "",
        country: String = ""
    ) {
        self.id = id
        self.identifier = identifier
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.region = region
        self.country = country
    }
}

/// VOR navigation aid
struct VOR: Identifiable, Codable, Hashable {
    let id: UUID
    let identifier: String
    let name: String
    let frequency: Double
    let latitude: Double
    let longitude: Double
    let hasDME: Bool
    let magneticVariation: Double

    init(
        id: UUID = UUID(),
        identifier: String,
        name: String,
        frequency: Double,
        latitude: Double,
        longitude: Double,
        hasDME: Bool = false,
        magneticVariation: Double = 0
    ) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.frequency = frequency
        self.latitude = latitude
        self.longitude = longitude
        self.hasDME = hasDME
        self.magneticVariation = magneticVariation
    }
}

/// NDB navigation aid
struct NDB: Identifiable, Codable, Hashable {
    let id: UUID
    let identifier: String
    let name: String
    let frequency: Double
    let latitude: Double
    let longitude: Double

    init(
        id: UUID = UUID(),
        identifier: String,
        name: String,
        frequency: Double,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.frequency = frequency
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Procedures

/// Standard Instrument Departure (SID)
struct SID: Identifiable, Codable {
    let id: UUID
    let identifier: String      // e.g., "RNAV1"
    let airport: String         // ICAO
    let runway: String?
    let waypoints: [String]     // Ordered list of waypoint identifiers
    let transitions: [String]
    let remarks: String?

    init(
        id: UUID = UUID(),
        identifier: String,
        airport: String,
        runway: String? = nil,
        waypoints: [String] = [],
        transitions: [String] = [],
        remarks: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.airport = airport
        self.runway = runway
        self.waypoints = waypoints
        self.transitions = transitions
        self.remarks = remarks
    }
}

/// Standard Terminal Arrival Route (STAR)
struct STAR: Identifiable, Codable {
    let id: UUID
    let identifier: String
    let airport: String
    let runway: String?
    let waypoints: [String]
    let transitions: [String]
    let remarks: String?

    init(
        id: UUID = UUID(),
        identifier: String,
        airport: String,
        runway: String? = nil,
        waypoints: [String] = [],
        transitions: [String] = [],
        remarks: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.airport = airport
        self.runway = runway
        self.waypoints = waypoints
        self.transitions = transitions
        self.remarks = remarks
    }
}

/// Instrument Approach Procedure
struct ApproachProcedure: Identifiable, Codable {
    let id: UUID
    let identifier: String      // e.g., "ILS09L"
    let type: ApproachType
    let airport: String
    let runway: String
    let frequency: Double?
    let minimumAltitude: Int
    let decisionHeight: Int?
    let remarks: String?

    enum ApproachType: String, Codable {
        case ils
        case ilsCat2
        case ilsCat3
        case vor
        case vorDme
        case ndb
        case rnav
        case rnavLpv
        case gls
        case visual
        case circling
    }

    init(
        id: UUID = UUID(),
        identifier: String,
        type: ApproachType,
        airport: String,
        runway: String,
        frequency: Double? = nil,
        minimumAltitude: Int = 0,
        decisionHeight: Int? = nil,
        remarks: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.type = type
        self.airport = airport
        self.runway = runway
        self.frequency = frequency
        self.minimumAltitude = minimumAltitude
        self.decisionHeight = decisionHeight
        self.remarks = remarks
    }
}

// MARK: - Airspace

/// Airspace definition
struct Airspace: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: AirspaceType
    let classType: AirspaceClass
    let lowerLimit: Int         // feet AGL or MSL
    let upperLimit: Int
    let frequency: Double?
    let boundary: [Coordinate]

    enum AirspaceType: String, Codable {
        case controlZone
        case terminalArea
        case controlArea
        case restrictedArea
        case dangerArea
        case prohibitedArea
        case militaryArea
        case alertArea
        case fir             // Flight Information Region
    }

    enum AirspaceClass: String, Codable {
        case a, b, c, d, e, f, g
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: AirspaceType,
        classType: AirspaceClass,
        lowerLimit: Int,
        upperLimit: Int,
        frequency: Double? = nil,
        boundary: [Coordinate] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.classType = classType
        self.lowerLimit = lowerLimit
        self.upperLimit = upperLimit
        self.frequency = frequency
        self.boundary = boundary
    }
}

/// Geographic coordinate
struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Airways

/// Airway segment
struct Airway: Identifiable, Codable {
    let id: UUID
    let identifier: String      // e.g., "V23", "J60", "T200"
    let type: AirwayType
    let fromWaypoint: String
    let toWaypoint: String
    let minimumAltitude: Int
    let maximumAltitude: Int?
    let direction: AirwayDirection

    enum AirwayType: String, Codable {
        case victor         // Low altitude
        case jet            // High altitude
        case rnav           // RNAV routes
        case tango          // T-routes
        case qRoute         // Q-routes (RNAV high)
    }

    enum AirwayDirection: String, Codable {
        case both
        case forward
        case reverse
    }

    init(
        id: UUID = UUID(),
        identifier: String,
        type: AirwayType,
        fromWaypoint: String,
        toWaypoint: String,
        minimumAltitude: Int,
        maximumAltitude: Int? = nil,
        direction: AirwayDirection = .both
    ) {
        self.id = id
        self.identifier = identifier
        self.type = type
        self.fromWaypoint = fromWaypoint
        self.toWaypoint = toWaypoint
        self.minimumAltitude = minimumAltitude
        self.maximumAltitude = maximumAltitude
        self.direction = direction
    }
}

// MARK: - AIRAC Data Container

/// Complete AIRAC data for a cycle
struct AIRACData: Codable {
    let cycle: AIRACCycle
    var airports: [String: Airport]         // Keyed by ICAO
    var waypoints: [String: Waypoint]       // Keyed by identifier
    var vors: [String: VOR]
    var ndbs: [String: NDB]
    var sids: [String: [SID]]               // Keyed by airport ICAO
    var stars: [String: [STAR]]
    var approaches: [String: [ApproachProcedure]]
    var airways: [String: [Airway]]         // Keyed by identifier
    var airspaces: [Airspace]

    init(cycle: AIRACCycle) {
        self.cycle = cycle
        self.airports = [:]
        self.waypoints = [:]
        self.vors = [:]
        self.ndbs = [:]
        self.sids = [:]
        self.stars = [:]
        self.approaches = [:]
        self.airways = [:]
        self.airspaces = []
    }

    /// Find a waypoint, VOR, or NDB by identifier
    func findNavaid(_ identifier: String) -> (type: String, found: Bool) {
        if waypoints[identifier] != nil {
            return ("waypoint", true)
        }
        if vors[identifier] != nil {
            return ("VOR", true)
        }
        if ndbs[identifier] != nil {
            return ("NDB", true)
        }
        return ("unknown", false)
    }

    /// Validate that a waypoint exists
    func isValidWaypoint(_ identifier: String) -> Bool {
        return waypoints[identifier] != nil ||
               vors[identifier] != nil ||
               ndbs[identifier] != nil
    }

    /// Get airport by ICAO or IATA code
    func findAirport(_ code: String) -> Airport? {
        if let airport = airports[code.uppercased()] {
            return airport
        }
        return airports.values.first { $0.iata?.uppercased() == code.uppercased() }
    }
}
