import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AutoImport

struct CaptureMetadataReaderTests {
    @Test
    func buildsDisplayRowsFromImageProperties() {
        let metadata = CaptureMetadataReader.metadata(
            from: [
                kCGImagePropertyPixelWidth as String: 6_000,
                kCGImagePropertyPixelHeight as String: 4_000,
                kCGImagePropertyTIFFDictionary as String: [
                    kCGImagePropertyTIFFMake as String: "Nikon",
                    kCGImagePropertyTIFFModel as String: "Z 8",
                ],
                kCGImagePropertyExifDictionary as String: [
                    kCGImagePropertyExifLensModel as String: "NIKKOR Z 24-70mm f/2.8 S",
                    kCGImagePropertyExifDateTimeOriginal as String: "2026:06:20 14:15:16",
                    kCGImagePropertyExifFNumber as String: 2.8,
                    kCGImagePropertyExifExposureTime as String: 0.008,
                    kCGImagePropertyExifISOSpeedRatings as String: [100],
                    kCGImagePropertyExifFocalLength as String: 35,
                ],
            ],
            sourceFileName: "DSC_0001.JPG"
        )

        let valuesByField = Dictionary(uniqueKeysWithValues: metadata.rows.map { ($0.field, $0.value) })

        #expect(metadata.sourceFileName == "DSC_0001.JPG")
        #expect(valuesByField[.camera] == "Nikon Z 8")
        #expect(valuesByField[.lens] == "NIKKOR Z 24-70mm f/2.8 S")
        #expect(valuesByField[.captured] == "2026:06:20 14:15:16")
        #expect(valuesByField[.aperture] == "f/2.8")
        #expect(valuesByField[.shutterSpeed] == "1/125 s")
        #expect(valuesByField[.iso] == "ISO 100")
        #expect(valuesByField[.focalLength] == "35 mm")
        #expect(valuesByField[.dimensions] == "6000x4000")
    }

    @Test
    func buildsDisplayRowsFromVideoMetadata() async {
        let metadata = await CaptureMetadataReader.metadata(
            fromVideoMetadata: [
                makeMetadataItem(.quickTimeMetadataMake, value: "Apple"),
                makeMetadataItem(.quickTimeMetadataModel, value: "iPhone 15 Pro"),
                makeMetadataItem(.quickTimeMetadataCreationDate, value: "2026-06-20T14:15:16Z"),
                makeMetadataItem(.quickTimeMetadataSoftware, value: "Camera"),
                makeMetadataItem(.quickTimeMetadataLocationISO6709, value: "+51.5074-000.1278+035.000/"),
            ],
            sourceFileName: "IMG_0001.MOV",
            duration: 62,
            pixelSize: PixelSize(width: 3_840, height: 2_160)
        )

        let valuesByField = Dictionary(uniqueKeysWithValues: metadata.rows.map { ($0.field, $0.value) })

        #expect(metadata.sourceFileName == "IMG_0001.MOV")
        #expect(valuesByField[.camera] == "Apple iPhone 15 Pro")
        #expect(valuesByField[.captured] == "2026-06-20T14:15:16Z")
        #expect(valuesByField[.duration] == "1:02")
        #expect(valuesByField[.dimensions] == "3840×2160")
        #expect(valuesByField[.software] == "Camera")
        #expect(valuesByField[.location] == "+51.5074-000.1278+035.000/")
    }

    @Test
    func readsMetadataFromGeneratedJPEG() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try writeJPEG(
            to: fileURL,
            properties: [
                kCGImagePropertyTIFFDictionary as String: [
                    kCGImagePropertyTIFFMake as String: "Canon",
                    kCGImagePropertyTIFFModel as String: "R6",
                ],
                kCGImagePropertyExifDictionary as String: [
                    kCGImagePropertyExifFNumber as String: 4.0,
                    kCGImagePropertyExifExposureTime as String: 0.01,
                    kCGImagePropertyExifISOSpeedRatings as String: [400],
                ],
            ]
        )

        let metadata = CaptureMetadataReader.metadata(for: fileURL)
        let valuesByField = Dictionary(uniqueKeysWithValues: metadata.rows.map { ($0.field, $0.value) })

        #expect(metadata.sourceFileName == fileURL.lastPathComponent)
        #expect(valuesByField[.camera] == "Canon R6")
        #expect(valuesByField[.aperture] == "f/4")
        #expect(valuesByField[.shutterSpeed] == "1/100 s")
        #expect(valuesByField[.iso] == "ISO 400")
        #expect(valuesByField[.dimensions] == "1x1")
    }

    @Test
    func returnsEmptyRowsForUnreadableFiles() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data("not an image".utf8).write(to: fileURL)

        let metadata = CaptureMetadataReader.metadata(for: fileURL)

        #expect(metadata.sourceFileName == fileURL.lastPathComponent)
        #expect(metadata.rows.isEmpty)
    }

    private func makeMetadataItem(
        _ identifier: AVMetadataIdentifier,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private func writeJPEG(to fileURL: URL, properties: [String: Any]) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ),
            let image = makeOnePixelImage()
        else {
            Issue.record("Unable to create JPEG destination")
            return
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func makeOnePixelImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: UInt32 = 0xFFFFFFFF

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }
}
