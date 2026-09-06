import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // A data grid needs room: open large and centred, and refuse to be squeezed
    // down to a size where the toolbar no longer fits.
    let screen = self.screen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width = min(1360, visible.width - 80)
    let height = min(860, visible.height - 80)
    let frame = NSRect(
      x: visible.midX - width / 2,
      y: visible.midY - height / 2,
      width: width,
      height: height
    )
    self.setFrame(frame, display: true)
    self.minSize = NSSize(width: 720, height: 420)

    RegisterGeneratedPlugins(registry: flutterViewController)

    OpenFileBridge.shared.attach(
      FlutterMethodChannel(
        name: OpenFileBridge.channelName,
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
    )

    super.awakeFromNib()
  }
}
