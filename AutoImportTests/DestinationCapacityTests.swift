import Testing

@testable import AutoImport

struct DestinationCapacityTests {
    @Test
    func usesRawAvailableCapacityWhenScopedCapacityReportsZero() {
        let available = DestinationCapacity.resolveAvailableBytes(
            totalBytes: 1_000,
            importantUsageCapacity: 0,
            opportunisticUsageCapacity: nil,
            rawAvailableCapacity: 900
        )

        #expect(available == 900)
    }

    @Test
    func keepsUsageScopedCapacityWhenItIsTheLargestCandidate() {
        let available = DestinationCapacity.resolveAvailableBytes(
            totalBytes: 1_000,
            importantUsageCapacity: 850,
            opportunisticUsageCapacity: 650,
            rawAvailableCapacity: 700
        )

        #expect(available == 850)
    }

    @Test
    func clampsAvailableCapacityToVolumeTotal() {
        let available = DestinationCapacity.resolveAvailableBytes(
            totalBytes: 1_000,
            importantUsageCapacity: 1_200,
            opportunisticUsageCapacity: nil,
            rawAvailableCapacity: nil
        )

        #expect(available == 1_000)
    }
}
