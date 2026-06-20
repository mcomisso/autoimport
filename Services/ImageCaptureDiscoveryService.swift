import Foundation
import ImageCaptureCore

@MainActor
final class ImageCaptureDiscoveryService: NSObject, @preconcurrency ICDeviceBrowserDelegate {
    static let shared = ImageCaptureDiscoveryService()

    private let browser: ICDeviceBrowser
    private var sourcesByID: [String: SourceDevice] = [:]
    private var hasStarted = false

    override init() {
        let browser = ICDeviceBrowser()
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        ) ?? .camera
        self.browser = browser
        super.init()
        self.browser.delegate = self
    }

    func currentSources() -> [SourceDevice] {
        startIfNeeded()
        return sourcesByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        browser.start()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let source = makeSource(from: device)
        sourcesByID[source.id] = source
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        let identifier = makeIdentifier(for: device)
        sourcesByID.removeValue(forKey: identifier)
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
        let source = makeSource(from: device)
        sourcesByID[source.id] = source
    }

    private func makeSource(from device: ICDevice) -> SourceDevice {
        SourceDevice(
            id: makeIdentifier(for: device),
            displayName: device.name ?? device.productKind ?? "Camera",
            kind: .imageCaptureDevice,
            rootURL: nil,
            subtitle: device.locationDescription ?? device.transportType ?? "Connected device",
            state: .ready
        )
    }

    private func makeIdentifier(for device: ICDevice) -> String {
        if let uuid = device.uuidString, !uuid.isEmpty {
            return "image-capture::\(uuid)"
        }

        let name = device.name ?? device.productKind ?? "camera"
        return "image-capture::\(name)"
    }
}
