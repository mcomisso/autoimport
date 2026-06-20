import Foundation
import AVFoundation
import ImageIO

struct CaptureMetadata: Hashable, Sendable {
    let sourceFileName: String
    let rows: [CaptureMetadataItem]
}

struct CaptureMetadataItem: Identifiable, Hashable, Sendable {
    enum Field: String, Hashable, Sendable {
        case camera
        case lens
        case captured
        case duration
        case aperture
        case shutterSpeed
        case iso
        case focalLength
        case dimensions
        case software
        case location
    }

    let field: Field
    let label: String
    let value: String

    var id: Field {
        field
    }
}

enum CaptureMetadataReader {
    static func metadata(for fileURL: URL) async -> CaptureMetadata {
        if let imageMetadata = imageMetadata(for: fileURL) {
            return imageMetadata
        }

        return await videoMetadata(for: fileURL)
    }

    static func metadata(for fileURL: URL) -> CaptureMetadata {
        imageMetadata(for: fileURL) ?? CaptureMetadata(sourceFileName: fileURL.lastPathComponent, rows: [])
    }

    private static func imageMetadata(for fileURL: URL) -> CaptureMetadata? {
        let options = [
            kCGImageSourceShouldCache as String: false,
        ] as CFDictionary

        guard
            let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options) as? [String: Any]
        else {
            return nil
        }

