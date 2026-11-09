import * as Alchemy from "alchemy"
import * as Cloudflare from "alchemy/Cloudflare"

/**
 * arewetiny.sudokw.com — one Worker, one route.
 *
 * The site is static after `vite build` (SSR is only needed once GitHub
 * integration lands, and Alchemy's Vite website handles both), so there is no
 * separate API worker and no service binding to keep in sync.
 *
 * The route is pinned to the zoneless subdomain on purpose: `workersDev` stays
 * on so a deploy can be smoke-tested at the workers.dev URL before DNS is
 * touched, and the custom domain is a `routes` entry rather than a redirect —
 * a redirect would make every absolute URL in the page point at the wrong host.
 *
 * Credentials come from `apps/webapp/.env`, which is gitignored; `alchemy`
 * reads CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID from the environment.
 */
export default class AreWeTiny extends Cloudflare.Website.Vite<AreWeTiny>()("AreWeTiny", {
  name: "arewetiny",
  rootDir: ".",
  // Playback and the scrubber hold local state; a second dev server on the
  // next free port would silently split the origin, so pin it.
  dev: { port: 5183, strictPort: true },
  routes: [{ pattern: "arewetiny.sudokw.com/*", zoneName: "sudokw.com" }],
  workersDev: true,
})

// Referenced so the import is not tree-shaken in editors that type-check this
// file alone; the stage is what Alchemy keys its state files on.
export const stage = Alchemy.Stage
