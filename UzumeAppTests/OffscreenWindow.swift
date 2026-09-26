// OffscreenWindow — the one way app tests build an AppKit window they later close. (BUG-143)
//
// A window made in code has `isReleasedWhenClosed == true`, a pre-ARC convention:
// `close()` releases it once more on the caller's behalf. ARC also owns it, so the
// window takes one release too many. When the pool drains it frees a window
// something still points at, and a later release crashes the test host
// (`objc_release` ← `objc_autoreleasePoolPop`). Whether it crashes depends on
// timing and allocator state — three DS.6 tests used the pattern, and the host
// died only when the app tests ran straight after the engine suite.

import AppKit
import Foundation
import Testing

// MARK: - Helper

extension NSWindow {

    /// A borderless, dark, buffered window that is safe to `close()` under ARC.
    @MainActor
    static func offscreen(_ contentRect: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        return window
    }
}

// MARK: - Tests

@Suite("Offscreen window (BUG-143)")
@MainActor
struct OffscreenWindowTests {

    @Test("closing a held window does not free it")
    func close_doesNotFreeAHeldWindow() throws {
        weak var weakWindow: NSWindow?
        let window = NSWindow.offscreen(CGRect(x: 0, y: 0, width: 64, height: 64))
        // Fail cleanly here: past this line an unfixed helper crashes the host outright
        // (3/3 runs, the BUG-143 signature) instead of failing the expectation below.
        try #require(!window.isReleasedWhenClosed)
        weakWindow = window
        window.contentView = NSView(frame: window.frame)
        autoreleasepool {
            window.contentView = nil
            window.close()
        }
        #expect(weakWindow != nil, "close() freed a window ARC still owns — isReleasedWhenClosed is true")
        withExtendedLifetime(window) {}
    }

    @Test("no test builds a raw NSWindow and closes it")
    func noRawWindowIsClosed() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "OffscreenWindow.swift" }
        let offenders = try files
            .filter {
                let source = try String(contentsOf: $0, encoding: .utf8)
                return source.contains("NSWindow(") && source.contains(".close()")
            }
            .map(\.lastPathComponent)
        #expect(offenders.isEmpty, "build closable windows with NSWindow.offscreen(_:): \(offenders)")
    }
}
