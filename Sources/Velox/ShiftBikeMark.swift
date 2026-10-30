import SwiftUI

/// A road-bike outline with two small, fixed scanline displacements.
/// Kept as vector paths so the compact header stays crisp on Retina displays.
struct ShiftBikeMark: View {
    var body: some View {
        Canvas { context, size in
            let sx=size.width/64, sy=size.height/40
            let outline=RoadBikeOutline().path(in:CGRect(origin:.zero,size:size))
            let stroke=StrokeStyle(lineWidth:1.8*min(sx,sy),lineCap:.round,lineJoin:.round)
            func band(_ top:CGFloat,_ height:CGFloat,_ shift:CGFloat,_ color:Color) {
                var slice=context
                slice.clip(to:Path(CGRect(x:0,y:top*sy,width:size.width,height:height*sy)))
                slice.translateBy(x:shift*sx,y:0)
                slice.stroke(outline,with:.color(color),style:stroke)
            }
            band(0,13,0,.lime)
            band(13,2,2.6,Color(red:0.52,green:0.89,blue:0.94))
            band(15,11,0,.lime)
            band(26,1.5,-2,.white.opacity(0.8))
            band(27.5,12.5,0,.lime)
        }
    }
}

struct RoadBikeOutline: Shape {
    func path(in rect:CGRect) -> Path {
        var p=Path()
        p.addEllipse(in:CGRect(x:4,y:17,width:20,height:20))
        p.addEllipse(in:CGRect(x:40,y:17,width:20,height:20))
        p.move(to:CGPoint(x:14,y:27))
        p.addLines([CGPoint(x:26,y:11),CGPoint(x:34,y:27),CGPoint(x:14,y:27)])
        p.move(to:CGPoint(x:26,y:11))
        p.addLines([CGPoint(x:43,y:10),CGPoint(x:34,y:27)])
        p.move(to:CGPoint(x:50,y:27))
        p.addLines([CGPoint(x:42,y:5),CGPoint(x:48,y:5)])
        p.addCurve(to:CGPoint(x:49,y:12),control1:CGPoint(x:54,y:5),control2:CGPoint(x:54,y:11))
        p.move(to:CGPoint(x:26,y:11))
        p.addLine(to:CGPoint(x:24,y:7))
        p.move(to:CGPoint(x:21,y:7))
        p.addLine(to:CGPoint(x:29,y:7))
        p.move(to:CGPoint(x:34,y:27))
        p.addLines([CGPoint(x:37,y:30),CGPoint(x:40,y:30)])
        return p.applying(CGAffineTransform(scaleX:rect.width/64,y:rect.height/40).concatenating(CGAffineTransform(translationX:rect.minX,y:rect.minY)))
    }
}
