import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Internal authoring tool only — never part of the Xcode build, never deployed as a
// requirement. See docs/specs/SPEC-LAYOUT-STUDIO.md § 2.
export default defineConfig({
  plugins: [react()],
  base: "./",
});
