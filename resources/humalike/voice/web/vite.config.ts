import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  build: { target: "chrome107", sourcemap: false, emptyOutDir: true },
});
