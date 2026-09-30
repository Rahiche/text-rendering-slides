import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open as a large 16:9 window centred on the screen (the slides are 16:9).
    if let screen = NSScreen.main {
      let vf = screen.visibleFrame
      let w = min(vf.width * 0.92, vf.height * 0.92 * 16 / 9)
      let h = w * 9 / 16
      self.setFrame(NSRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h), display: true)
    }
    self.title = "Inside Flutter's Text Pipeline"
    self.collectionBehavior.insert(.fullScreenPrimary)

    // Slide export (lib/main_export.dart): a small always-on-top window in the
    // corner, on every Space and over full-screen apps (Flutter stops drawing
    // occluded windows), that ignores the mouse while it walks the deck.
    // SLIDES_EXPORT=<n> picks a slot, so parallel exports don't cover each other.
    if let slot = ProcessInfo.processInfo.environment["SLIDES_EXPORT"], let screen = NSScreen.main {
      let vf = screen.visibleFrame
      let i = CGFloat(Int(slot) ?? 0)
      let cols = max(1, floor(vf.width / 328))
      let x = vf.maxX - 328 * (1 + i.truncatingRemainder(dividingBy: cols))
      let y = vf.minY + 8 + 188 * floor(i / cols)
      self.setFrame(NSRect(x: x, y: y, width: 320, height: 180), display: true)
      self.level = .statusBar
      self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      self.ignoresMouseEvents = true
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
