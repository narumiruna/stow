#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func makeIcon(size: Int, name: String) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let colors = [CGColor(red: 0.12, green: 0.34, blue: 0.96, alpha: 1), CGColor(red: 0.32, green: 0.16, blue: 0.76, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    let inset = CGFloat(size) * 0.20
    let box = CGRect(x: inset, y: inset * 0.82, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 1.9)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
    context.setLineWidth(CGFloat(size) * 0.055)
    context.setLineJoin(.round)
    context.stroke(box.insetBy(dx: CGFloat(size) * 0.025, dy: CGFloat(size) * 0.025))
    context.move(to: CGPoint(x: box.minX, y: box.maxY - box.height * 0.30))
    context.addLine(to: CGPoint(x: box.midX, y: box.maxY - box.height * 0.48))
    context.addLine(to: CGPoint(x: box.maxX, y: box.maxY - box.height * 0.30))
    context.strokePath()
    context.move(to: CGPoint(x: box.midX, y: box.maxY - box.height * 0.48))
    context.addLine(to: CGPoint(x: box.midX, y: box.minY))
    context.strokePath()

    guard let image = context.makeImage() else { return }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: output.appendingPathComponent(name), options: .atomic)
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes { try makeIcon(size: size, name: "AppIcon-\(size).png") }
