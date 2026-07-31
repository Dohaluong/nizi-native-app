import SwiftUI

// MARK: - Preview Model

/// `imageName` is an SF Symbol name, rendered as a placeholder in `AlbumDesignCard.coverImage`
/// only when `coverPhoto` is nil (design-preview usage — production callers pass a real
/// `AlbumPhotoReference` and the SF Symbol is never shown).
struct AlbumCardSample {
    let title: String
    let subtitle: String
    let photoCount: Int
    let dateRange: String
    let imageName: String
    let year: Int
    var coverPhoto: AlbumPhotoReference? = nil
}

// MARK: - Main Preview Screen

struct AlbumCardDesignPreview: View {

    @State private var selectedYear: Int? = nil
    @State private var isSearchPresented = false

    private let availableYears: [Int] = [
        2026,
        2025,
        2024,
        2023,
        2022,
        2021,
        2020,
        2019,
        2018
    ]

    private let album = AlbumCardSample(
        title: "Summer in Sydney",
        subtitle: "A week by the harbour",
        photoCount: 36,
        dateRange: "14–21 Jan 2026",
        imageName: "photo.on.rectangle.angled",
        year: 2026
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                albumHeader

                AlbumDesignCard(album: album)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isSearchPresented) {
            AlbumSearchPreview()
        }
    }

    // MARK: Header

    private var albumHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleSection
            yearFilter
        }
    }

    private var titleSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Albums")
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text("Your stories, beautifully collected.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search albums")
        }
        .padding(.horizontal, 20)
    }

    // MARK: Year Filter

    private var yearFilter: some View {
        YearFilterBar(years: availableYears, selectedYear: $selectedYear)
            .padding(.horizontal, 20)
    }
}

// MARK: - Year Filter Bar

/// Fixed-width pill: the capsule background is sized to the *bar's own frame* (the width its
/// parent proposes), not to the total width of its year buttons — badges scroll and clip inside
/// that fixed shape instead of the capsule itself stretching past the screen edge as you scroll.
/// Selecting a year re-centers that badge in the visible bar via `ScrollViewReader`.
struct YearFilterBar: View {
    let years: [Int]
    @Binding var selectedYear: Int?
    /// Albums keep the established leading "All" chip; EventList uses a trailing one so the
    /// chronological years read naturally from newest down to oldest.
    var placesAllLast: Bool = false
    /// EventList can render directly on its grouped background, avoiding a visible horizontal
    /// fill strip around the embedded year `ScrollView`.
    var showsBackground: Bool = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !placesAllLast { allButton(proxy: proxy) }

                    ForEach(years, id: \.self) { year in
                        yearButton(title: String(year), selected: selectedYear == year) {   // Không dùng formatted()
                            select(year, proxy: proxy)
                        }
                        .id(Optional(year))
                    }

                    if placesAllLast { allButton(proxy: proxy) }
                }
                .padding(6)
            }
            .background(showsBackground ? Color(.tertiarySystemFill) : .clear)
            .clipShape(Capsule())
        }
    }

    private func allButton(proxy: ScrollViewProxy) -> some View {
        yearButton(title: localizedString("album.year_filter.all", defaultValue: "All"), selected: selectedYear == nil) {
            select(nil, proxy: proxy)
        }
        .id(Optional<Int>.none)
    }

    private func select(_ year: Int?, proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            selectedYear = year
        }
        withAnimation(.snappy(duration: 0.3)) {
            proxy.scrollTo(year, anchor: .center)
        }
    }

    @ViewBuilder
    private func yearButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? .white : .primary)
                .frame(height: 42)
                .padding(.horizontal, 22)
                .background {
                    if selected {
                        Capsule().fill(Color.black)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Year Filter Badge

private struct YearFilterBadge: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(title)
                    .font(
                        .system(
                            size: 16,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(
                        isSelected
                        ? Color.primary
                        : Color.secondary
                    )

                Capsule()
                    .fill(
                        isSelected
                        ? Color.primary
                        : Color.clear
                    )
                    .frame(width: 18, height: 2)
            }
            .frame(minWidth: 44)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }
}

// MARK: - Album Card

struct AlbumDesignCard: View {

    let album: AlbumCardSample

    private let cardHeight: CGFloat = 330
    private let cornerRadius: CGFloat = 24

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverImage
            gradientOverlay
            cardContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(Color(.secondarySystemBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.06),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(0.10),
            radius: 18,
            x: 0,
            y: 8
        )
    }

    /// Real cover photo when `album.coverPhoto` is set (production usage); otherwise falls back to
    /// `album.imageName` rendered as an SF Symbol over a tinted fill (design-preview usage, where
    /// there's no real Album cover source).
    private var coverImage: some View {
        Group {
            if let coverPhoto = album.coverPhoto {
                AlbumPhotoView(
                    reference: coverPhoto, crop: .centered, contentMode: .fill,
                    targetSize: CGSize(width: 660, height: 660)
                )
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: album.imageName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(64)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipped()
    }

    private var gradientOverlay: some View {
        LinearGradient(
            stops: [
                .init(
                    color: .clear,
                    location: 0.28
                ),
                .init(
                    color: .black.opacity(0.12),
                    location: 0.52
                ),
                .init(
                    color: .black.opacity(0.80),
                    location: 1.00
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()

            albumIdentity

            metadata
        }
        .padding(22)
    }

    private var albumIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(album.title)
                .font(
                    .system(
                        size: 27,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(album.subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
        }
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            metadataPill(
                systemImage: "photo.on.rectangle.angled",
                text: localizedString("album.photosCount", defaultValue: "\(album.photoCount) photos")
            )

            metadataPill(
                systemImage: "calendar",
                text: album.dateRange
            )

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private func metadataPill(
        systemImage: String,
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
    }
}

// MARK: - Search Preview

private struct AlbumSearchPreview: View {

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary)

                        Text("Search Albums")
                            .font(.title3.weight(.semibold))

                        Text("Search by album title, date, or location.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)

                        Text("No Results")
                            .font(.title3.weight(.semibold))

                        Text("No albums match “\(searchText)”.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search albums"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Album Card — English") {
    AlbumCardDesignPreview()
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Album Card — Vietnamese") {
    AlbumCardDesignPreview()
        .environment(\.locale, Locale(identifier: "vi"))
}
