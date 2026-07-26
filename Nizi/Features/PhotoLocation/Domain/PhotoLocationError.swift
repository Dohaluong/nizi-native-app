//
//  PhotoLocationError.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

enum PhotoLocationError: Error, Equatable {
    case invalidCoordinate
    case placeNotFound
    case geocodingFailed
}
