//
//  AlbumPhotoProviderError.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

enum AlbumPhotoProviderError: Error, Equatable, Sendable {
    case assetNotFound
    case requestFailed
    case cancelled
}
