import AppKit
let dir=CommandLine.arguments[1]
for size in [16,32,64,128,256,512,1024] {
 let n=CGFloat(size)
 let image=NSImage(size:NSSize(width:n,height:n))
 image.lockFocus()
 let ctx=NSGraphicsContext.current!.cgContext
 ctx.scaleBy(x:n/1024,y:n/1024)
 let bg=NSBezierPath(roundedRect:NSRect(x:45,y:45,width:934,height:934),xRadius:210,yRadius:210)
 NSGradient(starting:NSColor(calibratedRed:0.12,green:0.21,blue:0.44,alpha:1),ending:NSColor(calibratedRed:0.29,green:0.40,blue:0.72,alpha:1))!.draw(in:bg,angle:55)
 let moon=NSBezierPath()
 moon.appendOval(in:NSRect(x:210,y:240,width:535,height:535))
 moon.appendOval(in:NSRect(x:370,y:365,width:460,height:460))
 moon.windingRule = .evenOdd
 NSGraphicsContext.saveGraphicsState()
 NSBezierPath(ovalIn:NSRect(x:210,y:240,width:535,height:535)).addClip()
 NSColor(calibratedRed:0.91,green:0.96,blue:1,alpha:1).setFill();moon.fill()
 NSGraphicsContext.restoreGraphicsState()
 let bolt=NSBezierPath();bolt.move(to:NSPoint(x:643,y:685));bolt.line(to:NSPoint(x:444,y:397));bolt.line(to:NSPoint(x:580,y:397));bolt.line(to:NSPoint(x:527,y:184));bolt.line(to:NSPoint(x:795,y:493));bolt.line(to:NSPoint(x:644,y:493));bolt.close()
 NSColor(calibratedRed:1,green:0.78,blue:0.27,alpha:1).setFill();bolt.fill()
 image.unlockFocus()
 let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
 let data=rep.representation(using:.png,properties:[:])!
 try! data.write(to:URL(fileURLWithPath:dir+"/size_\(size).png"))
}
