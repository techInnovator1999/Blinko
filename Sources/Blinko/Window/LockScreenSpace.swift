import AppKit
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "lockscreen")

/// A private SkyLight "space" with an absolute level above the lock screen. Windows moved
/// into it are drawn over loginwindow's shield, which is how the island and the widget panel
/// appear on the lock screen.
///
/// Technique learned from Lakr233's SkyLightWindow (MIT, https://github.com/Lakr233/SkyLightWindow,
/// used by boring.notch, MewNotch and Atoll) and boring.notch's `undelegateWindow`. This is an
/// independent implementation: every symbol is resolved with `dlsym` at first use and the
/// feature turns itself off if any required one is missing — it never crashes or links
/// against SkyLight. Nothing here runs until the screen is first locked with the feature on.
@MainActor
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    /// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`: above the screen-lock space
    /// (300), below boot progress / VoiceOver.
    static let lockScreenLevel: Int32 = 400

    // CGSConnectionID is a 32-bit int, CGSSpaceID a 64-bit integer (CGSInternal headers).
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowHideSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias RemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private struct Symbols {
        let mainConnectionID: MainConnectionID
        let spaceCreate: SpaceCreate
        let spaceDestroy: SpaceDestroy?
        let setAbsoluteLevel: SpaceSetAbsoluteLevel
        let showSpaces: ShowHideSpaces
        let hideSpaces: ShowHideSpaces?
        let addWindows: AddWindowsAndRemoveFromSpaces
        let removeWindows: RemoveWindowsFromSpaces
        let copySpacesForWindows: CopySpacesForWindows?
    }

    /// Required + optional private symbols, for the Settings pane and the round-trip test.
    static let requiredSymbols = ["SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel", "SLSShowSpaces",
                                  "SLSSpaceAddWindowsAndRemoveFromSpaces", "SLSRemoveWindowsFromSpaces"]
    static let optionalSymbols = ["SLSHideSpaces", "SLSSpaceDestroy", "SLSCopySpacesForWindows"]

    private lazy var symbols: Symbols? = Self.resolve()
    private var connection: Int32 = 0
    private(set) var spaceID: UInt64 = 0
    private var isShown = false
    /// Window numbers currently delegated to the space.
    private var members: Set<Int> = []
    private var quitObserver: NSObjectProtocol?

    /// Whether every required private symbol resolved (cheap after the first call).
    var isAvailable: Bool { symbols != nil }

    private static func resolve() -> Symbols? {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            log.error("SkyLight not loadable; lock-screen widgets disabled")
            return nil
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let main = sym("SLSMainConnectionID", MainConnectionID.self),
              let create = sym("SLSSpaceCreate", SpaceCreate.self),
              let level = sym("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
              let show = sym("SLSShowSpaces", ShowHideSpaces.self),
              let add = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindowsAndRemoveFromSpaces.self),
              let remove = sym("SLSRemoveWindowsFromSpaces", RemoveWindowsFromSpaces.self)
        else {
            log.error("SkyLight symbols missing; lock-screen widgets disabled")
            return nil
        }
        return Symbols(mainConnectionID: main, spaceCreate: create,
                       spaceDestroy: sym("SLSSpaceDestroy", SpaceDestroy.self),
                       setAbsoluteLevel: level, showSpaces: show,
                       hideSpaces: sym("SLSHideSpaces", ShowHideSpaces.self),
                       addWindows: add, removeWindows: remove,
                       copySpacesForWindows: sym("SLSCopySpacesForWindows", CopySpacesForWindows.self))
    }

    /// Creates the space on first use (lazily: never at launch) and makes it visible.
    @discardableResult
    func show() -> Bool {
        guard let s = symbols else { return false }
        if spaceID == 0 {
            connection = s.mainConnectionID()
            guard connection != 0 else { log.error("no SkyLight connection"); return false }
            // Flag 1: a "user" space without desktop (0 makes Finder draw icons into it).
            let id = s.spaceCreate(connection, 1, nil)
            guard id != 0 else { log.error("SLSSpaceCreate failed"); return false }
            spaceID = id
            let err = s.setAbsoluteLevel(connection, id, Self.lockScreenLevel)
            if err != 0 { log.error("SLSSpaceSetAbsoluteLevel error \(err)") }
            quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                  object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SkyLightSpace.shared.destroy() }
            }
            log.info("created lock-screen space \(id)")
        }
        if !isShown {
            let err = s.showSpaces(connection, [NSNumber(value: spaceID)] as CFArray)
            if err != 0 { log.error("SLSShowSpaces error \(err)") }
            isShown = true
        }
        return true
    }

    /// Hides the (then empty) space while unlocked; it is re-shown on the next lock.
    func hide() {
        guard let s = symbols, spaceID != 0, isShown else { return }
        if let hideSpaces = s.hideSpaces { _ = hideSpaces(connection, [NSNumber(value: spaceID)] as CFArray) }
        isShown = false
    }

    /// Moves a window into the space (and out of its regular spaces). The window must have
    /// a window-server window (`windowNumber > 0`), i.e. have been ordered in once.
    @discardableResult
    func add(_ window: NSWindow) -> Bool {
        guard let s = symbols, spaceID != 0, window.windowNumber > 0 else { return false }
        let err = s.addWindows(connection, spaceID, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        if err != 0 { log.error("SLSSpaceAddWindowsAndRemoveFromSpaces error \(err)"); return false }
        members.insert(window.windowNumber)
        return true
    }

    /// Takes a window back out of the space. The caller restores level / collection behaviour,
    /// which makes AppKit re-register the window with the user's spaces.
    func remove(_ window: NSWindow) {
        remove(windowNumber: window.windowNumber)
    }

    func remove(windowNumber: Int) {
        guard let s = symbols, spaceID != 0, windowNumber > 0 else { return }
        let err = s.removeWindows(connection, [NSNumber(value: windowNumber)] as CFArray,
                                  [NSNumber(value: spaceID)] as CFArray)
        if err != 0 { log.error("SLSRemoveWindowsFromSpaces error \(err)") }
        members.remove(windowNumber)
    }

    func contains(_ window: NSWindow) -> Bool { members.contains(window.windowNumber) }

    /// Space IDs the window server reports for a window (diagnostics / round-trip test).
    func spaces(of window: NSWindow) -> [UInt64]? {
        guard let s = symbols, let copy = s.copySpacesForWindows, window.windowNumber > 0 else { return nil }
        let cid = connection != 0 ? connection : s.mainConnectionID()
        guard let array = copy(cid, 7, [NSNumber(value: window.windowNumber)] as CFArray)?.takeRetainedValue()
                as? [NSNumber] else { return [] }
        return array.map(\.uint64Value)
    }

    /// Spaces created by an app must be destroyed before it exits.
    func destroy() {
        guard let s = symbols, spaceID != 0 else { return }
        for number in members { remove(windowNumber: number) }
        hide()
        _ = s.spaceDestroy?(connection, spaceID)
        spaceID = 0
    }
}