        return metadata(from: properties, sourceFileName: fileURL.lastPathComponent)
    }

    static func metadata(from properties: [String: Any], sourceFileName: String = "") -> CaptureMetadata {
        let exif = dictionaryValue(for: kCGImagePropertyExifDictionary, in: properties)
        let tiff = dictionaryValue(for: kCGImagePropertyTIFFDictionary, in: properties)
        let gps = dictionaryValue(for: kCGImagePropertyGPSDictionary, in: properties)

        var rows: [CaptureMetadataItem] = []
        append(.camera, label: "Camera", value: cameraText(from: tiff), to: &rows)
        append(.lens, label: "Lens", value: stringValue(for: kCGImagePropertyExifLensModel, in: exif), to: &rows)
        append(.captured, label: "Captured", value: stringValue(for: kCGImagePropertyExifDateTimeOriginal, in: exif), to: &rows)
        append(.aperture, label: "Aperture", value: apertureText(from: exif), to: &rows)
        append(.shutterSpeed, label: "Shutter", value: shutterText(from: exif), to: &rows)
        append(.iso, label: "ISO", value: isoText(from: exif), to: &rows)
        append(.focalLength, label: "Focal Length", value: focalLengthText(from: exif), to: &rows)
        append(.dimensions, label: "Dimensions", value: dimensionsText(from: properties), to: &rows)
        append(.software, label: "Software", value: stringValue(for: kCGImagePropertyTIFFSoftware, in: tiff), to: &rows)
        append(.location, label: "Location", value: locationText(from: gps), to: &rows)

        return CaptureMetadata(sourceFileName: sourceFileName, rows: rows)
    }

    static func metadata(
        fromVideoMetadata metadataItems: [AVMetadataItem],
        sourceFileName: String = "",
        duration: TimeInterval? = nil,
        pixelSize: PixelSize? = nil
    ) async -> CaptureMetadata {
        var rows: [CaptureMetadataItem] = []
        append(.camera, label: "Camera", value: await cameraText(fromVideoMetadata: metadataItems), to: &rows)
        append(.captured, label: "Captured", value: await videoMetadataString(
            for: [.quickTimeMetadataCreationDate, .commonIdentifierCreationDate],
            in: metadataItems
        ), to: &rows)
        append(.duration, label: "Duration", value: duration.map(CaptureDisplayFormatter.duration), to: &rows)
        append(.dimensions, label: "Dimensions", value: CaptureDisplayFormatter.dimensions(pixelSize), to: &rows)
        append(.software, label: "Software", value: await videoMetadataString(
            for: [.quickTimeMetadataSoftware, .commonIdentifierSoftware],
            in: metadataItems
        ), to: &rows)
        append(.location, label: "Location", value: await videoMetadataString(
            for: [.quickTimeMetadataLocationISO6709, .commonIdentifierLocation],
            in: metadataItems
        ), to: &rows)

        return CaptureMetadata(sourceFileName: sourceFileName, rows: rows)
    }

    private static func append(
        _ field: CaptureMetadataItem.Field,
        label: String,
        value: String?,
        to rows: inout [CaptureMetadataItem]
    ) {
        guard let value, !value.isEmpty else {
            return
        }

        rows.append(CaptureMetadataItem(field: field, label: label, value: value))
    }

    private static func videoMetadata(for fileURL: URL) async -> CaptureMetadata {
        let asset = AVURLAsset(url: fileURL)

        do {
            let metadataItems = try await asset.load(.metadata)
            let commonMetadataItems = try await asset.load(.commonMetadata)
            let duration = try? await videoDuration(for: asset)
            let pixelSize = try? await videoPixelSize(for: asset)

            return await metadata(
                fromVideoMetadata: metadataItems + commonMetadataItems,
                sourceFileName: fileURL.lastPathComponent,
                duration: duration,
                pixelSize: pixelSize
            )
        } catch {
            return CaptureMetadata(sourceFileName: fileURL.lastPathComponent, rows: [])
        }
    }

    private static func cameraText(from tiff: [String: Any]) -> String? {
        let parts = [
            stringValue(for: kCGImagePropertyTIFFMake, in: tiff),
            stringValue(for: kCGImagePropertyTIFFModel, in: tiff),
        ]
        .compactMap { $0 }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " ")
    }

    private static func cameraText(fromVideoMetadata metadataItems: [AVMetadataItem]) async -> String? {
        let parts = [
            await videoMetadataString(for: [.quickTimeMetadataMake, .commonIdentifierMake], in: metadataItems),
            await videoMetadataString(for: [.quickTimeMetadataModel, .commonIdentifierModel], in: metadataItems),
        ]
        .compactMap { $0 }

        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }

        return await videoMetadataString(for: [.quickTimeMetadataCameraIdentifier], in: metadataItems)
    }

    private static func apertureText(from exif: [String: Any]) -> String? {
        guard let fNumber = doubleValue(for: kCGImagePropertyExifFNumber, in: exif) else {
            return nil
        }

        return "f/\(decimalText(fNumber))"
    }

    private static func shutterText(from exif: [String: Any]) -> String? {
        guard let exposureTime = doubleValue(for: kCGImagePropertyExifExposureTime, in: exif), exposureTime > 0 else {
            return nil
        }

        if exposureTime < 1 {
            let denominator = max(1, Int((1 / exposureTime).rounded()))
            return "1/\(denominator) s"
        }

        return "\(decimalText(exposureTime)) s"
    }

    private static func isoText(from exif: [String: Any]) -> String? {
        let isoValues = intArrayValue(for: kCGImagePropertyExifISOSpeedRatings, in: exif)
        guard !isoValues.isEmpty else {
            return nil
        }

        return "ISO \(isoValues.map(String.init).joined(separator: ", "))"
    }

    private static func focalLengthText(from exif: [String: Any]) -> String? {
        guard let focalLength = doubleValue(for: kCGImagePropertyExifFocalLength, in: exif) else {
            return nil
        }

        return "\(decimalText(focalLength)) mm"
    }

    private static func locationText(from gps: [String: Any]) -> String? {
        guard
            let latitude = doubleValue(for: kCGImagePropertyGPSLatitude, in: gps),
            let longitude = doubleValue(for: kCGImagePropertyGPSLongitude, in: gps)
        else {
            return nil
        }

        let latitudeRef = stringValue(for: kCGImagePropertyGPSLatitudeRef, in: gps)?.uppercased()
        let longitudeRef = stringValue(for: kCGImagePropertyGPSLongitudeRef, in: gps)?.uppercased()
        let signedLatitude = latitudeRef == "S" ? -latitude : latitude
        let signedLongitude = longitudeRef == "W" ? -longitude : longitude

        return "\(coordinateText(signedLatitude)), \(coordinateText(signedLongitude))"
    }

    private static func dimensionsText(from properties: [String: Any]) -> String? {
        guard
            let width = intValue(for: kCGImagePropertyPixelWidth, in: properties),
            let height = intValue(for: kCGImagePropertyPixelHeight, in: properties)
        else {
            return nil
        }

        return "\(width)x\(height)"
    }

    private static func videoDuration(for asset: AVAsset) async throws -> TimeInterval? {
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }

        return seconds
    }

    private static func videoPixelSize(for asset: AVAsset) async throws -> PixelSize? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            return nil
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())

        guard width > 0, height > 0 else {
            return nil
        }

        return PixelSize(width: width, height: height)
    }

    private static func videoMetadataString(
        for identifiers: [AVMetadataIdentifier],
        in metadataItems: [AVMetadataItem]
    ) async -> String? {
        for identifier in identifiers {
            let matchingItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: identifier)
            for item in matchingItems {
                if let value = await stringValue(from: item) {
                    return value
                }
            }
        }

        return nil
    }

    private static func stringValue(from metadataItem: AVMetadataItem) async -> String? {
        if let string = try? await metadataItem.load(.stringValue) {
            let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedString.isEmpty ? nil : trimmedString
        }

        if let number = try? await metadataItem.load(.numberValue) {
            return number.stringValue
        }

        if let date = try? await metadataItem.load(.dateValue) {
            return ISO8601DateFormatter().string(from: date)
        }

        guard let value = try? await metadataItem.load(.value) else {
            return nil
        }

        let valueString = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return valueString.isEmpty ? nil : valueString
    }

    private static func dictionaryValue(for key: CFString, in dictionary: [String: Any]) -> [String: Any] {
        dictionary[key as String] as? [String: Any] ?? [:]
    }

    private static func stringValue(for key: CFString, in dictionary: [String: Any]) -> String? {
        guard let value = dictionary[key as String] else {
            return nil
        }

        if let string = value as? String {
            let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedString.isEmpty ? nil : trimmedString
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private static func doubleValue(for key: CFString, in dictionary: [String: Any]) -> Double? {
        guard let value = dictionary[key as String] else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let double = value as? Double {
            return double
        }

        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private static func intValue(for key: CFString, in dictionary: [String: Any]) -> Int? {
        guard let value = dictionary[key as String] else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let int = value as? Int {
            return int
        }

        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private static func intArrayValue(for key: CFString, in dictionary: [String: Any]) -> [Int] {
        guard let value = dictionary[key as String] else {
            return []
        }

        if let values = value as? [NSNumber] {
            return values.map(\.intValue)
        }

        if let values = value as? [Int] {
            return values
        }

        if let number = value as? NSNumber {
            return [number.intValue]
        }

        if let int = value as? Int {
            return [int]
        }

        return []
    }

    private static func decimalText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }

        return String(format: "%.1f", rounded)
    }

    private static func coordinateText(_ value: Double) -> String {
        String(format: "%.5f", value)
    }
}
