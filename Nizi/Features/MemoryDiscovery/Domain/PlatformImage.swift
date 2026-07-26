//
//  PlatformImage.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import UIKit

/// Platform-neutral name for the image type Infrastructure hands back to Domain/Application.
/// Currently just `UIImage` since Nizi only ships on iOS — see docs/modules/memory-discovery/ARCHITECTURE.md § 6.2.
typealias PlatformImage = UIImage
