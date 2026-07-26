//
//  AlbumPageFormat.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// The aspect-ratio family a page is rendered at. See docs/ALBUM_LAYOUT_SYSTEM.md § Page format.
/// This sprint's sample layout library only ships `square` layouts, but the model and renderer
/// support all three so `portrait`/`landscape` layouts can be added later without a model change.
enum AlbumPageFormat: String, Codable, CaseIterable, Hashable {
    case square
    case portrait
    case landscape

    /// Reference canvas size used when authoring layouts for this format.
    var referenceSize: AlbumReferenceCanvas {
        switch self {
        case .square: AlbumReferenceCanvas(width: 1000, height: 1000)
        case .portrait: AlbumReferenceCanvas(width: 1000, height: 1400)
        case .landscape: AlbumReferenceCanvas(width: 1400, height: 1000)
        }
    }
}

/// The canvas a layout's slot coordinates are authored against — resolution-independent by
/// design (see docs/ALBUM_LAYOUT_SYSTEM.md § Coordinate system). Renderers scale from this to
/// whatever size they're actually given.
struct AlbumReferenceCanvas: Codable, Hashable {
    let width: Double
    let height: Double
}
