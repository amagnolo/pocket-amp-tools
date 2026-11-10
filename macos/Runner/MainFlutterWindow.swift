import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Closing goes through the app's exit request, which asks first while
    // the pedal is being written; the window stays up while it asks.
    self.delegate = self

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(nil)
    return false
  }
}
