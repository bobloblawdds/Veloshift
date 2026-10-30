import SwiftUI
import AppKit

@main
struct VeloshiftApp:App {
    @StateObject private var session=Session()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body:some Scene {
        WindowGroup("Veloshift") {
            RootView(session:session)
                .onAppear {
                    delegate.session=session
                    DispatchQueue.main.async { delegate.configureWindow() }
                    if CommandLine.arguments.contains("--demo") { session.startDemo() }
                    if let i=CommandLine.arguments.firstIndex(of:"--render-preview"), i+1<CommandLine.arguments.count {
                        session.startDemo()
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                            let renderer=ImageRenderer(content:RootView(session:session).frame(width:380,height:900))
                            renderer.scale=2
                            if let image=renderer.nsImage, let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff), let png=bitmap.representation(using:.png,properties:[:]) {
                                try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]))
                            }
                            NSApp.terminate(nil)
                        }
                    }
                }
                .onDisappear { session.stopAll() }
        }.windowStyle(.hiddenTitleBar).defaultSize(width:380,height:900)
        .commands { CommandGroup(replacing:.newItem) {}; CommandMenu("Ride") {
            Button("Connect devices") { session.scan() }
            Button("Start bridge") { session.startBridge() }.disabled(!session.trainerReady || session.demo)
            Button("Stop bridge") { session.stopBridge() }
            Divider()
            Button("Shift easier (\(session.shiftShortcutKeys.easier))") { session.shiftFromKeyboard(-1) }.disabled(!session.canShiftFromKeyboard)
            Button("Shift harder (\(session.shiftShortcutKeys.harder))") { session.shiftFromKeyboard(1) }.disabled(!session.canShiftFromKeyboard)
            Divider()
            Button("Fit to screen edge") { NotificationCenter.default.post(name:.veloxFitWindow,object:nil) }
            Button("Explore demo") { session.startDemo() }
        } }
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var session:Session?
    private var configured=false
    private var fitObserver:NSObjectProtocol?
    func configureWindow() {
        guard !configured,let window=NSApp.windows.first(where:{ $0.canBecomeMain }) else { return }
        configured=true;WindowPlacement.configure(window)
        fitObserver=NotificationCenter.default.addObserver(forName:.veloxFitWindow,object:nil,queue:.main) { [weak window] _ in
            if let window { WindowPlacement.fit(window) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationWillTerminate(_ notification:Notification) { session?.stopAll() }
}
