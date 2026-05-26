#!/usr/bin/env swift
// oklch-to-srgb: parse coss-tokens.css :root {} tokens, convert oklch() to sRGB, emit JSON.
// Usage: ./tools/oklch-to-srgb.swift <input.css> <output.json>
// Pipeline: oklch -> oklab -> linear sRGB (D65) -> clamp -> sRGB gamma.

import Foundation

struct RGBA: Encodable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double
}

enum ScriptError: Error, CustomStringConvertible {
    case unreadableRootBlock
    case invalidDeclaration(String)

    var description: String {
        switch self {
        case .unreadableRootBlock:
            return "could not find a complete :root { ... } block"
        case let .invalidDeclaration(name):
            return "invalid oklch() declaration for token \(name)"
        }
    }
}

func oklchToOklab(lightness: Double, chroma: Double, hue: Double) -> (l: Double, a: Double, b: Double) {
    let radians = hue * .pi / 180.0
    return (lightness, chroma * cos(radians), chroma * sin(radians))
}

func oklabToLinearSRGB(l: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
    let lPrime = l + 0.3963377774 * a + 0.2158037573 * b
    let mPrime = l - 0.1055613458 * a - 0.0638541728 * b
    let sPrime = l - 0.0894841775 * a - 1.2914855480 * b

    let lCubed = lPrime * lPrime * lPrime
    let mCubed = mPrime * mPrime * mPrime
    let sCubed = sPrime * sPrime * sPrime

    return (
        +4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed,
        -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed,
        -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed
    )
}

func clamp(_ value: Double) -> Double {
    min(1.0, max(0.0, value))
}

func linearToSRGBGamma(_ value: Double) -> Double {
    let clamped = clamp(value)
    if clamped <= 0.0031308 {
        return 12.92 * clamped
    }
    return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
}

func convert(lightness: Double, chroma: Double, hue: Double, alpha: Double) -> RGBA {
    let lab = oklchToOklab(lightness: lightness / 100.0, chroma: chroma, hue: hue)
    let linear = oklabToLinearSRGB(l: lab.l, a: lab.a, b: lab.b)
    return RGBA(
        r: linearToSRGBGamma(linear.r),
        g: linearToSRGBGamma(linear.g),
        b: linearToSRGBGamma(linear.b),
        a: clamp(alpha)
    )
}

func rootBlock(in css: String) throws -> String {
    guard let rootRange = css.range(of: ":root"),
          let openingBrace = css[rootRange.upperBound...].firstIndex(of: "{")
    else {
        throw ScriptError.unreadableRootBlock
    }

    var depth = 0
    var index = openingBrace
    while index < css.endIndex {
        let character = css[index]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(css[css.index(after: openingBrace)..<index])
            }
        }
        index = css.index(after: index)
    }

    throw ScriptError.unreadableRootBlock
}

func firstMatchGroups(pattern: String, in input: String) throws -> [String]? {
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(input.startIndex..., in: input)
    guard let match = regex.firstMatch(in: input, range: range) else {
        return nil
    }

    return (1..<match.numberOfRanges).map { groupIndex in
        let groupRange = match.range(at: groupIndex)
        guard groupRange.location != NSNotFound,
              let range = Range(groupRange, in: input)
        else {
            return ""
        }
        return String(input[range])
    }
}

func removingComments(from input: String) throws -> String {
    let regex = try NSRegularExpression(pattern: #"/\*.*?\*/"#, options: [.dotMatchesLineSeparators])
    let range = NSRange(input.startIndex..., in: input)
    return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "")
}

func convertTokens(from css: String) throws -> [String: RGBA] {
    let declarationPattern = #"(?m)--([A-Za-z0-9_-]+)\s*:\s*([^;]+);"#
    let oklchPattern = #"^\s*oklch\(\s*([0-9]*\.?[0-9]+)%?\s+([0-9]*\.?[0-9]+)\s+([0-9]*\.?[0-9]+)(?:\s*/\s*([0-9]*\.?[0-9]+))?\s*\)\s*$"#

    let block = try rootBlock(in: css)
    let declarationRegex = try NSRegularExpression(pattern: declarationPattern)
    let blockRange = NSRange(block.startIndex..., in: block)
    var result: [String: RGBA] = [:]

    declarationRegex.enumerateMatches(in: block, range: blockRange) { match, _, _ in
        guard let match,
              let nameRange = Range(match.range(at: 1), in: block),
              let valueRange = Range(match.range(at: 2), in: block)
        else {
            return
        }

        let name = String(block[nameRange])
        guard let value = try? removingComments(from: String(block[valueRange])) else {
            return
        }

        guard let groups = try? firstMatchGroups(pattern: oklchPattern, in: value) else {
            return
        }

        guard groups.count == 4,
              let lightness = Double(groups[0]),
              let chroma = Double(groups[1]),
              let hue = Double(groups[2])
        else {
            return
        }

        let alpha = Double(groups[3]) ?? 1.0
        result[name] = convert(lightness: lightness, chroma: chroma, hue: hue, alpha: alpha)
    }

    return result
}

func main() throws {
    guard CommandLine.arguments.count == 3 else {
        print("usage: ./tools/oklch-to-srgb.swift <input.css> <output.json>")
        exit(2)
    }

    let inputPath = CommandLine.arguments[1]
    let outputPath = CommandLine.arguments[2]
    let css = try String(contentsOfFile: inputPath, encoding: .utf8)
    let tokens = try convertTokens(from: css)
    let data = try JSONEncoder.sortedPrettyEncoder.encode(tokens)
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    print("converted \(tokens.count) tokens -> \(outputPath)")
}

extension JSONEncoder {
    static var sortedPrettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

do {
    try main()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
