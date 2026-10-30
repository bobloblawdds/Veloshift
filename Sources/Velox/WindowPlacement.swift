import AppKit

extension Notification.Name { static let veloxFitWindow=Notification.Name("VeloxFitWindow") }

/// App-owned window placement, in logical screen points (independent of Retina scale).
enum WindowPlacement {
    static let savedFrame="Velox.Companion.v04"
    static func configure(_ window:NSWindow) {
        window.contentMinSize=NSSize(width:300,height:560)
        if !window.setFrameUsingName(savedFrame) { fit(window) }
        window.setFrameAutosaveName(savedFrame)
    }
    static func fit(_ window:NSWindow) {
        guard let screen=window.screen ?? NSScreen.main else { return }
        let available=screen.visibleFrame
        let width=min(520,max(300,(available.width*0.25).rounded()))
        window.setFrame(NSRect(x:available.maxX-width,y:available.minY,width:width,height:available.height),display:true)
    }
}
