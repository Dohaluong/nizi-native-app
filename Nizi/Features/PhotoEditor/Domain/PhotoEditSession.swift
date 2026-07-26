//
//  PhotoEditSession.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// One editing session's state — created when Photo Editor opens, discarded when it closes.
/// Every mutation the UI makes (preset pick, slider drag, Auto Enhance, reset) touches
/// `workingRecipe` only; `originalRecipe` is never mutated, so Cancel is always just "throw this
/// whole struct away" (PHOTO-EDITOR.md § 16).
struct PhotoEditSession: Equatable {
    /// The recipe as it was when the editor opened — `nil` if this photo had never been edited
    /// before. Never mutated for the lifetime of the session.
    let originalRecipe: PhotoEditRecipe?
    var workingRecipe: PhotoEditRecipe

    init(photoId: String, existingRecipe: PhotoEditRecipe?, now: Date = Date()) {
        originalRecipe = existingRecipe
        workingRecipe = existingRecipe ?? .original(photoId: photoId, now: now)
    }

    /// Compares content only (never timestamps) against whatever baseline the session opened
    /// with — an untouched, never-before-edited photo has `originalRecipe == nil`, so the
    /// baseline in that case is a fresh Original recipe, not "everything is unsaved by default."
    var hasUnsavedChanges: Bool {
        let baseline = originalRecipe ?? .original(photoId: workingRecipe.photoId, now: workingRecipe.createdAt)
        return !workingRecipe.hasSameContent(as: baseline)
    }

    /// § 16.2 — returns `workingRecipe` to Original, keeping the same `photoId`/`createdAt`.
    /// Does not touch `originalRecipe` and does not save; a subsequent Cancel would still restore
    /// whatever the photo had before this session opened.
    mutating func resetToOriginal(now: Date = Date()) {
        workingRecipe = .original(photoId: workingRecipe.photoId, now: now)
    }
}
