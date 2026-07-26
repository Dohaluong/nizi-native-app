//
//  PhotoEditSessionTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PhotoEditSessionTests {
    @Test
    func newPhotoWithNoRecipeHasNoUnsavedChanges() {
        let session = PhotoEditSession(photoId: "p1", existingRecipe: nil)
        #expect(!session.hasUnsavedChanges)
        #expect(session.originalRecipe == nil)
        #expect(session.workingRecipe.isUnedited)
    }

    @Test
    func mutatingWorkingRecipeMarksUnsavedChanges() {
        var session = PhotoEditSession(photoId: "p1", existingRecipe: nil)
        session.workingRecipe.presetId = "warm-memory"
        session.workingRecipe.presetIntensity = 0.5
        #expect(session.hasUnsavedChanges)
    }

    @Test
    func reopeningOnAlreadySavedRecipeHasNoUnsavedChanges() {
        var saved = PhotoEditRecipe.original(photoId: "p1")
        saved.presetId = "warm-memory"
        saved.presetIntensity = 0.65

        let session = PhotoEditSession(photoId: "p1", existingRecipe: saved)
        #expect(!session.hasUnsavedChanges)
        #expect(session.workingRecipe.presetId == "warm-memory")
    }

    @Test
    func editingAnAlreadySavedRecipeMarksUnsavedChanges() {
        var saved = PhotoEditRecipe.original(photoId: "p1")
        saved.presetId = "warm-memory"
        saved.presetIntensity = 0.65

        var session = PhotoEditSession(photoId: "p1", existingRecipe: saved)
        session.workingRecipe.presetIntensity = 0.9
        #expect(session.hasUnsavedChanges)
    }

    @Test
    func resetToOriginalClearsWorkingRecipeButKeepsOriginalRecipe() {
        var saved = PhotoEditRecipe.original(photoId: "p1")
        saved.presetId = "warm-memory"
        saved.presetIntensity = 0.65

        var session = PhotoEditSession(photoId: "p1", existingRecipe: saved)
        session.resetToOriginal()

        #expect(session.workingRecipe.isUnedited)
        #expect(session.originalRecipe == saved) // Cancel would still restore the saved recipe
        #expect(session.hasUnsavedChanges) // reset-to-original away from a saved style is itself a pending change
    }
}
