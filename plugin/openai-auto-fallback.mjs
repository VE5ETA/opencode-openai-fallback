import fs from "node:fs/promises"
import path from "node:path"
import os from "node:os"
import { createHash, randomBytes } from "node:crypto"
import { createServer } from "node:http"

const CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
const ISSUER = "https://auth.openai.com"
const CODEX_API_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses"
const OAUTH_PORT = 1455
const OAUTH_DUMMY_KEY = "opencode-oauth-dummy-key"
const REFRESH_MARGIN_MS = 60_000

const PROFILE_DEFS = {
  pp: { name: "Primary personal", data: ".local/share-opencode-openai-primary-personal/opencode/auth.json" },
  ps: { name: "Primary shared", data: ".local/share-opencode-openai-primary-shared/opencode/auth.json" },
  sp: { name: "Secondary personal", data: ".local/share-opencode-openai-secondary-personal/opencode/auth.json" },
  ss: { name: "Secondary shared", data: ".local/share-opencode-openai-secondary-shared/opencode/auth.json" },
}

const PROFILE_ORDER = ["pp", "ps", "sp", "ss"]

function getProfileOrder(selected = process.env.OPENCODE_OPENAI_PROFILE || "pp") {
  const index = PROFILE_ORDER.indexOf(selected)
  if (index === -1) return [...PROFILE_ORDER]
  return [...PROFILE_ORDER.slice(index), ...PROFILE_ORDER.slice(0, index)]
}

function isLimitResponse(status, text) {
  if (status === 429) return true
  const lower = String(text || "").toLowerCase()
  return (
    lower.includes("usage limit") ||
    lower.includes("limit reached") ||
    lower.includes("rate limit") ||
    lower.includes("too many requests") ||
    lower.includes("free usage exceeded") ||
    lower.includes("gousagelimiterror") ||
    lower.includes("freeusagelimiterror") ||
    lower.includes("insufficient_quota") ||
    lower.includes("insufficient quota") ||
    lower.includes("quota exceeded") ||
    lower.includes("exceeded your quota")
  )
}

function createFallbackFetch(input) {
  const fetchImpl = input.fetchImpl || fetch
  const selectedProfile = input.selectedProfile || process.env.OPENCODE_OPENAI_PROFILE || "pp"

  return async function openaiFallbackFetch(requestInput, init) {
    let lastLimitResponse
    const prepared = await prepareRequest(requestInput, init)

    for (const key of getProfileOrder(selectedProfile)) {
      const profile = await input.loadProfile(key)
      if (!profile?.auth || profile.auth.type !== "oauth") continue

      let auth
      try {
        auth = await ensureFreshAuth(profile, input)
      } catch {
        console.warn(`[openai-auto-fallback] ${PROFILE_DEFS[key]?.name || key} auth refresh failed; trying next profile`)
        continue
      }

      const response = await fetchWithAuth(fetchImpl, prepared, auth)
      if (!response || response.status < 400) return response

      const text = await response.clone().text().catch(() => "")
      if (!isLimitResponse(response.status, text)) return response

      lastLimitResponse = new Response(text, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      })
      console.warn(`[openai-auto-fallback] ${PROFILE_DEFS[key]?.name || key} hit a usage limit; trying next profile`)
    }

    return lastLimitResponse || new Response("No authenticated OpenAI fallback profiles found", { status: 401 })
  }
}

async function ensureFreshAuth(profile, input) {
  if ((profile.auth.expires || 0) > Date.now() + REFRESH_MARGIN_MS) return profile.auth
  const next = await input.refreshProfile(profile)
  await input.saveProfile(profile.key, next)
  profile.auth = next
  return next
}

async function fetchWithAuth(fetchImpl, prepared, auth) {
  const headers = new Headers(prepared.headers)
  headers.delete("authorization")
  headers.delete("Authorization")
  headers.set("authorization", `Bearer ${auth.access}`)
  if (auth.accountId) headers.set("ChatGPT-Account-Id", auth.accountId)

  return fetchImpl(prepared.url, {
    ...prepared.init,
    headers,
  })
}

