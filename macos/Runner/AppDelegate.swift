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

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
