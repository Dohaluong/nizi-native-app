/** Triggers a browser file download for a JSON-serializable value — used by both the production
 * export and "Save Studio Project" (§ 22, § 23). Never uploads/sends anything anywhere. */
export function downloadJson(filename: string, value: unknown): void {
  const json = JSON.stringify(value, null, 2);
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
