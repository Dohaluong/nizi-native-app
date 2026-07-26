//
//  CubeFileParser.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Parses the text of a `.cube` 3D LUT file (the standard Adobe/DaVinci format) into the RGBA
/// `Float32` buffer `CIColorCubeWithColorSpace` expects. Kept as its own pure function (no
/// `Bundle`, no caching) so it's directly unit-testable against small synthetic `.cube` text —
/// `CubeLUTLoader` is the only thing that touches the file system and the parse cache.
enum CubeFileParser {
    /// - Parameter expectedDimension: The `lutDimension` the calling `PresetDefinition` declares.
    ///   Mismatched against the file's own `LUT_3D_SIZE` line — a preset that claims dimension 33
    ///   but ships a 17-point cube is a data error, not something to silently coerce.
    static func parse(text: String, expectedDimension: Int) throws -> Data {
        var declaredDimension: Int?
        var triples: [(Float, Float, Float)] = []
        triples.reserveCapacity(expectedDimension * expectedDimension * expectedDimension)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(separator: " ")
                guard parts.count >= 2, let size = Int(parts[1]) else {
                    throw LUTLoadingError.invalidFormat
                }
                declaredDimension = size
                continue
            }

            // Any other metadata line (TITLE, DOMAIN_MIN, DOMAIN_MAX, LUT_1D_SIZE, ...) is
            // skipped rather than rejected — this parser only needs the size + the data rows, not
            // every optional header a `.cube` file may carry. Critically, a line like
            // `DOMAIN_MIN 0.0 0.0 0.0` must be rejected as non-data *before* parsing floats — a
            // few real presets ship this line, and its label happens to fail `Float(_:)`, so a
            // naive `.compactMap { Float($0) }` over all tokens silently drops just the label and
            // is left with exactly 3 floats, misreading it as a genuine data row. Requiring
            // exactly 3 *tokens* up front (not 3 *parseable* tokens after the fact) is what
            // actually distinguishes the two.
            let rawComponents = line.split(separator: " ")
            guard rawComponents.count == 3 else { continue }
            let components = rawComponents.compactMap { Float($0) }
            guard components.count == 3 else { continue }
            triples.append((components[0], components[1], components[2]))
        }

        guard let declaredDimension, declaredDimension == expectedDimension else {
            throw LUTLoadingError.dimensionMismatch
        }
        let expectedCount = expectedDimension * expectedDimension * expectedDimension
        guard triples.count == expectedCount else {
            throw LUTLoadingError.invalidFormat
        }

        // `.cube`'s row ordering (red fastest, blue slowest) is already the exact order
        // `CIColorCubeWithColorSpace` wants — each RGB triple just gets an alpha of 1.0 appended.
        var buffer = [Float]()
        buffer.reserveCapacity(expectedCount * 4)
        for (r, g, b) in triples {
            buffer.append(r)
            buffer.append(g)
            buffer.append(b)
            buffer.append(1.0)
        }
        return buffer.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
