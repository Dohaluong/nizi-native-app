//
//  HomeDesignPreview1A.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI
import SwiftData
import UIKit

/// TEMPORARY, UI-only design preview — recreates concept "1a — The Memory Surface" from
/// docs/design-system/Nizi Home Concepts.dc.html § 1 so it can be compared against the real app
/// on a device. All text/dates/counts are still static mock content and nothing here is tappable
/// — the only "real" data pulled in is a handful of actual photo thumbnails from one of the
/// user's own loved Events, so the placeholders read as real photos instead of gray boxes.
/// Reached only via the DEBUG Diagnostics hub (`PhotoLibraryDiagnosticsView`); delete this file
/// once the design decision is made.
struct HomeDesignPreview1A: View {
    private let ink = Color(previewHex: 0x0E0D10)
    private let cream = Color(previewHex: 0xF6F1EA)
    private let accent = Color(previewHex: 0xE1875B)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var images: [String: PlatformImage] = [:]

    /// Matches the design's own hero-to-frame proportion (700/874 in the 402×874 mock device) —
    /// scaled off the real screen height instead of a fixed point value, per "đúng tỷ lệ chiều
    /// cao như trong mẫu thiết kế".
    private var heroHeight: CGFloat {
        UIScreen.main.bounds.height * (700.0 / 874.0)
    }

