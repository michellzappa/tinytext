#!/usr/bin/swift

// generate-icon.swift
// Generates an AppIcon.icon for any Tiny* app.
//
// Usage: swift scripts/generate-icon.swift <GLYPH> <ACCENT_HEX> [output_dir]
//   GLYPH:      SF Symbol name (e.g. "checkmark") or path to .svg/.png file
//   ACCENT_HEX: Hex color, e.g. "#A855F7" (purple)
//   output_dir:  Optional, defaults to ./AppIcon.icon
//
// Examples:
//   swift scripts/generate-icon.swift checkmark "#A855F7"
//   swift scripts/generate-icon.swift scripts/symbol.svg "#6B8DD6"

import AppKit
import CoreGraphics

// MARK: - Color helpers

func hexToComponents(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return (
        r: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        g: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        b: CGFloat(rgb & 0xFF) / 255.0
    )
}

func srgbString(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,%.5f", r, g, b, a)
}

// MARK: - Generate circle PNG

func generateCirclePNG(accentHex: String, size: Int, outputPath: String) {
    let (r, g, b) = hexToComponents(accentHex)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { print("Failed to create CGContext"); exit(1) }

    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Clip to circle
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.addEllipse(in: rect)
    ctx.clip()

    // Gradient: very dark accent (top) → dark accent (bottom)
    // In CGContext, y=0 is bottom, so startPoint is bottom, endPoint is top
    let colors = [
        CGColor(colorSpace: colorSpace, components: [r * 0.2, g * 0.2, b * 0.2, 1.0])!,
        CGColor(colorSpace: colorSpace, components: [r * 0.35, g * 0.35, b * 0.35, 1.0])!,
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size)),  // top (flipped)
        end: CGPoint(x: CGFloat(size) / 2, y: 0),                // bottom (flipped)
        options: []
    )

    guard let image = ctx.makeImage() else { print("Failed to create image"); exit(1) }
    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed to create image destination"); exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Generate symbol PNG

func generateSymbolPNG(symbolName: String, size: Int, outputPath: String) {
    let cgSize = CGSize(width: size, height: size)

    guard let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        print("SF Symbol '\(symbolName)' not found")
        exit(1)
    }

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.45, weight: .medium)
    let configured = symbolImage.withSymbolConfiguration(config)!

    let finalImage = NSImage(size: cgSize, flipped: false) { rect in
        let symbolSize = configured.size
        let x = (rect.width - symbolSize.width) / 2
        let y = (rect.height - symbolSize.height) / 2
        let symbolRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)

        // Draw the symbol (renders as template/black)
        configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // Tint it white using sourceAtop compositing
        NSColor.white.setFill()
        symbolRect.fill(using: .sourceAtop)
        return true
    }

    // Render to PNG
    guard let tiffData = finalImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render symbol to PNG"); exit(1)
    }
    try! pngData.write(to: URL(fileURLWithPath: outputPath))
}

// MARK: - Copy/convert custom symbol file (SVG or PNG)

func copyCustomSymbolPNG(filePath: String, size: Int, outputPath: String) {
    let url = URL(fileURLWithPath: filePath)
    let ext = url.pathExtension.lowercased()

    let sourceImage: NSImage
    if ext == "svg" {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            print("Failed to load SVG from '\(filePath)'"); exit(1)
        }
        sourceImage = image
    } else {
        guard let image = NSImage(contentsOfFile: filePath) else {
            print("Failed to load image from '\(filePath)'"); exit(1)
        }
        sourceImage = image
    }

    // Re-render at target size, centered
    let cgSize = CGSize(width: size, height: size)
    let finalImage = NSImage(size: cgSize, flipped: false) { rect in
        let srcSize = sourceImage.size
        let scale = min(rect.width * 0.49 / srcSize.width, rect.height * 0.49 / srcSize.height)
        let w = srcSize.width * scale
        let h = srcSize.height * scale
        let x = (rect.width - w) / 2
        let y = (rect.height - h) / 2
        sourceImage.draw(in: NSRect(x: x, y: y, width: w, height: h),
                        from: .zero, operation: .sourceOver, fraction: 1.0)
        return true
    }

    guard let tiffData = finalImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render custom symbol to PNG"); exit(1)
    }
    try! pngData.write(to: URL(fileURLWithPath: outputPath))
}

// MARK: - Generate icon.json

func generateIconJSON(accentHex: String) -> String {
    let (r, g, b) = hexToComponents(accentHex)
    let accentColor = srgbString(r, g, b)
    let darkerAccent = srgbString(r * 0.7, g * 0.7, b * 0.7)

    return """
    {
      "fill" : {
        "linear-gradient" : [
          "\(accentColor)",
          "\(darkerAccent)"
        ],
        "orientation" : {
          "start" : {
            "x" : 0.5,
            "y" : 0
          },
          "stop" : {
            "x" : 0.5,
            "y" : 1
          }
        }
      },
      "groups" : [
        {
          "layers" : [
            {
              "glass" : false,
              "image-name" : "symbol.png",
              "name" : "symbol",
              "position" : {
                "scale" : 2,
                "translation-in-points" : [
                  0,
                  0
                ]
              }
            },
            {
              "glass" : true,
              "image-name" : "circle.png",
              "name" : "circle",
              "position" : {
                "scale" : 2.2,
                "translation-in-points" : [
                  0,
                  0
                ]
              }
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.5
          },
          "translucency" : {
            "enabled" : true,
            "value" : 0.5
          }
        }
      ],
      "supported-platforms" : {
        "circles" : [
          "watchOS"
        ],
        "squares" : "shared"
      }
    }
    """
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: swift \(args[0]) <GLYPH> <ACCENT_HEX> [output_dir]")
    print("  GLYPH: SF Symbol name or path to .svg/.png file")
    print("Example: swift \(args[0]) checkmark \"#A855F7\"")
    exit(1)
}

let glyph = args[1]
let accentHex = args[2]
let outputDir = args.count > 3 ? args[3] : "AppIcon.icon"

// Create directory structure
let assetsDir = "\(outputDir)/Assets"
let fm = FileManager.default
try? fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// Generate circle PNG
let imageSize = 355
let circlePath = "\(assetsDir)/circle.png"
generateCirclePNG(accentHex: accentHex, size: imageSize, outputPath: circlePath)
print("Generated \(circlePath)")

// Generate symbol PNG — detect if glyph is a file path or SF Symbol name
let symbolPath = "\(assetsDir)/symbol.png"
let isFilePath = glyph.contains("/") || glyph.contains(".svg") || glyph.contains(".png")
if isFilePath {
    copyCustomSymbolPNG(filePath: glyph, size: imageSize, outputPath: symbolPath)
} else {
    generateSymbolPNG(symbolName: glyph, size: imageSize, outputPath: symbolPath)
}
print("Generated \(symbolPath)")

// Generate icon.json
let jsonPath = "\(outputDir)/icon.json"
let json = generateIconJSON(accentHex: accentHex)
try! json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
print("Generated \(jsonPath)")

print("Done! AppIcon.icon ready at \(outputDir)/")
