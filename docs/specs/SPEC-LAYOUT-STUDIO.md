
# SPEC — Nizi Layout Studio

## 1. Mục tiêu

Xây dựng một web module độc lập nằm trong cùng repository với app Nizi Native để thiết kế trực quan các Album Page Layout và export ra JSON đúng chuẩn mà app iOS hiện đang sử dụng.

Module này không phải một phần runtime của app iOS.

Nó là một internal authoring tool:

Design Layout on Web
    ↓
Validate
    ↓
Export `album-layouts.json`
    ↓
Copy/replace vào iOS project
    ↓
Album Planner sử dụng layout mới

Mục tiêu chính:

- chủ động tạo nhiều layout Album hơn;
- không phải sửa JSON thủ công;
- kéo/thả và resize slot trực quan;
- kiểm tra orientation của từng slot;
- preview layout bằng ảnh thật local;
- import layout JSON hiện tại của app;
- export JSON đúng schema hiện tại;
- không làm thay đổi kiến trúc Planner/Layout Engine bên iOS.

---

# 2. Vị trí trong repository

Không tạo repository riêng.

Tạo module tại:

`tools/layout-studio/`

Cấu trúc tổng thể:

Nizi/
├── Nizi.xcodeproj
├── Nizi/
│   ├── App/
│   ├── Features/
│   ├── Resources/
│   │   └── album-layouts.json
│   └── ...
│
├── tools/
│   └── layout-studio/
│
├── docs/
└── README.md

`layout-studio` là một project web độc lập về build và dependency.

Không đặt React/TypeScript source vào trong `Nizi/Features`.

Không thêm Node dependency vào Xcode target.

Không làm thay đổi iOS build process.

---

# 3. Công nghệ

Sử dụng:

- Vite
- React
- TypeScript
- Konva
- react-konva
- Zustand
- Zod

Không dùng Next.js.

Không cần backend.

Không cần database.

Không cần authentication.

Không upload dữ liệu lên server.

Module phải chạy local bằng:

`npm install`

sau đó:

`npm run dev`

Production build:

`npm run build`

---

# 4. Quan trọng nhất: App JSON là source of truth

Trước khi code UI, phải khảo sát project iOS hiện tại và xác định chính xác schema đang được app dùng cho:

- `AlbumLayoutLibrary`
- `AlbumPageLayout`
- `AlbumLayoutSlot`
- `AlbumSlotOrientation`
- `album-layouts.json`

Không được tự suy đoán schema.

Không tạo schema mới chỉ vì web editor tiện hơn.

Claude phải đọc:

- Swift model liên quan đến Album Layout;
- JSON resource hiện tại;
- decoder/load mechanism;
- các test liên quan nếu có.

Sau khi khảo sát, tạo TypeScript types phản ánh đúng schema production hiện tại.

Ví dụ chỉ mang tính minh họa:

