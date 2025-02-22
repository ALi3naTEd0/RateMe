import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        
        // Ensure view initialization
        if let view = flutterViewController.view {
            view.frame = NSRect(x: 0, y: 0, width: windowFrame.width, height: windowFrame.height)
        }
        
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        self.backgroundColor = NSColor.white

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()
    }
}
