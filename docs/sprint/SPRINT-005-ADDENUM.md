# Product Navigation Principle

Memory Discovery is not the main application home.

The main Home screen displays the timeline of albums already created.

Memory Discovery is a secondary workflow used to discover photo groups and convert them into future albums.

## First Launch Flow

1. Show “Hello Nizi”.
2. Explain why Nizi needs to inspect the photo library:
   - to find trips;
   - to find events;
   - to suggest groups of photos that may become albums.
3. Allow the user to choose:
   - the full photo library; or
   - a specific year/month range.
4. Request Photo Library permission.
5. Scan only the permitted and selected scope.
6. Show scan progress.
7. On completion, navigate to the main Home screen.

## Main Home

The Home screen displays the album timeline.

This timeline should reuse the product structure and UX already implemented in the Nizi webapp, rewritten natively in SwiftUI.

Home also contains one entry point:

“Các sự kiện / chuyến đi”

This entry point opens Memory Discovery.

## Memory Discovery

The Memory Discovery screen displays EventCandidates generated from the local index.

Candidates are not albums.

Candidates are suggestions that may later be converted into AlbumDrafts.

## Candidate Flow

Home
→ Các sự kiện / chuyến đi
→ Candidate List
→ Candidate Detail
→ AlbumDraft flow in Sprint 006

## Important Constraints

- Do not make Candidate List the main Home.
- Do not navigate directly from scan completion to Candidate List.
- Do not treat EventCandidate as an Album.
- Do not implement upload in Sprint 005.
- Do not redesign the album timeline independently from the existing webapp.