import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        
        // Initialize view and frame
        if let flutterView = flutterViewController.view {
            flutterView.wantsLayer = true
            flutterView.layer?.backgroundColor = NSColor.white.cgColor
        }
        
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        // Basic window configuration
        self.titlebarAppearsTransparent = false
        self.backgroundColor = NSColor.white

        RegisterGeneratedPlugins(registry: flutterViewController)
        super.awakeFromNib()
    }
}
