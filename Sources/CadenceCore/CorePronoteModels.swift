import Foundation

public struct PronoteSchool: Codable, Equatable, Identifiable, Sendable {
    public var url: String
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var postalCode: String?
    public var distance: Double?
    public var id: String { url }

    public init(url: String, name: String, latitude: Double? = nil, longitude: Double? = nil,
                postalCode: String? = nil, distance: Double? = nil) {
        self.url = url; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.postalCode = postalCode; self.distance = distance
    }
}

public struct PronotePeriod: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: Int
    public var startDate: Date
    public var endDate: Date

    public init(id: String, name: String, kind: Int, startDate: Date, endDate: Date) {
        self.id = id; self.name = name; self.kind = kind; self.startDate = startDate; self.endDate = endDate
    }
}

public struct PronoteStudentResource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var className: String?

    public init(id: String, name: String, className: String? = nil) {
        self.id = id; self.name = name; self.className = className
    }
}

public struct PronoteProfile: Codable, Equatable, Sendable {
    public var displayName: String
    public var establishment: String
    public var className: String?
    public var resourceID: String
    public var resources: [PronoteStudentResource]
    public var capabilities: [String]
    public var periods: [PronotePeriod]
    /// PRONOTE supplies different available/default periods for each screen.
    /// Optional so caches created by earlier versions remain readable.
    public var defaultPeriodIDs: [String: String]?
    public var sectionPeriodIDs: [String: [String]]?

    public init(displayName: String, establishment: String, className: String? = nil,
                resourceID: String, resources: [PronoteStudentResource] = [],
                capabilities: [String] = [], periods: [PronotePeriod] = [],
                defaultPeriodIDs: [String: String]? = nil, sectionPeriodIDs: [String: [String]]? = nil) {
        self.displayName = displayName; self.establishment = establishment; self.className = className
        self.resourceID = resourceID; self.resources = resources; self.capabilities = capabilities; self.periods = periods
        self.defaultPeriodIDs = defaultPeriodIDs; self.sectionPeriodIDs = sectionPeriodIDs
    }

    public func periods(for section: String) -> [PronotePeriod] {
        guard let ids = sectionPeriodIDs?[section], !ids.isEmpty else { return periods }
        return periods.filter { ids.contains($0.id) }
    }

    public func currentPeriodID(for section: String, at date: Date = Date()) -> String? {
        let available = periods(for: section)
        if let id = defaultPeriodIDs?[section], available.contains(where: { $0.id == id }) { return id }
        let shortest: (PronotePeriod, PronotePeriod) -> Bool = {
            $0.endDate.timeIntervalSince($0.startDate) < $1.endDate.timeIntervalSince($1.startDate)
        }
        if let current = available.filter({ $0.startDate <= date && $0.endDate >= date }).sorted(by: shortest).first { return current.id }
        if let previous = available.filter({ $0.endDate < date }).sorted(by: { $0.endDate > $1.endDate }).first { return previous.id }
        return available.sorted { $0.startDate < $1.startDate }.first?.id
    }
}

public struct PronoteSecurityChallenge: Codable, Equatable, Sendable {
    public var shouldEnterPIN: Bool
    public var shouldCustomPassword: Bool
    public var shouldCustomDoubleAuth: Bool
    public var shouldEnterSource: Bool
    public var availableModes: [Int]
    public var defaultMode: Int
    public var passwordMinLength: Int
    public var passwordMaxLength: Int
    public var message: String

    public init(shouldEnterPIN: Bool = false, shouldCustomPassword: Bool = false,
                shouldCustomDoubleAuth: Bool = false, shouldEnterSource: Bool = false,
                availableModes: [Int] = [], defaultMode: Int = 0,
                passwordMinLength: Int = 0, passwordMaxLength: Int = 0, message: String = "") {
        self.shouldEnterPIN = shouldEnterPIN; self.shouldCustomPassword = shouldCustomPassword
        self.shouldCustomDoubleAuth = shouldCustomDoubleAuth; self.shouldEnterSource = shouldEnterSource
        self.availableModes = availableModes; self.defaultMode = defaultMode
        self.passwordMinLength = passwordMinLength; self.passwordMaxLength = passwordMaxLength; self.message = message
    }
}

/// Separate from the study history: unavailable PRONOTE sections never erase the last readable cache.
public struct PronotePortalCache: Codable, Equatable, Sendable {
    public var profile: PronoteProfile?
    public var sections: [String: SchoolJSON]
    public var updatedAt: [String: Date]

    public init(profile: PronoteProfile? = nil, sections: [String: SchoolJSON] = [:], updatedAt: [String: Date] = [:]) {
        self.profile = profile; self.sections = sections; self.updatedAt = updatedAt
    }
}

public extension SchoolJSON {
    subscript(_ key: String) -> SchoolJSON? { objectValues?[key] }
    var arrayValues: [SchoolJSON]? { if case .array(let values) = self { return values }; return nil }
    var objectValues: [String: SchoolJSON]? { if case .object(let values) = self { return values }; return nil }
    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var numberValue: Double? { if case .number(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var integerValue: Int? {
        guard let value = numberValue, value.isFinite, value.rounded() == value,
              value >= Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value)
    }
}
