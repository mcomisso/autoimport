import Foundation

enum DestinationOrganizationMode: String, CaseIterable, Codable, Sendable {
    case flat
    case byDate
    case byCameraAndDate
}
