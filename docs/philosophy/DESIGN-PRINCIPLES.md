# Design Principles

Cross-cutting UI/UX rules, derived from the Memory Discovery UI spec ([ui/memory-discovery.md](../ui/memory-discovery.md)) and generalized for reuse by other modules.

## 1. Product language

The product must read as helping, not surveilling. Avoid words that imply bulk collection or unilateral action; prefer language that names what's happening and keeps the user in control.

Avoid:

```text
AI đã quyết định
Nizi sẽ upload toàn bộ ảnh
Đang thu thập dữ liệu
Đã xác định chính xác đây là chuyến đi
```

Prefer:

```text
Nizi đang khám phá ảnh từ năm 2022
Nizi đã tìm thấy một chuyến đi có thể tạo Album
Ảnh được xử lý trên iPhone của bạn
Bạn luôn có thể thay đổi lựa chọn
```

## 2. Presentation layer boundaries

The Presentation layer (screens, components, view models) must not:

- call PhotoKit (or any framework data source) directly;
- write directly to persistence;
- contain clustering, scoring, or other domain algorithms;
- hold large in-memory assets (e.g. `UIImage`) in long-lived state.

Screens read and act through Application use cases only.

## 3. Accessibility

- Support Dynamic Type.
- VoiceOver must announce counts and selection state, not just visuals.
- Never use color as the only signal.
- Respect minimum tap target sizes.
- Show progress as text, not only as a spinner/ring.
- Meet standard contrast requirements.

## 4. Performance UI

- Use lazy grids for large photo collections.
- Never generate full-resolution thumbnails for list/grid cells.
- Cancel in-flight image requests when a cell leaves the screen.
- View models must not retain images for an entire list.
- Use small covers for list/candidate cards; request larger images only for full-screen preview.

## 5. Visual tone

- Warm, light backgrounds; photos are the focal point.
- Minimal text, soft accents, moderately rounded cards.
- Avoid heavy gradients.
- Debug/diagnostic UI must stay visually separate from user-facing screens and confined to debug builds.
