//
//  CubeFileParserTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct CubeFileParserTests {
    private let validCubeText = """
    # A tiny synthetic 2x2x2 LUT — comment lines and metadata should be skipped.
    TITLE "Test LUT"
    LUT_3D_SIZE 2
    0.0 0.0 0.0
    0.1 0.1 0.1
    0.2 0.2 0.2
    0.3 0.3 0.3
    0.4 0.4 0.4
    0.5 0.5 0.5
    0.6 0.6 0.6
    0.7 0.7 0.7
    """

    private func floats(from data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    @Test
    func parsesEveryRowWithAlphaAppended() throws {
        let data = try CubeFileParser.parse(text: validCubeText, expectedDimension: 2)
        let values = floats(from: data)

        #expect(values.count == 2 * 2 * 2 * 4)
        // First row: (0, 0, 0, 1); second row: (0.1, 0.1, 0.1, 1); ...
        #expect(values[0...3].elementsEqual([0, 0, 0, 1]))
        #expect(values[4...7].elementsEqual([0.1, 0.1, 0.1, 1]))
        #expect(values[28...31].elementsEqual([0.7, 0.7, 0.7, 1]))
    }

    @Test
    func skipsCommentAndMetadataLines() throws {
        // Already exercised by `validCubeText` itself (it has a `#` comment and a `TITLE` line)
        // — this just asserts that having them present doesn't change the row count.
        let data = try CubeFileParser.parse(text: validCubeText, expectedDimension: 2)
        #expect(floats(from: data).count == 32)
    }

    @Test
    func dimensionMismatchThrows() {
        #expect(throws: LUTLoadingError.dimensionMismatch) {
            try CubeFileParser.parse(text: validCubeText, expectedDimension: 3)
        }
    }

    @Test
    func missingLUT3DSizeLineThrows() {
        let text = "0.0 0.0 0.0\n0.1 0.1 0.1"
        #expect(throws: LUTLoadingError.dimensionMismatch) {
            try CubeFileParser.parse(text: text, expectedDimension: 2)
        }
    }

    @Test
    func tooFewDataRowsThrowsInvalidFormat() {
        let text = "LUT_3D_SIZE 2\n0.0 0.0 0.0\n0.1 0.1 0.1"
        #expect(throws: LUTLoadingError.invalidFormat) {
            try CubeFileParser.parse(text: text, expectedDimension: 2)
        }
    }
}
