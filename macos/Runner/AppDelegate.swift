import Cocoa
import FlutterMacOS

/// Bridges files opened through Finder ("Abrir com", double click, drop on the
/// Dock icon) to the Flutter side. Files can arrive before the engine is ready,
/// so they are queued until Dart asks for them.
final class OpenFileBridge {
  static let shared = OpenFileBridge()
  static let channelName = "csviewer/open_file"

  private var pending: [String] = []
  private var channel: FlutterMethodChannel?

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "consumePending" {
        let files = self.pending
        self.pending = []
        result(files)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func open(_ path: String) {
    if let channel = channel {
      channel.invokeMethod("openFile", arguments: path)
    } else {
      pending.append(path)
    }
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    OpenFileBridge.shared.open(filename)
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL {
      OpenFileBridge.shared.open(url.path)
    }
  }
}
