// Assembles slide PNGs into a PDF, one 16:9 page per image (1600×900 pt).
//   swift tool/slides_pdf.swift out.pdf 01_title.png 02_…png …
import AppKit

let args = CommandLine.arguments
guard args.count > 2 else {
  print("usage: slides_pdf.swift out.pdf images…")
  exit(64)
}
var page = CGRect(x: 0, y: 0, width: 1600, height: 900)
let info: [CFString: Any] = [
  kCGPDFContextTitle: "Inside Flutter's Text Pipeline",
  kCGPDFContextCreator: "text_slides",
]
guard let ctx = CGContext(URL(fileURLWithPath: args[1]) as CFURL, mediaBox: &page, info as CFDictionary) else {
  print("cannot create \(args[1])")
  exit(1)
}
for path in args[2...] {
  guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("skip (unreadable): \(path)")
    continue
  }
  ctx.beginPDFPage(nil)
  ctx.interpolationQuality = .high
  ctx.draw(image, in: page)
  ctx.endPDFPage()
}
ctx.closePDF()
print("\(args[1])  (\(args.count - 2) pages)")
