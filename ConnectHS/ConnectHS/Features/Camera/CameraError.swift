import Foundation

enum CameraError: LocalizedError, Sendable {
    case permissionDenied
    case noCameraAvailable
    case captureFailed
    case encodeFailed
    case uploadFailed
    case alreadyPostedToday
    case noActiveGroup

    var errorDescription: String? {
        switch self {
        case .permissionDenied:    return String(localized: "camera.error.permissionDenied")
        case .noCameraAvailable:   return String(localized: "camera.error.noCameraAvailable")
        case .captureFailed:       return String(localized: "camera.error.captureFailed")
        case .encodeFailed:        return String(localized: "camera.error.encodeFailed")
        case .uploadFailed:        return String(localized: "camera.error.uploadFailed")
        case .alreadyPostedToday:  return String(localized: "camera.error.alreadyPostedToday")
        case .noActiveGroup:       return String(localized: "camera.error.noActiveGroup")
        }
    }
}
