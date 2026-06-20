import Testing

@testable import AutoImport

struct MediaClassificationTests {
    @Test
    func keepsProxyVideoHelpersClassifiedAsSidecars() {
        #expect(MediaClassification.classify(pathExtension: "lrv") == .sidecar)
        #expect(MediaClassification.classify(pathExtension: "lrf") == .sidecar)
    }

    @Test
    func supportsVideoPreviewForPrimaryAndProxyVideos() {
        #expect(MediaClassification.supportsVideoPreview(pathExtension: "mp4"))
        #expect(MediaClassification.supportsVideoPreview(pathExtension: "mov"))
        #expect(MediaClassification.supportsVideoPreview(pathExtension: "lrv"))
        #expect(MediaClassification.supportsVideoPreview(pathExtension: "lrf"))
        #expect(!MediaClassification.supportsVideoPreview(pathExtension: "thm"))
    }
}
