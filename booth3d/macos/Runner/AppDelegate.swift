import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var exportActivity: NSObjectProtocol?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Slide export: don't take focus from whatever the user is doing, and
    // don't let App Nap throttle timers or frames while exporting.
    if ProcessInfo.processInfo.environment["SLIDES_EXPORT"] != nil {
      NSApp.setActivationPolicy(.accessory)
      exportActivity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .latencyCritical], reason: "Exporting slides")
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // The booth app (Info.plist BoothKiosk = true, set by
    // tool/build_booth_macos.sh): visitors at the keyboard can't quit, hide,
    // close or minimise it with ⌘Q/⌘H/⌘W/⌘M. Staff quit with Ctrl+Shift+Q.
    if Bundle.main.object(forInfoDictionaryKey: "BoothKiosk") as? Bool == true {
      func strip(_ menu: NSMenu?) {
        for item in menu?.items ?? [] {
          if item.keyEquivalentModifierMask.contains(.command),
            ["q", "h", "w", "m"].contains(item.keyEquivalent.lowercased())
          {
            item.keyEquivalent = ""
          }
          strip(item.submenu)
        }
      }
      strip(NSApp.mainMenu)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
