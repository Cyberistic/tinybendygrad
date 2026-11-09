import * as Cloudflare from "@alchemy.run/cloudflare"

/**
 * arewetiny.sudokw.com — one Worker, one route, deployed from this directory.
 *
 * Alchemy v2: resources are top-level program entries and `export default` is
 * the thing the CLI deploys. The route names the zone by ID rather than by
 * name — `.env` already carries CLOUDFLARE_ZONE_ID, and an ID needs no DNS
 * lookup at deploy time.
 *
 * `Website.Vite` builds the client and the SSR bundle in one `vite build` and
 * enables `nodejs_compat` by default, which is what TanStack Start needs. The
 * workers.dev hostname stays available so a deploy can be smoke-tested before
 * DNS points anywhere.
 */
const zoneId = process.env.CLOUDFLARE_ZONE_ID

export default Cloudflare.Website.Vite("AreWeTiny", {
  name: "arewetiny",
  rootDir: ".",
  dev: { port: 5183, strictPort: true },
  routes: zoneId
    ? [{ pattern: "arewetiny.sudokw.com/*", zoneId }]
    : [{ pattern: "arewetiny.sudokw.com/*", zoneName: "sudokw.com" }],
  workersDev: true,
})
