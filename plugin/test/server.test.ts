import { afterAll, describe, expect, test } from "bun:test"
import fs from "fs/promises"
import os from "os"
import path from "path"
import { FALLBACK_LIMIT, keyFromEnv, loadCatalog, perMillion, providerName } from "../src/gateway"
import plugin, { catalogFor, resolveBaseURL, resolveName, storedKey } from "../src/server"

// A stand-in gateway speaking LiteLLM's shapes; each test picks its behaviour by path prefix.
const state = { outage: false }
const gateway = Bun.serve({
  port: 0,
  fetch(request) {
    const url = new URL(request.url)
    const [, scenario, ...rest] = url.pathname.split("/")
    const route = "/" + rest.join("/")
    if (scenario === "down" || state.outage) return new Response("nope", { status: 503 })
    if (scenario === "ollama" && route === "/v1/models") return Response.json({ data: [{ id: "qwen2.5-coder:7b" }] })
    if (request.headers.get("authorization") !== "Bearer sk-good") return new Response("no", { status: 401 })
    if (route === "/v1/models")
      return Response.json({
        data: [
          { id: "claude-sonnet-4-6" },
          { id: "qwen3p7-plus" },
          { id: "text-embedding-3-small" },
          { id: "deepgram/nova-3" },
        ],
      })
    if (route === "/v1/model/info" && scenario === "litellm")
      return Response.json({
        data: [
          {
            model_name: "claude-sonnet-4-6",
            model_info: {
              max_input_tokens: 1_050_000,
              max_output_tokens: 64_000,
              input_cost_per_token: 0.000003,
              output_cost_per_token: 0.000015,
              cache_read_input_token_cost: 0.0000003,
              mode: "chat",
              supports_vision: true,
              supports_pdf_input: true,
            },
          },
          { model_name: "deepgram/nova-3", model_info: { mode: "audio_transcription", input_cost_per_token: 0 } },
        ],
      })
    return new Response("not found", { status: 404 })
  },
})
const base = (scenario: string) => `http://localhost:${gateway.port}/${scenario}/v1`
const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "ckode-test-"))
afterAll(async () => {
  gateway.stop(true)
  await fs.rm(tmp, { recursive: true, force: true })
})

describe("loadCatalog", () => {
  test("uses /v1/model/info limits, prices and modes; drops embeddings and transcription", async () => {
    const catalog = await loadCatalog(base("litellm"), "sk-good")
    expect(catalog.described).toBe(true)
    expect(Object.keys(catalog.models).sort()).toEqual(["claude-sonnet-4-6", "qwen3p7-plus"])
    expect(catalog.models["claude-sonnet-4-6"]).toEqual({
      name: "claude-sonnet-4-6",
      tool_call: true,
      attachment: true,
      modalities: { input: ["text", "image", "pdf"], output: ["text"] },
      limit: { context: 1_050_000, output: 64_000 },
      cost: { input: 3, output: 15, cache_read: 0.3, cache_write: 0 },
    })
    // Reported without info: defaulted limits and no invented price.
    expect(catalog.models["qwen3p7-plus"]).toEqual({ name: "qwen3p7-plus", tool_call: true, limit: FALLBACK_LIMIT })
  })

  test("treats a 404 on /v1/model/info as an ordinary OpenAI-compatible host", async () => {
    const catalog = await loadCatalog(base("plain"), "sk-good")
    expect(catalog.described).toBe(false)
    // Without modes only the embedding can be recognised by name.
    expect(Object.keys(catalog.models).sort()).toEqual(["claude-sonnet-4-6", "deepgram/nova-3", "qwen3p7-plus"])
  })

  test("throws on a rejected key so the empty list is explained", async () => {
    await expect(loadCatalog(base("litellm"), "sk-bad")).rejects.toThrow("401")
  })
})

test("perMillion rounds away float noise", () => {
  expect(perMillion(0.0000004)).toBe(0.4)
  expect(perMillion(undefined)).toBe(0)
})

test("keyFromEnv treats empty and whitespace as absent", () => {
  expect(keyFromEnv({ CKODE_API_KEY: "" })).toBeUndefined()
  expect(keyFromEnv({ CKODE_API_KEY: "  " })).toBeUndefined()
  expect(keyFromEnv({ CKODE_API_KEY: " sk-good " })).toBe("sk-good")
})

