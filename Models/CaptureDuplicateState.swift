import Foundation

enum CaptureDuplicateState: Hashable, Sendable {
    case unique
    case partial
    case duplicate
}
