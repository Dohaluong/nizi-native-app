//
//  NewsreaderFontRegistrar.swift
//  Nizi
//

import CoreText
import Foundation

/// Generated Info.plist registration can be sensitive to how a filesystem-synchronised resource
/// folder is copied into an app bundle. Registering from the resolved bundle URL makes Newsreader
/// available on device regardless of whether Xcode flattens `Resources/Fonts` into the bundle
/// root or preserves that directory.
enum NewsreaderFontRegistrar {
    private static let fontFiles = [
        "Newsreader-VariableFont_opsz,wght.ttf",
        "Newsreader-Italic-VariableFont_opsz,wght.ttf"
    ]

    static func registerBundledFonts() {
        for fileName in fontFiles {
            let resourceName = fileName.replacingOccurrences(of: ".ttf", with: "")
            let url = Bundle.main.url(forResource: resourceName, withExtension: "ttf")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "ttf", subdirectory: "Resources/Fonts")
            guard let url else { continue }

            var error: Unmanaged<CFError>?
            // `false` merely means the font was already registered via UIAppFonts, which is a
            // successful end state too, so no error/reporting is needed here.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
