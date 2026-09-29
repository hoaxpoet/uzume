// BuildFlavorTests — the public build records no sessions (CLEAN.2.5b, BUG-157).

import Testing
@testable import UzumeApp

// MARK: - BuildFlavorTests

@Suite("BuildFlavor")
struct BuildFlavorTests {

    @Test func publicBuild_recordsNoSessions() {
        #expect(BuildFlavor.public.recordsSessions == false)
    }

    @Test func developerBuild_recordsSessions() {
        #expect(BuildFlavor.developer.recordsSessions)
    }

    /// Only `Scripts/release.sh` sets `UZUME_BUILD_FLAVOR = public`; the test host is a developer build.
    @Test func testBuild_isDeveloperFlavor() {
        #expect(BuildFlavor.current == .developer)
    }
}
