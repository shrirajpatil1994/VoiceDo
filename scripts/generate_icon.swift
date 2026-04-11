#!/usr/bin/swift
// Generates AppIcon-1024.png for VoiceDo.
// Run: swift scripts/generate_icon.swift
// from the VoiceDo project root.

import AppKit
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let outputPath = "VoiceDo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

// Colors
let background = NSColor(red: 0.969, green: 0.957, blue: 0.937, alpha: 1) // cream
let ink = NSColor(white: 0.08, alpha: 1)                                   // near-black

// Create image
let image = NSImage(size: size)
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("No graphics context")
    exit(1)
}

// Background (cream, rounded square via clipping)
let cornerRadius: CGFloat = 220
let bgRect = CGRect(origin: .zero, size: size)
let clipPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(clipPath)
ctx.clip()

ctx.setFillColor(background.cgColor)
ctx.fill(bgRect)

// V shape — two lines from top-left/top-right converging at bottom-center
let vTop: CGFloat = 280
let vBottom: CGFloat = 620
let vLeft: CGFloat = 280
let vRight: CGFloat = 744
let vMid: CGFloat = 512

ctx.setStrokeColor(ink.cgColor)
ctx.setLineWidth(62)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let vPath = CGMutablePath()
vPath.move(to: CGPoint(x: vLeft, y: vTop))
vPath.addLine(to: CGPoint(x: vMid, y: vBottom))
vPath.addLine(to: CGPoint(x: vRight, y: vTop))
ctx.addPath(vPath)
ctx.strokePath()

// Mic capsule below the V point
let micWidth: CGFloat = 72
let micHeight: CGFloat = 120
let micX = vMid - micWidth / 2
let micY = vBottom - 10
let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
let micPath = CGPath(
    roundedRect: micRect,
    cornerWidth: micWidth / 2,
    cornerHeight: micWidth / 2,
    transform: nil
)
ctx.setFillColor(ink.cgColor)
ctx.addPath(micPath)
ctx.fillPath()

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? png.write(to: url)
print("Icon written to \(outputPath)")
