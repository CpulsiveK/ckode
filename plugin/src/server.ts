import type { Config, Plugin, PluginOptions } from "@opencode-ai/plugin"
import os from "os"
import path from "path"
import { API_KEY_ENV, FREE_PROVIDER_ID, PROVIDER_ID, providerName, keyFromEnv, loadCatalog, type Catalog } from "./gateway"

/**
 * Server half of ckode: keeps OpenCode's free models available, registers the
 * one extra provider the user chose at launch (if any), fills its model list
 * from that server, and hides every other provider.
 *
 * The provider has to be injected through the `config` hook. OpenCode's
 * `provider.models` hook only runs for providers already in the models.dev
 * catalogue, and `ckode` is not in it, so that hook would never fire.
 */
const server: Plugin = async (_input, options) => {
  const baseURL = resolveBaseURL(options)
  const name = resolveName(options)
  return {
    config: async (cfg) => {
      // No URL means the user kept the default, OpenCode's free models.
      if (!baseURL) return lock(cfg)
      const key = keyFromEnv() ?? (await storedKey())
      lock(cfg, { baseURL, name, catalog: await catalogFor(baseURL, key) })
    },
    auth: {
      provider: PROVIDER_ID,
      methods: [{ type: "api", label: "API key" }],
    },
  }
}

export default { id: "ckode", server }

/**
 * Applied last, so it wins over every config file: a user or project that
 * enables another provider still gets only the configured provider plus OpenCode's free models, because both provider
 * paths (the provider service and the Connect dialog) read this same config
 * object after the hook. Autoupdate is off because the launcher pins the
 * OpenCode version; upgrades go through `ckode upgrade` after evaluation.
 */
function lock(cfg: Config, extra?: { baseURL: string; name: string; catalog: Catalog }) {
  cfg.autoupdate = false
  cfg.enabled_providers = extra ? [PROVIDER_ID, FREE_PROVIDER_ID] : [FREE_PROVIDER_ID]
  cfg.disabled_providers = []
  cfg.provider = extra
    ? {
        [PROVIDER_ID]: {
          name: extra.name || providerName(extra.baseURL),
          npm: "@ai-sdk/openai-compatible",
          api: extra.baseURL,
          env: [API_KEY_ENV],
          options: { baseURL: extra.baseURL },
          models: extra.catalog.models,
        },
      }
    : {}
}

/** `CKODE_BASE_URL` wins so a run can point at another server; otherwise the launcher's choice. Empty means none. */
export function resolveBaseURL(options: PluginOptions | undefined, env: Record<string, string | undefined> = process.env) {
  const configured = env["CKODE_BASE_URL"]?.trim() || (typeof options?.baseURL === "string" ? options.baseURL : "")
  return configured.replace(/\/+$/, "")
}

/** The name the user gave the provider, shown in the model list. */
export function resolveName(options: PluginOptions | undefined) {
  return typeof options?.name === "string" ? options.name.trim() : ""
}

/**
 * Stale-while-revalidate. A cached catalogue is returned immediately and
 * refreshed in the background for next start, because this hook blocks the
 * provider list and the gateway is VPN-gated. Only a first run waits on the
 * network, and even then it falls back to an empty list rather than hanging.
 */
export async function catalogFor(baseURL: string, key: string | undefined, dir = cacheDir()): Promise<Catalog> {
  const file = Bun.file(path.join(dir, `catalog-${fingerprint(baseURL, key)}.json`))
  const refresh = loadCatalog(baseURL, key).then(async (catalog) => {
    await Bun.write(file, JSON.stringify(catalog))
    return catalog
  })
  // Both branches below handle a failed refresh, but only after reading the
  // cache. A gateway that fails faster than that read would otherwise surface
  // as an unhandled rejection first (reliably so on Windows).
  refresh.catch(() => {})
  const cached = (await file.exists()) ? ((await file.json().catch(() => undefined)) as Catalog | undefined) : undefined
  if (cached) {
    refresh.catch((error) => log(`refresh failed, using cached models: ${error.message}`))
    return cached
  }
  return refresh.catch((error) => {
    log(`could not load models from ${baseURL}: ${error.message}. Check the stored key with: ckode auth list`)
    return { models: {}, described: false }
  })
}

/** Reads the key `opencode auth login` stored, from OpenCode's own credential file. */
export async function storedKey(file = path.join(dataDir(), "auth.json")) {
  const auth = (await Bun.file(file)
    .json()
    .catch(() => ({}))) as Record<string, { type?: string; key?: string }>
  const entry = auth[PROVIDER_ID]
  if (entry?.type !== "api") return
  return entry.key?.trim() || undefined
}

/** Models are scoped per key, so each key and gateway gets its own cache entry. */
function fingerprint(baseURL: string, key: string | undefined) {
  return new Bun.CryptoHasher("sha256")
    .update(`${baseURL}\n${key ?? ""}`)
    .digest("hex")
    .slice(0, 16)
}

// Mirrors xdg-basedir, which OpenCode uses for its own directories.
function dataDir() {
  return path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share"), "opencode")
}

function cacheDir() {
  return path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "ckode")
}

// stderr would tear through the TUI, so the plugin logs to its own file.
function log(message: string) {
  const line = `${new Date().toISOString()} ckode: ${message}\n`
  const file = path.join(cacheDir(), "plugin.log")
  Bun.file(file)
    .text()
    .catch(() => "")
    .then((prev) => Bun.write(file, prev + line))
    .catch(() => {})
}
