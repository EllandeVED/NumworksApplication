// Generates background.jpg from Epsilon's background-with-shadow.webp.
// Replicates upstream's ImageMagick rule (convert -crop 1005x1975+93+13)
// using ImageIO so ImageMagick is not required on the build machine.
// Usage: swift generate-background-asset.swift <input.webp> <output.jpg>

import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-background-asset.swift <input.webp> <output.jpg>\n".utf8))
    exit(1)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("error: cannot decode \(inputURL.path)\n".utf8))
    exit(1)
}

// Same crop rectangle as upstream: -crop 1005x1975+93+13
guard let cropped = image.cropping(to: CGRect(x: 93, y: 13, width: 1005, height: 1975)) else {
    FileHandle.standardError.write(Data("error: crop failed\n".utf8))
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("error: cannot create \(outputURL.path)\n".utf8))
    exit(1)
}
let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
CGImageDestinationAddImage(destination, cropped, options)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: write failed\n".utf8))
    exit(1)
}