async function prepareRequest(requestInput, init) {
  const request = requestInput instanceof Request ? requestInput : undefined
  const parsed = request ? new URL(request.url) : requestUrl(requestInput)
  const url = parsed.pathname.includes("/v1/responses") || parsed.pathname.includes("/chat/completions")
    ? new URL(CODEX_API_ENDPOINT)
    : parsed

  const headers = new Headers(request?.headers)
  if (init?.headers) {
    new Headers(init.headers).forEach((value, key) => headers.set(key, value))
  }

  const method = init?.method || request?.method || "GET"
  const requestInit = request
    ? {
        method,
        redirect: init?.redirect || request.redirect,
        signal: init?.signal || request.signal,
      }
    : { method }

  for (const [key, value] of Object.entries(init || {})) {
    if (key !== "headers" && key !== "body" && key !== "method") requestInit[key] = value
  }

  if (method !== "GET" && method !== "HEAD") {
    if (init && Object.hasOwn(init, "body")) {
      requestInit.body = await replayableBody(init.body)
    } else if (request?.body) {
      requestInit.body = await request.clone().arrayBuffer()
    }
  }

  return { url, headers, init: requestInit }
}

function requestUrl(requestInput) {
  if (requestInput instanceof URL) return requestInput
  if (requestInput instanceof Request) return new URL(requestInput.url)
  return new URL(String(requestInput))
}

async function replayableBody(body) {
  if (typeof ReadableStream !== "undefined" && body instanceof ReadableStream) {
    return new Response(body).arrayBuffer()
  }
  return body
}

async function loadProfile(key) {
  const file = profilePath(key)
  try {
    const json = JSON.parse(await fs.readFile(file, "utf8"))
    if (!json.openai || json.openai.type !== "oauth") return undefined
    return { key, file, auth: json.openai }
  } catch {
    return undefined
  }
}

async function saveProfile(key, auth) {
  const file = profilePath(key)
  await fs.mkdir(path.dirname(file), { recursive: true })
  const json = await fs
    .readFile(file, "utf8")
    .then((value) => JSON.parse(value))
    .catch(() => ({}))
  json.openai = auth
  await fs.writeFile(file, JSON.stringify(json, null, 2))
}

function profilePath(key) {
  const def = PROFILE_DEFS[key]
  if (!def) throw new Error(`Unknown OpenAI profile ${key}`)
  return path.join(home(), ...def.data.split("/"))
}

function home() {
  return process.env.USERPROFILE || os.homedir()
}

async function refreshOAuthProfile(profile) {
  const response = await fetch(`${ISSUER}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: profile.auth.refresh,
      client_id: CLIENT_ID,
    }).toString(),
  })
  if (!response.ok) throw new Error(`Token refresh failed for ${profile.key}: ${response.status}`)

  const tokens = await response.json()
  return {
    type: "oauth",
    refresh: tokens.refresh_token || profile.auth.refresh,
    access: tokens.access_token,
    expires: Date.now() + (tokens.expires_in ?? 3600) * 1000,
    accountId: extractAccountId(tokens) || profile.auth.accountId,
  }
}

function extractAccountId(tokens) {
  for (const token of [tokens.id_token, tokens.access_token]) {
    const claims = parseJwtClaims(token)
    const account =
      claims?.chatgpt_account_id ||
      claims?.["https://api.openai.com/auth"]?.chatgpt_account_id ||
      claims?.organizations?.[0]?.id
    if (account) return account
  }
}

function parseJwtClaims(token) {
  if (!token || typeof token !== "string") return undefined
  const parts = token.split(".")
  if (parts.length !== 3) return undefined
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"))
  } catch {
    return undefined
  }
}

function generatePKCE() {
  const verifier = randomBytes(32).toString("base64url")
  const challenge = createHash("sha256").update(verifier).digest("base64url")
  return { verifier, challenge }
}

function generateState() {
  return randomBytes(32).toString("base64url")
}

function buildAuthorizeUrl(redirectUri, pkce, state) {
  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: redirectUri,
    scope: "openid profile email offline_access",
    code_challenge: pkce.challenge,
    code_challenge_method: "S256",
    id_token_add_organizations: "true",
    codex_cli_simplified_flow: "true",
    state,
    originator: "opencode",
  })
  return `${ISSUER}/oauth/authorize?${params.toString()}`
}

async function exchangeCodeForTokens(code, redirectUri, pkce) {
  const response = await fetch(`${ISSUER}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
      client_id: CLIENT_ID,
      code_verifier: pkce.verifier,
    }).toString(),
  })
  if (!response.ok) throw new Error(`Token exchange failed: ${response.status}`)
  return response.json()
}

