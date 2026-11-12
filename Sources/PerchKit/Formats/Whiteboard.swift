import Foundation

public enum WhiteboardError: Error, Equatable {
    case missingPayload
    case unsupportedPayload
    case invalidScene
}

/// Reads Excalidraw scenes from `*.excalidraw` and `*.excalidraw.svg` files.
/// Perch only ever writes these from Excalidraw's own export, so saved files stay compatible.
public enum WhiteboardCodec {
    public static func sceneJSON(fromFileNamed name: String, text: String) throws -> Data {
        if name.lowercased().hasSuffix(".svg") { return try sceneJSON(fromSVG: text) }
        return try validated(Data(text.utf8))
    }

    public static func sceneJSON(fromSVG svg: String) throws -> Data {
        guard
            let start = svg.range(of: "<!-- payload-start -->"),
            let end = svg.range(of: "<!-- payload-end -->", range: start.upperBound..<svg.endIndex)
        else { throw WhiteboardError.missingPayload }

        let base64 = svg[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let raw = Data(base64Encoded: String(base64)) else { throw WhiteboardError.unsupportedPayload }
        // The outer JSON is latin-1 encoded, so each byte maps to one code point.
        var outerScalars = String.UnicodeScalarView()
        for byte in raw { outerScalars.append(Unicode.Scalar(byte)) }
        let outerText = String(outerScalars)
        guard
            let outerData = outerText.data(using: .utf8),
            let outer = try? JSONSerialization.jsonObject(with: outerData) as? [String: Any]
        else {
            return try validated(raw)
        }
        guard let encoded = outer["encoded"] as? String else {
            // Older files hold the scene directly.
            return try validated(outerData)
        }
        let bytes = Data(encoded.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        if (outer["compressed"] as? Bool) == true {
            guard bytes.count > 2 else { throw WhiteboardError.unsupportedPayload }
            // NSData's .zlib is raw deflate, so drop the 2-byte zlib header.
            guard let inflated = try? (bytes.dropFirst(2) as NSData).decompressed(using: .zlib) as Data else {
                throw WhiteboardError.unsupportedPayload
            }
            return try validated(inflated)
        }
        return try validated(bytes)
    }

    public static func elementCount(sceneJSON: Data) -> Int {
        guard let scene = try? JSONSerialization.jsonObject(with: sceneJSON) as? [String: Any],
              let elements = scene["elements"] as? [Any] else { return 0 }
        return elements.count
    }

    private static func validated(_ data: Data) throws -> Data {
        guard let scene = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              scene["elements"] is [Any] else { throw WhiteboardError.invalidScene }
        return data
    }
}
