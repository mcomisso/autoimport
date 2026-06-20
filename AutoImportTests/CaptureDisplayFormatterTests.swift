import Foundation
import Testing

@testable import AutoImport

struct CaptureDisplayFormatterTests {
    @Test
    func formatsShortAndLongDurationsForTheBrowser() {
        #expect(CaptureDisplayFormatter.duration(45) == "0:45")
        #expect(CaptureDisplayFormatter.duration(3_661) == "1:01:01")
    }

    @Test
    func combinesMultipartCountAndDurationWhenBothExist() {
        #expect(CaptureDisplayFormatter.multipartSummary(segmentCount: 2, totalDuration: 93) == "2 parts · 1:33")
        #expect(CaptureDisplayFormatter.multipartSummary(segmentCount: 1, totalDuration: nil) == nil)
    }
}