test("resolveBaseURL prefers the env override, then plugin options, then nothing", () => {
  expect(resolveBaseURL({ baseURL: "https://prod/v1/" }, { CKODE_BASE_URL: "http://local/v1" })).toBe(
    "http://local/v1",
  )
  expect(resolveBaseURL({ baseURL: "https://prod/v1/" }, {})).toBe("https://prod/v1")
  expect(resolveBaseURL(undefined, { CKODE_BASE_URL: " " })).toBe("")
})

test("storedKey reads only an api credential for ckode", async () => {
  const file = path.join(tmp, "auth.json")
  await Bun.write(file, JSON.stringify({ ckode: { type: "api", key: "sk-good" }, openai: { type: "api", key: "x" } }))
  expect(await storedKey(file)).toBe("sk-good")
  await Bun.write(file, JSON.stringify({ ckode: { type: "oauth", access: "x" } }))
  expect(await storedKey(file)).toBeUndefined()
  expect(await storedKey(path.join(tmp, "missing.json"))).toBeUndefined()
})

describe("catalogFor", () => {
  test("serves the cache when the gateway is unreachable", async () => {
    const dir = path.join(tmp, "cache-swr")
    const fresh = await catalogFor(base("litellm"), "sk-good", dir)
    expect(Object.keys(fresh.models)).toHaveLength(2)
    state.outage = true
    const cached = await catalogFor(base("litellm"), "sk-good", dir)
    state.outage = false
    expect(cached).toEqual(fresh)
    // A different key must not see another key's models.
    const other = await catalogFor(base("litellm"), "sk-bad", dir)
    expect(other.models).toEqual({})
  })

  test("asks a host for models without a key, as a local Ollama needs none", async () => {
    const catalog = await catalogFor(base("ollama"), undefined, path.join(tmp, "cache-local"))
    expect(Object.keys(catalog.models)).toEqual(["qwen2.5-coder:7b"])
    expect(catalog.models["qwen2.5-coder:7b"].limit).toEqual(FALLBACK_LIMIT)
  })

  test("returns an empty catalogue instead of throwing on first run", async () => {
    const catalog = await catalogFor(base("down"), "sk-good", path.join(tmp, "cache-empty"))
    expect(catalog).toEqual({ models: {}, described: false })
  })
})

test("config hook injects the ckode provider, keeps only OpenCode's free provider besides it, and overrides user provider choices", async () => {
  const hooks = await plugin.server({} as never, { baseURL: base("litellm"), name: "ollama" })
  const cfg: {
    autoupdate: boolean
    enabled_providers: string[]
    disabled_providers: string[]
    provider: Record<string, { models?: object }>
  } = {
    autoupdate: true,
    enabled_providers: ["openai"],
    disabled_providers: ["ckode"],
    provider: { openai: {} },
  }
  process.env.CKODE_API_KEY = "sk-good"
  await hooks.config!(cfg as never)
  delete process.env.CKODE_API_KEY
  expect(cfg.autoupdate).toBe(false)
  expect(cfg.enabled_providers).toEqual(["ckode", "opencode"])
  expect(cfg.disabled_providers).toEqual([])
  expect(Object.keys(cfg.provider)).toEqual(["ckode"])
  expect(Object.keys(cfg.provider.ckode.models ?? {})).toHaveLength(2)
  expect((cfg.provider.ckode as { name?: string }).name).toBe("ollama")
})

test("config hook with no provider chosen leaves only OpenCode's free models", async () => {
  const hooks = await plugin.server({} as never, {})
  const cfg: { enabled_providers: string[]; provider: Record<string, object> } = { enabled_providers: ["openai"], provider: { openai: {} } }
  await hooks.config!(cfg as never)
  expect(cfg.enabled_providers).toEqual(["opencode"])
  expect(cfg.provider).toEqual({})
})

test("resolveName trims and tolerates absence", () => {
  expect(resolveName({ name: " anthropic " })).toBe("anthropic")
  expect(resolveName(undefined)).toBe("")
})

test("names the provider after its host", () => {
  expect(providerName("http://localhost:11434/v1")).toBe("localhost:11434")
  expect(providerName("https://gateway.example.com/v1")).toBe("gateway.example.com")
})