    /// Must be an explicit value, never `nil` — `MemoryPhoto` passing `width: nil` here was the
    /// actual bug behind "giao diện đang bị lấy theo chiều rộng ảnh hero": with only `height`
    /// constrained, `.aspectRatio(contentMode: .fill)` computed the image's width from its own
    /// (real, often-landscape) aspect ratio × the fixed height instead of the screen width, and
    /// that oversized "ideal width" propagated up through the ZStack and stretched everything.
    private var heroWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    lovedMemoriesSection
                    recentSection
                    tripSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ink.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(selected: .home)
            }

            backButton
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadRealPhotos() }
    }

    /// No top bar/title, deliberately — just the one round back button the simpler mock frames
    /// (Events, Photobook Detail) use, per "Không làm top bar mà chỉ làm 1 nút back tròn".
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 54)
        .padding(.leading, 18)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            MemoryPhoto(image: images["hero"], width: heroWidth, height: heroHeight, cornerRadius: 0)

            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text("8 YEARS AGO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.75))
                Text("Summer in Da Nang")
                    .font(.onboardingSerif(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                HStack(alignment: .lastTextBaseline) {
                    Text("Mỹ An · Đà Nẵng — Jul 2018 · 24 of 156 photos")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
    }

    // MARK: - Loved Memories

    private var lovedMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("LOVED MEMORIES")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    lovedCard(slot: "loved1", place: "Hội An · 2021")
                    lovedCard(slot: "loved2", place: "Sapa · 2020")
                    lovedCard(slot: "loved3", place: "Đà Lạt · 2019")
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func lovedCard(slot: String, place: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            MemoryPhoto(image: images[slot], width: 132, height: 172, cornerRadius: 14)

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 65)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            Text(place)
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
                .padding(10)
        }
        .frame(width: 132, height: 172)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RECENT")

            HStack(spacing: 14) {
                MemoryPhoto(image: images["recent"], width: 110, height: 110, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Last weekend")
                        .font(.onboardingSerif(size: 19))
                        .foregroundStyle(cream)
                    Text("12–13 Jul · 42 photos")
                        .font(.system(size: 12))
                        .foregroundStyle(cream.opacity(0.5))
                    HStack(spacing: 14) {
                        Text("View")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                        Image(systemName: "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(cream.opacity(0.5))
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    // MARK: - Trip

    /// Fixed collage geometry (matches the design's `grid-template-columns:1.2fr 1fr` over a
    /// 200pt-tall, 2-row grid) — computed once from a fixed reference width rather than via
    /// `GeometryReader`, so every tile gets a fully explicit width *and* height and there is no
    /// ambient-size ambiguity anywhere in this section.
    private func tripCollage(availableWidth: CGFloat) -> some View {
        let spacing: CGFloat = 2
        let leftWidth = (availableWidth - spacing) * 1.2 / 2.2
        let rightWidth = availableWidth - spacing - leftWidth
        let rightTileHeight = (200 - spacing) / 2

        return ZStack(alignment: .bottomLeading) {
            HStack(spacing: spacing) {
                MemoryPhoto(image: images["trip1"], width: leftWidth, height: 200, cornerRadius: 0)
                VStack(spacing: spacing) {
                    MemoryPhoto(image: images["trip2"], width: rightWidth, height: rightTileHeight, cornerRadius: 0)
                    MemoryPhoto(image: images["trip3"], width: rightWidth, height: rightTileHeight, cornerRadius: 0)
                }
            }
            .frame(width: availableWidth, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .frame(width: availableWidth, height: 120)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("Japan")
                    .font(.onboardingSerif(size: 22))
                    .foregroundStyle(.white)
                Text("Tokyo · Kyoto · Osaka — 7 days")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 16)
            .padding(.bottom, 14)
        }
        .frame(width: availableWidth, height: 200)
    }

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("A TRIP WORTH REVISITING")

            GeometryReader { proxy in
                tripCollage(availableWidth: proxy.size.width)
            }
            .frame(height: 200)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Shared bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(cream.opacity(0.45))
            .padding(.horizontal, 24)
    }

    // MARK: - Pulling in real photos from one loved Event

    /// The 8 image slots this mock needs, in priority order, each mapped to a target thumbnail
    /// size roughly matching how big it's actually drawn. Reused cyclically if the chosen Event
    /// has fewer than 8 photos.
    private static let slots: [(key: String, size: CGSize)] = [
        ("hero", CGSize(width: 500, height: 500)),
        ("loved1", CGSize(width: 200, height: 260)),
        ("loved2", CGSize(width: 200, height: 260)),
        ("loved3", CGSize(width: 200, height: 260)),
        ("recent", CGSize(width: 220, height: 220)),
        ("trip1", CGSize(width: 260, height: 240)),
        ("trip2", CGSize(width: 220, height: 120)),
        ("trip3", CGSize(width: 220, height: 120))
    ]

    /// Prefers a real loved Event (`isLoved == true`) so the preview shows photos the user
    /// actually cares about; falls back to the single top-scored Event only if nothing is loved
    /// yet. No further logic beyond "pick one Event with photos to show".
    private func loadRealPhotos() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)

        var orderedAssetIDs: [String] = []
        if let lovedEvent = try? await store.fetchMemoryEvents().first {
            orderedAssetIDs = (lovedEvent.coverAssetID.map { [$0] } ?? []) + lovedEvent.assetIDs
        } else if let event = try? await store.fetchEvents(sortedBy: .scoreDescending).first {
            orderedAssetIDs = (event.coverAssetID.map { [$0] } ?? []) + event.assetIDs
        }

        var seen = Set<String>()
        let assetIDs = orderedAssetIDs.filter { seen.insert($0).inserted }
        guard !assetIDs.isEmpty else { return }

        for (index, slot) in Self.slots.enumerated() {
            let assetID = assetIDs[index % assetIDs.count]
            guard let image = try? await assetProvider.requestThumbnail(
                assetID: assetID, targetSize: slot.size,
                networkAccessAllowed: false, deliveryMode: .fast, contentMode: .fill
            ) else { continue }
            images[slot.key] = image
        }
    }
}

/// Shows a real loaded photo when available; otherwise falls back to a muted "photo goes here"
/// gradient so the layout still reads correctly before/without library data. `width`/`height` are
/// always applied directly here — never left to be inferred from an ambient/parent proposal —
/// specifically because a real `UIImage`'s large native pixel size combined with
/// `.aspectRatio(contentMode: .fill)` and no explicit bound is what was blowing out the rest of
/// the layout (rows overflowing, the trip collage's math going wrong, etc.) once real photos
/// replaced the flexible placeholder `Rectangle`.
private struct MemoryPhoto: View {
    let image: PlatformImage?
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
            } else {
                LinearGradient(
                    colors: [Color(previewHex: 0x2A2830), Color(previewHex: 0x1A181C)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.18))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// The same fixed bottom tab bar as concept "4a — Events" (docs/design-system/Nizi Home
/// Concepts.dc.html § t4): Home / Events / Trips, translucent blurred background, only the
/// active tab's icon+label go full cream/semibold — reused here with Home active. Not
/// interactive (no tab switching) — this preview only ever shows the Home screen.
private struct BottomTabBar: View {
    enum Tab { case home, events, trips }

    let selected: Tab

    var body: some View {
        HStack(spacing: 64) {
            tab(.home, systemImage: "house", label: "Home")
            tab(.events, systemImage: "calendar", label: "Events")
            tab(.trips, systemImage: "safari", label: "Trips")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 16)
        .padding(.bottom, 0)
        .background {
            ZStack(alignment: .top) {
                Color(previewHex: 0x141316).opacity(0.85)
                Color.white.opacity(0.08).frame(height: 1)
            }
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(_ tab: Tab, systemImage: String, label: String) -> some View {
        let isActive = tab == selected
        let tint = isActive ? Color(previewHex: 0xF6F1EA) : Color(previewHex: 0xF6F1EA).opacity(0.4)
        return VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
            Text(label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
        }
        .foregroundStyle(tint)
    }
}

private extension Color {
    /// Local, throwaway hex parser — this file is temporary and shouldn't take on a shared
    /// dependency for it.
    init(previewHex hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    NavigationStack {
        HomeDesignPreview1A()
    }
}
