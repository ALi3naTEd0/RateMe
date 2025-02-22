import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        // Add this line to fix black screen
        flutterViewController.view.wantsLayer = true

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()
    }
}
