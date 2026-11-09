import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import path from "node:path";

export default defineConfig({
  server: { port: 5183 },
  resolve: { alias: { "@": path.resolve(__dirname, "./src"), "@viz": path.resolve(__dirname, "../../packages/visualizer/src") } },
  plugins: [tailwindcss(), tanstackStart(), react()],
});
