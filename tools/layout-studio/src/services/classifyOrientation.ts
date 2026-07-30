/** Same ±5% "close enough to square" tolerance `AlbumLayoutValidator.squareRatioTolerance` and
 * `preview/LocalPhotoProvider.ts` already use — one shared threshold for "is this rect square"
 * everywhere in the Studio, rather than three slightly-different copies. */
const SQUARE_TOLERANCE = 0.05;

/** Derives `landscape`/`portrait`/`square` straight from a rect's own width/height — never
 * `"any"`, since that's a deliberate authoring choice ("accept whatever photo you're given"),
 * not something a rectangle's shape can imply on its own — the return type spells that out
 * explicitly (a strict subset of `AlbumSlotOrientation`, freely assignable to it) rather than
 * claiming the full 4-value type and just happening never to produce the 4th. Used to
 * auto-populate a slot's `preferredOrientation` from its frame (§ user request: "Preferred
 * Orientation cần tự nhận diện theo kích thước RECT") every time that frame changes — drag,
 * resize, or a manual Inspector edit — so the two never drift out of sync with the slot's actual
 * shape. */
export function classifyOrientationFromSize(width: number, height: number): "landscape" | "portrait" | "square" {
  if (width <= 0 || height <= 0) return "square";
  const ratio = width / height;
  if (Math.abs(ratio - 1) <= SQUARE_TOLERANCE) return "square";
  return ratio > 1 ? "landscape" : "portrait";
}
