import SwiftUI

// MARK: - Preview Models

struct AlbumDetailSample {
    let eyebrow: String
    let title: String
    let subtitle: String
    let dateRange: String
    let heroImageName: String
    let introduction: String
    let pages: [AlbumPageSample]
}

struct AlbumPageSample: Identifiable {
    let id = UUID()
    let photos: [AlbumPhotoSample]
}

struct AlbumPhotoSample: Identifiable {
    let id = UUID()
    let imageName: String
    let symbolName: String
}

extension AlbumDetailSample {
    /// The original design-mock content — used as the default so the standalone `#Preview`
    /// below keeps working unchanged; real call sites (e.g. `HomeView`) pass their own.
    static let sample = AlbumDetailSample(
        eyebrow: "SYDNEY · 2026",
        title: "Summer in Sydney",
        subtitle: "A week by the harbour",
        dateRange: "14–21 January 2026",
        heroImageName: "album-hero",
        introduction:
            "Một tuần của nắng, gió biển và những buổi chiều đi bộ quanh bến cảng. Những khoảnh khắc nhỏ đã trở thành một phần ký ức thật đẹp.",
        pages: [
            AlbumPageSample(
                photos: [
                    AlbumPhotoSample(
                        imageName: "album-photo-01",
                        symbolName: "photo"
                    )
                ]
            ),

            AlbumPageSample(
                photos: [
                    AlbumPhotoSample(
                        imageName: "album-photo-02",
                        symbolName: "sun.max"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-03",
                        symbolName: "water.waves"
                    )
                ]
            ),

            AlbumPageSample(
                photos: [
                    AlbumPhotoSample(
                        imageName: "album-photo-04",
                        symbolName: "building.2"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-05",
                        symbolName: "figure.walk"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-06",
                        symbolName: "camera"
                    )
                ]
            ),

            AlbumPageSample(
                photos: [
                    AlbumPhotoSample(
                        imageName: "album-photo-07",
                        symbolName: "leaf"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-08",
                        symbolName: "cloud.sun"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-09",
                        symbolName: "tram"
                    ),
                    AlbumPhotoSample(
                        imageName: "album-photo-10",
                        symbolName: "heart"
                    )
                ]
            )
        ]
    )
}

// MARK: - Main Preview

struct AlbumDetailDesignPreview: View {

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPage = 0

    let album: AlbumDetailSample

    /// Đổi thành true sau khi đã thêm ảnh vào Assets.xcassets.
    private let useAssetImages = false

    init(album: AlbumDetailSample = .sample) {
        self.album = album
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroCover

                albumIntroduction

                albumPagesSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var heroCover: some View {
        ZStack {
            heroImage
            heroGradient
            heroNavigation
            heroContent
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroImage: some View {
        Group {
            if useAssetImages {
                Image(album.heroImageName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.9),
                            Color.indigo.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var heroGradient: some View {
        LinearGradient(
            stops: [
                .init(
                    color: .black.opacity(0.15),
                    location: 0
                ),
                .init(
                    color: .clear,
                    location: 0.32
                ),
                .init(
                    color: .black.opacity(0.08),
                    location: 0.52
                ),
                .init(
                    color: .black.opacity(0.82),
                    location: 1
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var heroNavigation: some View {
        VStack {
            HStack {
                heroButton(systemImage: "chevron.left") {
                    dismiss()
                }

                Spacer()

                heroButton(systemImage: "ellipsis") {
                    // Preview action
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)

            Spacer()
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text(album.eyebrow)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.bottom, 10)

            Text(album.title)
                .font(
                    .system(
                        size: 36,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 7)

            Text(album.subtitle)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .padding(.bottom, 16)

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))

                Text(album.dateRange)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.82))
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottomLeading
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private func heroButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Introduction

    private var albumIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("album.detail.story_section.title")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            Text(album.introduction)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 30)
        .background(Color(.systemBackground))
    }

    // MARK: - Album Pages

    private var albumPagesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageSectionHeader

            pageCarousel

            pageIndicator
        }
        .padding(.top, 26)
        .padding(.bottom, 48)
    }

    private var pageSectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("album.detail.pages_section.title")
                    .font(.system(size: 26, weight: .bold))

                Text(localizedString("album.detail.page_count", defaultValue: "\(album.pages.count) pages"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(selectedPage + 1) / \(album.pages.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var pageCarousel: some View {
        TabView(selection: $selectedPage) {
            ForEach(Array(album.pages.enumerated()), id: \.element.id) {
                index,
                page in

                AlbumPageView(
                    page: page,
                    useAssetImages: useAssetImages
                )
                .padding(.horizontal, 20)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 500)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(album.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        selectedPage == index
                            ? Color.primary
                            : Color.secondary.opacity(0.25)
                    )
                    .frame(
                        width: selectedPage == index ? 20 : 7,
                        height: 7
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .animation(
            .easeInOut(duration: 0.2),
            value: selectedPage
        )
    }
}

// MARK: - Album Page

private struct AlbumPageView: View {

    let page: AlbumPageSample
    let useAssetImages: Bool

    private let pageCornerRadius: CGFloat = 4
    private let photoSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageHeight = geometry.size.height

            pageLayout(
                width: pageWidth,
                height: pageHeight
            )
            .padding(12)
            .frame(
                width: pageWidth,
                height: pageHeight
            )
            .background(Color.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: pageCornerRadius,
                    style: .continuous
                )
            )
            .shadow(
                color: .black.opacity(0.10),
                radius: 16,
                x: 0,
                y: 8
            )
        }
    }

    @ViewBuilder
    private func pageLayout(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        switch page.photos.count {
        case 1:
            onePhotoLayout

        case 2:
            twoPhotoLayout

        case 3:
            threePhotoLayout

        default:
            fourPhotoLayout
        }
    }

    // MARK: 1 Photo

    private var onePhotoLayout: some View {
        photoView(page.photos[0])
    }

    // MARK: 2 Photos

    private var twoPhotoLayout: some View {
        VStack(spacing: photoSpacing) {
            photoView(page.photos[0])
            photoView(page.photos[1])
        }
    }

    // MARK: 3 Photos

    private var threePhotoLayout: some View {
        VStack(spacing: photoSpacing) {
            photoView(page.photos[0])

            HStack(spacing: photoSpacing) {
                photoView(page.photos[1])
                photoView(page.photos[2])
            }
        }
    }

    // MARK: 4 Photos

    private var fourPhotoLayout: some View {
        VStack(spacing: photoSpacing) {
            HStack(spacing: photoSpacing) {
                photoView(page.photos[0])
                photoView(page.photos[1])
            }

            HStack(spacing: photoSpacing) {
                photoView(page.photos[2])
                photoView(page.photos[3])
            }
        }
    }

    // MARK: Photo

    private func photoView(
        _ photo: AlbumPhotoSample
    ) -> some View {
        Group {
            if useAssetImages {
                Image(photo.imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.24),
                            Color.gray.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 10) {
                        Image(systemName: photo.symbolName)
                            .font(.system(size: 32, weight: .light))

                        Text(photo.imageName)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .clipped()
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Album Detail — Pages") {
    NavigationStack {
        AlbumDetailDesignPreview()
    }
}
