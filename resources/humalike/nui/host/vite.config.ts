import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  publicDir: "../../voice/web/public",
  build: { target: "chrome107", sourcemap: false, emptyOutDir: true },
});
