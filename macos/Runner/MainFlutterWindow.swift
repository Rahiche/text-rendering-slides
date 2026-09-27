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
    self.title = "Text rendering"
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
