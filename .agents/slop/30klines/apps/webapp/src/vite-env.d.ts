/// <reference types="vite/client" />

declare module "virtual:compare-data" {
  import type { CompareData } from "../plugins/compare-data"
  const data: CompareData
  export default data
}