```ts
type SlotOrientation =
  | "landscape"
  | "portrait"
  | "square"
  | "any";

interface AlbumLayoutSlot {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  preferredOrientation: SlotOrientation;
}

interface AlbumPageLayout {
  id: string;
  photoCount: number;
  slots: AlbumLayoutSlot[];
}

interface AlbumLayoutLibrary {
  layouts: AlbumPageLayout[];
}
````

Nếu schema iOS thực tế khác ví dụ trên, phải dùng schema thực tế.

Không sửa Swift model chỉ để khớp web trừ khi phát hiện bug thật và báo trước.

---

# 5. Nguyên tắc dữ liệu

Layout geometry phải dùng normalized coordinate:

`0...1`

Không persistence theo pixel.

Canvas trên web có thể render ở:

`800 × 800`

hoặc kích thước phù hợp với viewport.

Nhưng state phải lưu:

```ts
{
  x: 0.05,
  y: 0.10,
  width: 0.90,
  height: 0.40
}
```

Render lên Konva:

```ts
pixelX = x * canvasWidth
pixelY = y * canvasHeight
pixelWidth = width * canvasWidth
pixelHeight = height * canvasHeight
```

Sau drag/resize:

```ts
x = node.x() / canvasWidth
y = node.y() / canvasHeight
width = actualWidth / canvasWidth
height = actualHeight / canvasHeight
```

Clamp kết quả về `0...1`.

Không lưu scaleX/scaleY của Konva vào JSON.

Sau transform phải normalize lại width/height và reset transform scale về 1.

---

# 6. Hai lớp model

Nên tách:

## A. Production/App Layout Model

Phản ánh chính xác JSON app iOS hiểu.

## B. Studio Model

Có thể chứa metadata phục vụ editor, ví dụ:

* displayName;
* category;
* notes;
* favorite;
* createdAt;
* updatedAt;
* locked;
* preview metadata.

Studio-only field không được tự động xuất vào production JSON nếu app không hỗ trợ.

Kiến trúc:

Studio Model
↓
Exporter
↓
App Layout Model
↓
album-layouts.json

Không để web tool ép app phải hiểu metadata editor.

---

# 7. Cấu trúc source đề xuất

Tạo:

tools/layout-studio/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
├── src/
│   ├── domain/
│   │   ├── albumLayout.ts
│   │   ├── studioLayout.ts
│   │   └── schemas.ts
│   │
│   ├── editor/
│   │   ├── LayoutCanvas.tsx
│   │   ├── LayoutSlot.tsx
│   │   ├── SlotTransformer.tsx
│   │   ├── GridLayer.tsx
│   │   └── CanvasBackground.tsx
│   │
│   ├── panels/
│   │   ├── LayoutLibraryPanel.tsx
│   │   ├── LayoutInspector.tsx
│   │   ├── SlotInspector.tsx
│   │   └── PhotoPreviewPanel.tsx
│   │
│   ├── preview/
│   │   ├── LocalPhotoProvider.ts
│   │   ├── LayoutPhotoPreview.tsx
│   │   └── SpreadPreview.tsx
│   │
│   ├── services/
│   │   ├── importLayoutLibrary.ts
│   │   ├── exportLayoutLibrary.ts
│   │   ├── validateLayout.ts
│   │   ├── normalizeGeometry.ts
│   │   └── downloadJson.ts
│   │
│   ├── store/
│   │   └── layoutStudioStore.ts
│   │
│   ├── components/
│   │   ├── Toolbar.tsx
│   │   ├── OrientationBadge.tsx
│   │   └── ValidationPanel.tsx
│   │
│   ├── App.tsx
│   └── main.tsx
└── README.md

Có thể điều chỉnh tên file nhưng phải giữ separation tương đương.

---

# 8. Layout Studio UI

Desktop-first internal tool.

Không cần tối ưu mobile.

Bố cục ba cột:

┌────────────────┬────────────────────────────┬─────────────────┐
│ Layout Library │        Canvas Editor       │ Inspector       │
│                │                            │                 │
│ 1 Photo        │                            │ Layout          │
│ 2 Photos       │       PAGE CANVAS          │ Slot            │
│ 3 Photos       │                            │ Orientation     │
│ 4 Photos       │                            │ Geometry        │
│                │                            │                 │
└────────────────┴────────────────────────────┴─────────────────┘

Toolbar phía trên:

* Import JSON
* New Layout
* Duplicate
* Delete
* Add Slot
* Preview Photos
* Validate
* Export JSON

Không cần design hệ thống đẹp quá mức.

Ưu tiên công cụ sử dụng nhanh, rõ ràng.

---

# 9. Layout Library Panel

Hiển thị layout nhóm theo `photoCount`.

Ví dụ:

1 Photo

* single.full
* single.inset

2 Photos

* two.vertical
* two.horizontal
* two.heroTop
* two.heroLeft

3 Photos

* three.heroTop
* three.heroLeft
* three.equalColumns

4 Photos

* four.grid
* four.heroTop
* four.heroLeft

Mỗi item hiển thị:

* layout id;
* số ảnh;
* thumbnail geometry đơn giản.

Actions:

* select;
* new;
* duplicate;
* rename ID;
* delete.

Delete cần confirmation.

Duplicate phải tạo ID mới hoặc yêu cầu người dùng sửa ID trước khi export.

Không cho export nếu duplicate layout ID.

---

# 10. New Layout

Khi tạo layout mới:

Người dùng chọn:

* photoCount;
* layout ID.

Ví dụ:

`three.editorial01`

Sau khi tạo:

* canvas trống;
* có thể `Add Slot`.

Có thể cung cấp option:

`Create default slots`

nhưng không bắt buộc MVP.

Quy tắc:

`photoCount` cuối cùng phải bằng `slots.length` trước khi export production JSON.

---

# 11. Layout Canvas

Dùng `react-konva`.

Canvas đại diện cho một Page.

Canvas nên tự scale để vừa vùng editor nhưng giữ aspect ratio.

Nếu app hiện dùng page 1:1, canvas render 1:1.

Nếu schema hiện tại có page aspect ratio thì lấy từ schema thật.

Không hardcode format khác app.

Canvas có:

* page background;
* optional grid;
* slots;
* selection outline;
* transformer handles.

---

# 12. Slot interaction

Một slot phải hỗ trợ:

* select;
* drag;
* resize;
* delete;
* duplicate nếu dễ triển khai.

Dùng `Konva.Transformer`.

Resize từ:

* 4 góc;
* có thể thêm 4 cạnh.

Không cho slot:

* width <= 0;
* height <= 0;
* đi hoàn toàn ra ngoài page.

Ưu tiên clamp để slot luôn nằm trong page:

`x >= 0`

`y >= 0`

`x + width <= 1`

`y + height <= 1`

---

# 13. Snap và Grid

MVP cần snap đơn giản.

Mặc định:

`0.01`

tương đương 1% page.

Khi lưu geometry, round tối đa 3–4 chữ số thập phân.

Ví dụ tránh:

```json
"x": 0.103728912
```

Ưu tiên:

```json
"x": 0.104
```

Có toggle:

`Snap On / Off`

Grid hiển thị có thể là:

`20 × 20`

Grid chỉ hỗ trợ thiết kế.

Không export grid metadata.

---

# 14. Slot Inspector

Khi chọn slot, panel bên phải hiển thị:

* Slot ID
* X
* Y
* Width
* Height
* Preferred Orientation

Orientation values phải lấy đúng enum của app.

Nếu app hiện hỗ trợ:

* landscape
* portrait
* square
* any

thì web dùng đúng bốn giá trị đó.

Không tự thêm:

* horizontal
* vertical
* auto

nếu app không có.

Các input geometry có thể chỉnh bằng tay.

Khi chỉnh input:

* validate;
* clamp;
* update canvas realtime.

---

# 15. Orientation visualization

Trên slot hiển thị badge nhỏ:

* L = Landscape
* P = Portrait
* S = Square
* A = Any

Hoặc icon tương ứng.

Không che ảnh preview quá nhiều.

Orientation là metadata của slot, không thay đổi geometry tự động.

---

# 16. Local Photo Preview

Cho phép user chọn nhiều ảnh từ máy bằng browser file input.

Không upload ảnh.

Dùng:

`URL.createObjectURL(file)`

để preview local.

Ảnh chỉ tồn tại trong browser session.

Không lưu blob lớn vào localStorage.

Tự đọc:

* naturalWidth;
* naturalHeight.

Phân loại preview orientation:

* width > height → landscape;
* height > width → portrait;
* gần bằng nhau → square.

Có nút:

* Use Sample Photos / Select Photos
* Shuffle Preview
* Clear Photos

Không cần upload server.

---

# 17. Photo assignment trong preview

Khi preview layout:

Ưu tiên gán ảnh phù hợp với `preferredOrientation`.

Ví dụ:

slot landscape
→ ưu tiên ảnh landscape.

slot portrait
→ ưu tiên portrait.

slot square
→ ưu tiên square, sau đó landscape/portrait nếu thiếu.

slot any
→ ảnh bất kỳ.

Đây chỉ là preview helper.

Không cố tái tạo toàn bộ Album Planner.

Không đưa Planner scoring từ Swift sang TypeScript.

---

# 18. Image rendering trong slot

Preview ảnh dùng kiểu crop tương tự app:

`cover / scaledToFill`

Slot clip ảnh.

Không cần crop editor trong MVP.

Mục tiêu là nhìn nhanh xem geometry thực tế có đẹp không.

---

# 19. Import production JSON

Toolbar:

`Import App JSON`

Cho phép chọn `album-layouts.json`.

Import flow:

File
↓
JSON.parse
↓
Zod schema validation
↓
Semantic validation
↓
Studio state

Nếu file sai schema:

* không crash;
* hiển thị lỗi;
* chỉ rõ field/layout lỗi nếu có thể.

Import phải preserve:

* layout IDs;
* slot IDs;
* order;
* orientation;
* normalized geometry.

Import rồi export lại mà không sửa phải cho ra dữ liệu production tương đương về ý nghĩa.

Không được âm thầm thay đổi layout.

---

# 20. Zod schema

Tạo Zod schema phản ánh app model thật.

Validation tối thiểu:

* root structure đúng;
* layout ID không rỗng;
* layout ID unique;
* photoCount hợp lệ;
* slots là array;
* slot ID không rỗng;
* slot ID unique trong layout;
* x >= 0;
* y >= 0;
* width > 0;
* height > 0;
* x <= 1;
* y <= 1;
* width <= 1;
* height <= 1;
* x + width <= 1;
* y + height <= 1;
* orientation hợp lệ;
* photoCount == slots.length.

Nếu app hiện hỗ trợ thêm field thì validate theo schema thật.

---

# 21. Error và Warning

Phân biệt:

## Error

Không cho export.

Ví dụ:

* duplicate layout ID;
* duplicate slot ID;
* slot vượt page;
* invalid orientation;
* photoCount không bằng số slot;
* thiếu field bắt buộc.

## Warning

Cho phép export nhưng báo.

Ví dụ:

* slot overlap;
* slot quá nhỏ;
* margin quá sát;
* layout geometry gần như giống layout khác;
* tất cả slot cùng orientation dù geometry không phù hợp.

MVP không bắt buộc similarity detection nâng cao.

Nhưng validator structure phải hỗ trợ:

```ts
type ValidationIssue = {
  level: "error" | "warning";
  code: string;
  message: string;
  layoutId?: string;
  slotId?: string;
};
```

---

# 22. Export production JSON

Toolbar:

`Export App JSON`

Flow:

Studio State
↓
Convert to App Layout Model
↓
Zod validation
↓
Semantic validation
↓
Round normalized geometry
↓
JSON.stringify
↓
Download `album-layouts.json`

Không export nếu còn Error.

Warning không chặn export.

Export chỉ chứa field app hỗ trợ.

Không export Studio-only metadata.

Không ghi trực tiếp vào iOS resource trong MVP.

User download file rồi tự replace vào project.

Điều này tránh ghi nhầm production JSON.

---

# 23. Studio project persistence

Không cần DB.

MVP dùng:

* localStorage cho autosave lightweight;
* Save Studio Project JSON;
* Open Studio Project JSON.

Studio project có thể chứa metadata riêng.

Tên file đề xuất:

`nizi-layout-studio.json`

Không nhầm với:

`album-layouts.json`

Production export và Studio project là hai loại file khác nhau.

---

# 24. Autosave

Autosave Studio state vào localStorage sau thay đổi với debounce.

Ví dụ:

`300–500 ms`

Không autosave ảnh local dạng blob.

Khi reload web:

* restore layouts;
* restore selection nếu hợp lệ;
* ảnh preview có thể mất và user chọn lại.

Có action:

`Reset Studio`

với confirmation.

---

# 25. Undo/Redo

Nếu đơn giản, có thể triển khai ngay bằng state history.

Nếu làm tăng scope đáng kể, defer.

MVP ưu tiên:

* keyboard Delete;
* Cmd/Ctrl + D duplicate;
* arrow key nudge slot.

Undo/Redo là nice-to-have, không phải blocker.

---

# 26. Keyboard interactions

Nếu dễ triển khai:

* Delete/Backspace → delete selected slot;
* Arrow → move 1 snap unit;
* Shift + Arrow → move lớn hơn;
* Cmd/Ctrl + D → duplicate selected slot/layout tùy context;
* Escape → deselect.

Không bắt buộc nếu gây phức tạp.

---

# 27. Spread Preview

Có thể triển khai trong cùng module nhưng để sau MVP cơ bản.

Mode:

`Page | Spread`

Spread Preview hiển thị hai layout cạnh nhau để người thiết kế kiểm tra visual balance.

Quan trọng:

Đây chỉ là authoring preview.

Không liên quan quyết định production iPhone Viewer hiện chỉ hiển thị một Page.

Không sửa logic Single-Page Album Viewer bên app.

Spread Preview chỉ phục vụ việc thiết kế layout pair.

---

# 28. Không làm trong MVP

Không xây:

* backend;
* account/login;
* cloud sync;
* upload ảnh;
* database;
* multi-user;
* comments;
* AI layout generation;
* automatic Planner port;
* full crop editor;
* text blocks;
* stickers;
* freeform illustration;
* export PDF;
* print engine;
* direct Xcode file mutation;
* deployment production bắt buộc.

Đây là internal layout authoring tool, không phải Canva.

---

# 29. README

Tạo:

`tools/layout-studio/README.md`

Bao gồm:

## Run

```bash
cd tools/layout-studio
npm install
npm run dev
```

## Build

```bash
npm run build
```

## Workflow

1. Import current `album-layouts.json`.
2. Create/duplicate layout.
3. Edit geometry.
4. Assign preferred orientation.
5. Preview using local photos.
6. Validate.
7. Export `album-layouts.json`.
8. Replace resource in iOS project.
9. Build iOS app.

README phải ghi rõ:

Studio không tự ghi vào iOS resource trong MVP.

---

# 30. Khảo sát trước khi implement

Trước khi viết app web, Claude phải báo cáo ngắn:

1. File Swift nào định nghĩa Layout Library.
2. File Swift nào định nghĩa Page Layout.
3. File Swift nào định nghĩa Slot.
4. Orientation enum hiện tại.
5. Đường dẫn `album-layouts.json`.
6. JSON root structure.
7. Field bắt buộc.
8. Field optional.
9. Quy tắc decoder.
10. Có version field hay không.
11. Page aspect ratio hiện tại.
12. Các layout IDs hiện có.
13. Số layout theo photoCount.
14. Có test fixture hay không.

Sau đó implement dựa trên kết quả thật.

Không yêu cầu user xác nhận lại nếu schema rõ ràng.

---

# 31. Acceptance Criteria

Hoàn thành khi:

1. `tools/layout-studio` tồn tại độc lập.
2. iOS app vẫn build mà không phụ thuộc npm.
3. `npm install` thành công.
4. `npm run dev` chạy Studio.
5. `npm run build` thành công.
6. Studio dùng React + TypeScript + Vite.
7. Canvas dùng react-konva.
8. State dùng normalized coordinates.
9. Có Layout Library panel.
10. Layout được group theo photoCount.
11. Có create layout.
12. Có duplicate layout.
13. Có delete layout.
14. Có select layout.
15. Có Add Slot.
16. Slot kéo được.
17. Slot resize được.
18. Slot luôn clamp trong Page.
19. Có snap.
20. Có inspector chỉnh geometry.
21. Có preferredOrientation editor.
22. Orientation values khớp Swift enum.
23. Có import app JSON.
24. Import validate schema.
25. Có local photo preview.
26. Ảnh không upload server.
27. Preview ảnh clip đúng slot.
28. Có Validate action.
29. Error ngăn export.
30. Warning không nhất thiết ngăn export.
31. photoCount phải bằng slot count.
32. Không duplicate layout ID.
33. Không duplicate slot ID trong layout.
34. Geometry hợp lệ trong 0...1.
35. Có Export App JSON.
36. Export chỉ chứa field app hiểu.
37. Export geometry được round hợp lý.
38. Import → export không làm mất layout.
39. Có autosave localStorage.
40. Có Save/Open Studio project.
41. README đầy đủ.
42. Không có backend.
43. Không thay đổi Planner.
44. Không thay đổi Album Viewer.
45. Không thay đổi production Layout Engine nếu không thực sự cần.
46. Không chạy simulator.
47. Không chạy iOS tests nếu chưa được yêu cầu.
48. Web build pass.
49. iOS build vẫn pass nếu có file iOS bị động tới.
50. Báo cáo rõ known limitations.

---

# 32. Thứ tự triển khai

## Phase 1 — Inspect existing app schema

Đọc Swift models + JSON.

Không code schema giả.

## Phase 2 — Scaffold Studio

Tạo Vite React TypeScript.

Cài:

* konva
* react-konva
* zustand
* zod

## Phase 3 — Domain types + Zod

Mirror production schema.

Thêm Studio model riêng nếu cần.

## Phase 4 — Import

Load `album-layouts.json`.

Parse + validate.

Đưa vào store.

## Phase 5 — Library panel

Browse/select/create/duplicate/delete.

## Phase 6 — Canvas editor

Konva stage/layer.

Slot drag/resize/select.

Normalized coordinate conversion.

## Phase 7 — Inspector

Geometry + orientation.

## Phase 8 — Preview photos

Local file selection.

Orientation detection.

Fill slots.

## Phase 9 — Validator

Errors + warnings.

## Phase 10 — Export

Convert Studio → App model.

Validate.

Download production JSON.

## Phase 11 — Persistence

localStorage + Studio JSON project.

## Phase 12 — Polish + docs

README.

Keyboard basics nếu hợp lý.

Build.

---

# 33. Báo cáo hoàn thành

Claude phải báo theo format:

1. Existing iOS layout schema discovered
2. Current JSON path and root shape
3. Existing layout count by photoCount
4. Files created
5. Files modified
6. Web stack used
7. TypeScript production model
8. Studio-only model
9. Import behavior
10. Canvas behavior
11. Normalized coordinate conversion
12. Drag/resize behavior
13. Snap behavior
14. Orientation editor
15. Local photo preview
16. Validation rules
17. Export behavior
18. Studio persistence
19. Commands to run
20. Web build result
21. iOS build result if applicable
22. Tests written
23. Tests executed
24. Known limitations
25. Recommended next improvements

Do not report only "done".

---

# 34. Task ngắn để giao trực tiếp Claude Code

Build an internal web tool called `Nizi Layout Studio` inside the existing Nizi repository at:

`tools/layout-studio`

Use:

* Vite
* React
* TypeScript
* react-konva
* Zustand
* Zod

Before implementing, inspect the existing iOS Album Layout models and the real `album-layouts.json`. Treat the current iOS JSON schema as the production source of truth. Do not invent a new app schema.

The Studio must let me:

1. Import the existing app `album-layouts.json`.
2. Browse layouts grouped by photo count.
3. Create, duplicate, rename and delete layouts.
4. Edit a Page visually using a Konva canvas.
5. Add, select, drag and resize photo slots.
6. Store all slot geometry as normalized coordinates 0...1.
7. Snap geometry to clean values.
8. Edit each slot's `preferredOrientation` using exactly the enum values supported by the iOS app.
9. Edit x/y/width/height numerically in an Inspector.
10. Select local photos only for preview, without uploading them anywhere.
11. Preview photos clipped inside layout slots.
12. Validate layout IDs, slot IDs, photo counts, geometry and orientation.
13. Distinguish validation errors from warnings.
14. Prevent production export when validation errors exist.
15. Export a clean `album-layouts.json` containing only fields understood by the iOS app.
16. Keep Studio-only metadata separate from the production export.
17. Autosave Studio state locally.
18. Save/open a Studio project JSON separately from the production app JSON.
19. Do not add backend, database, authentication or cloud features.
20. Do not modify Album Planner, Album Viewer or production Layout Engine unless required for compatibility with the existing schema.

The web project must build independently and must not become part of the Xcode build target.

Build only. Do not run Simulator or iOS tests unless explicitly requested.

At completion, report the actual discovered iOS schema, all files created/modified, import/export behavior, normalized-coordinate handling, validation rules, preview behavior, build results and known limitations.

```

Điểm tôi muốn Claude đặc biệt tuân thủ là **khảo sát schema thật trước rồi mới code**. Nếu không có bước này rất dễ xảy ra tình trạng web làm xong đẹp nhưng JSON chỉ “gần giống” schema Swift, sau đó lại phải sửa cả hai phía.
```
