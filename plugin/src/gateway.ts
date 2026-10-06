/**
 * Any OpenAI-compatible server: a hosted LiteLLM-style gateway or a local one
 * such as Ollama. Hosted gateways scope model access per key, so the server is
 * the only thing that knows which models a given key may use.
 */

export const PROVIDER_ID = "ckode"
/** OpenCode's own provider; without a key it offers only the free models, which ckode keeps available. */
export const FREE_PROVIDER_ID = "opencode"
export const API_KEY_ENV = "CKODE_API_KEY"

/** What the provider is called in the UI: the host that was configured. */
export function providerName(baseURL: string) {
  try {
    return new URL(baseURL).host
  } catch {
    return baseURL
  }
}

/**
 * Used when /v1/model/info does not report a model's limits. They matter more
 * than they look: /v1 does no context trimming, so a zero or wrong limit means
 * the client never compacts and a long session fails outright.
 */
export const FALLBACK_LIMIT = { context: 200_000, output: 16_000 }

/** No gateway call may block a user indefinitely; the host is VPN-gated and hangs rather than refusing. */
const TIMEOUT_MS = 5_000

export type ModelConfig = {
  name: string
  tool_call: boolean
  attachment?: true
  modalities?: { input: ("text" | "image" | "pdf")[]; output: "text"[] }
  limit: { context: number; output: number }
  cost?: { input: number; output: number; cache_read: number; cache_write: number }
}

export type Catalog = {
  models: Record<string, ModelConfig>
  /** True when /v1/model/info answered, so limits and prices are real rather than defaulted. */
  described: boolean
}

type ModelInfo = {
  model_name?: string
  model_info?: {
    max_input_tokens?: number
    max_output_tokens?: number
    input_cost_per_token?: number
    output_cost_per_token?: number
    cache_read_input_token_cost?: number
    cache_creation_input_token_cost?: number
    mode?: string
    supports_function_calling?: boolean
    supports_vision?: boolean
    supports_pdf_input?: boolean
  }
}

/** LiteLLM modes that can drive a coding agent; anything else reported (transcription, embedding, image) cannot. */
const AGENT_MODES = new Set(["chat", "responses"])

/** Empty and whitespace count as absent: `CKODE_API_KEY=` is the normal shape of a .env placeholder. */
export function keyFromEnv(env: Record<string, string | undefined> = process.env) {
  const value = env[API_KEY_ENV]?.trim()
  return value ? value : undefined
}

/**
 * Loads the models this key may use. Throws when /v1/models fails, because an
 * empty catalogue makes OpenCode silently drop the provider and the caller needs
 * to know why. /v1/model/info is optional: a merely OpenAI-compatible host 404s.
 */
export async function loadCatalog(baseURL: string, key: string | undefined): Promise<Catalog> {
  const response = await get(baseURL, "/models", key)
  if (!response.ok) throw new Error(`GET /models: ${response.status} ${response.statusText}`)
  const body = (await response.json()) as { data?: { id?: string }[] }
  const info = await modelInfo(baseURL, key)

  // Prefer the mode /v1/model/info reports. Without one, the id is all there is,
  // so fall back to dropping embeddings by name and keeping the rest.
  const ids = (body.data ?? [])
    .map((entry) => entry.id)
    .filter((id): id is string => !!id && !id.includes("embedding"))
    .filter((id) => {
      const mode = info.get(id)?.mode
      return !mode || AGENT_MODES.has(mode)
    })

  return {
    described: info.size > 0,
    models: Object.fromEntries(ids.map((id) => [id, describe(id, info.get(id))])),
  }
}

function describe(id: string, info: ModelInfo["model_info"]): ModelConfig {
  const base = {
    name: id,
    // Only an explicit false disables tools; an unreported capability is assumed present.
    tool_call: info?.supports_function_calling !== false,
    ...attachments(info),
    limit: {
      context: info?.max_input_tokens ?? FALLBACK_LIMIT.context,
      output: info?.max_output_tokens ?? FALLBACK_LIMIT.output,
    },
  }
  // A zero price is indistinguishable from an unpriced model, so only claim a
  // cost when the gateway actually reported one side of it.
  if (info?.input_cost_per_token == null && info?.output_cost_per_token == null) return base
  return {
    ...base,
    cost: {
      input: perMillion(info.input_cost_per_token),
      output: perMillion(info.output_cost_per_token),
      cache_read: perMillion(info.cache_read_input_token_cost),
      cache_write: perMillion(info.cache_creation_input_token_cost),
    },
  }
}

function attachments(info: ModelInfo["model_info"]): Pick<ModelConfig, "attachment" | "modalities"> {
  const input = [
    ...(info?.supports_vision ? (["image"] as const) : []),
    ...(info?.supports_pdf_input ? (["pdf"] as const) : []),
  ]
  if (!input.length) return {}
  return { attachment: true, modalities: { input: ["text", ...input], output: ["text"] } }
}

/**
 * The gateway prices per token; OpenCode's session accounting multiplies by
 * tokens and divides by a million, so it wants per-million. Unscaled, spend
 * reads as $0.00 forever. Rounded, because 0.0000004 * 1e6 is 0.39999999999999997.
 */
export function perMillion(value: number | undefined) {
  if (value == null) return 0
  return Math.round(value * 1e12) / 1e6
}

async function modelInfo(baseURL: string, key: string | undefined) {
  const response = await get(baseURL, "/model/info", key).catch(() => undefined)
  if (!response?.ok) return new Map<string, ModelInfo["model_info"]>()
  const body = (await response.json().catch(() => ({}))) as { data?: ModelInfo[] }
  return new Map(
    (body.data ?? [])
      .filter((entry) => entry.model_name && entry.model_info)
      .map((entry) => [entry.model_name!, entry.model_info]),
  )
}

function get(baseURL: string, pathname: string, key: string | undefined) {
  return fetch(`${baseURL.replace(/\/+$/, "")}${pathname}`, {
    headers: {
      accept: "application/json",
      ...(key ? { authorization: `Bearer ${key}` } : {}),
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  })
}
