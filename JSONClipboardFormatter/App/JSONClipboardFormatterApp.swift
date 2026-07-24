import AppKit
import SwiftUI

@main
struct BracePasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar apps use AppDelegate for the status item; Settings scene is optional.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        appController = controller
        menuBarController = MenuBarController(appController: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
