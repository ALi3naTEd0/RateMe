import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        
        // Set window properties
        self.contentMinSize = NSSize(width: 800, height: 600)
        self.contentAspectRatio = NSSize(width: 16, height: 9)
        self.titlebarAppearsTransparent = true
        
        // Set content view controller
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        // Register plugins
        RegisterGeneratedPlugins(registry: flutterViewController)
        
        super.awakeFromNib()
    }
}