function startOAuthServer() {
  let pending
  const server = createServer((req, res) => {
    const url = new URL(req.url || "/", `http://localhost:${OAUTH_PORT}`)
    if (url.pathname !== "/auth/callback") {
      res.writeHead(404)
      res.end("Not found")
      return
    }

    const error = url.searchParams.get("error_description") || url.searchParams.get("error")
    const code = url.searchParams.get("code")
    const state = url.searchParams.get("state")
    if (error) pending?.reject(new Error(error))
    else if (!code) pending?.reject(new Error("Missing authorization code"))
    else if (state !== pending?.state) pending?.reject(new Error("Invalid OAuth state"))
    else pending.resolve(code)

    res.writeHead(200, { "Content-Type": "text/html" })
    res.end("<!doctype html><title>OpenCode</title><body>Authorization complete. You can close this window.</body>")
  })

  return new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(OAUTH_PORT, () => {
      resolve({
        redirectUri: `http://localhost:${OAUTH_PORT}/auth/callback`,
        waitForCode(state) {
          return new Promise((resolveCode, rejectCode) => {
            pending = { state, resolve: resolveCode, reject: rejectCode }
          }).finally(() => server.close())
        },
      })
    })
  })
}

async function authorizeBrowser() {
  const oauth = await startOAuthServer()
  const pkce = generatePKCE()
  const state = generateState()
  const codePromise = oauth.waitForCode(state)
  return {
    url: buildAuthorizeUrl(oauth.redirectUri, pkce, state),
    instructions: "Complete authorization in your browser. This window can be closed afterward.",
    method: "auto",
    async callback() {
      const tokens = await exchangeCodeForTokens(await codePromise, oauth.redirectUri, pkce)
      return {
        type: "success",
        refresh: tokens.refresh_token,
        access: tokens.access_token,
        expires: Date.now() + (tokens.expires_in ?? 3600) * 1000,
        accountId: extractAccountId(tokens),
      }
    },
  }
}

async function OpenAIAutoFallbackPlugin() {
  return {
    auth: {
      provider: "openai",
      async loader(getAuth) {
        if (process.env.OPENCODE_OPENAI_AUTO_FALLBACK === "0") return {}
        const current = await getAuth()
        if (current?.type !== "oauth") return {}
        const available = []
        for (const key of PROFILE_ORDER) {
          const profile = await loadProfile(key)
          if (profile) available.push(profile)
        }
        if (!available.length) return {}
        return {
          apiKey: OAUTH_DUMMY_KEY,
          fetch: createFallbackFetch({
            selectedProfile: process.env.OPENCODE_OPENAI_PROFILE || "pp",
            loadProfile,
            saveProfile,
            refreshProfile: refreshOAuthProfile,
          }),
        }
      },
      methods: [
        {
          label: "ChatGPT Pro/Plus (browser)",
          type: "oauth",
          authorize: authorizeBrowser,
        },
        {
          label: "Manually enter API Key",
          type: "api",
        },
      ],
    },
  }
}

export const testExports = {
  PROFILE_ORDER,
  getProfileOrder,
  isLimitResponse,
  createFallbackFetch,
}

export default {
  id: "opencode-openai-fallback",
  server: OpenAIAutoFallbackPlugin,
}
