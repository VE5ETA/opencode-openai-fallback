import assert from "node:assert/strict"
import pluginModule, { testExports } from "../plugin/openai-auto-fallback.mjs"

const { createFallbackFetch, getProfileOrder, isLimitResponse } = testExports

assert.equal(typeof pluginModule.server, "function")
for (const [name, value] of Object.entries(await import("../plugin/openai-auto-fallback.mjs"))) {
  if (name === "default") continue
  assert.equal(name, "testExports")
  assert.equal(typeof value, "object")
}

const hooks = await pluginModule.server()
assert.equal(hooks.auth.provider, "openai")
assert.equal(typeof hooks.auth.loader, "function")

assert.deepEqual(getProfileOrder("pp"), ["pp", "ps", "sp", "ss"])
assert.deepEqual(getProfileOrder("ps"), ["ps", "sp", "ss", "pp"])
assert.deepEqual(getProfileOrder("unknown"), ["pp", "ps", "sp", "ss"])
assert.equal(isLimitResponse(429, ""), true)
assert.equal(isLimitResponse(400, "The usage limit has been reached"), true)
assert.equal(isLimitResponse(400, "insufficient_quota"), true)
assert.equal(isLimitResponse(400, "quota configuration missing"), false)
assert.equal(isLimitResponse(500, "server exploded"), false)

const attempts = []
const warnings = []
const originalWarn = console.warn
console.warn = (message) => warnings.push(String(message))

const profiles = {
  pp: { key: "pp", auth: { type: "oauth", access: "access-pp", refresh: "refresh-pp", expires: Date.now() + 60_000, accountId: "acct-pp" } },
  ps: { key: "ps", auth: { type: "oauth", access: "access-ps", refresh: "refresh-ps", expires: Date.now() + 60_000, accountId: "acct-ps" } },
  sp: { key: "sp", auth: { type: "oauth", access: "access-sp", refresh: "refresh-sp", expires: Date.now() + 60_000, accountId: "acct-sp" } },
  ss: { key: "ss", auth: { type: "oauth", access: "access-ss", refresh: "refresh-ss", expires: Date.now() + 60_000, accountId: "acct-ss" } },
}

const fallbackFetch = createFallbackFetch({
  selectedProfile: "pp",
  loadProfile: async (key) => profiles[key],
  saveProfile: async () => {},
  refreshProfile: async (profile) => profile.auth,
  fetchImpl: async (_url, init) => {
    const headers = new Headers(init.headers)
    const token = headers.get("authorization")?.replace("Bearer ", "")
    attempts.push({ token, accountId: headers.get("ChatGPT-Account-Id") })

    if (token === "access-pp" || token === "access-ps") {
      return new Response("The usage limit has been reached", { status: 429 })
    }

    return new Response("ok", { status: 200 })
  },
})

const response = await fallbackFetch("https://api.openai.com/v1/responses", {
  method: "POST",
  body: JSON.stringify({ model: "gpt-5.5" }),
})

assert.equal(response.status, 200)
assert.equal(await response.text(), "ok")
assert.deepEqual(attempts, [
  { token: "access-pp", accountId: "acct-pp" },
  { token: "access-ps", accountId: "acct-ps" },
  { token: "access-sp", accountId: "acct-sp" },
])
assert.deepEqual(warnings, [
  "[openai-auto-fallback] Primary personal hit a usage limit; trying next profile",
  "[openai-auto-fallback] Primary shared hit a usage limit; trying next profile",
])

let refreshedAuth
const refreshFetch = createFallbackFetch({
  selectedProfile: "ss",
  loadProfile: async () => ({ key: "ss", auth: { type: "oauth", access: "old", refresh: "refresh-ss", expires: Date.now() - 1 } }),
  saveProfile: async (_key, auth) => { refreshedAuth = auth },
  refreshProfile: async () => ({ type: "oauth", access: "fresh", refresh: "refresh-ss", expires: Date.now() + 60_000, accountId: "acct-fresh" }),
  fetchImpl: async (_url, init) => {
    const headers = new Headers(init.headers)
    assert.equal(headers.get("authorization"), "Bearer fresh")
    assert.equal(headers.get("ChatGPT-Account-Id"), "acct-fresh")
    return new Response("fresh ok", { status: 200 })
  },
})

assert.equal((await refreshFetch("https://api.openai.com/v1/responses", { method: "POST" })).status, 200)
assert.equal(refreshedAuth.access, "fresh")

const refreshFailureAttempts = []
const refreshFailureFetch = createFallbackFetch({
  selectedProfile: "pp",
  loadProfile: async (key) => {
    if (key === "pp") return { key, auth: { type: "oauth", access: "expired", refresh: "bad-refresh", expires: Date.now() - 1 } }
    if (key === "ps") return { key, auth: { type: "oauth", access: "access-ps", refresh: "refresh-ps", expires: Date.now() + 120_000, accountId: "acct-ps" } }
  },
  saveProfile: async () => {},
  refreshProfile: async () => { throw new Error("refresh failed") },
  fetchImpl: async (_url, init) => {
    const headers = new Headers(init.headers)
    refreshFailureAttempts.push(headers.get("authorization"))
    return new Response("ok", { status: 200 })
  },
})

assert.equal((await refreshFailureFetch("https://api.openai.com/v1/responses", { method: "POST" })).status, 200)
assert.deepEqual(refreshFailureAttempts, ["Bearer access-ps"])

const streamBodies = []
const streamFallbackFetch = createFallbackFetch({
  selectedProfile: "pp",
  loadProfile: async (key) => profiles[key],
  saveProfile: async () => {},
  refreshProfile: async (profile) => profile.auth,
  fetchImpl: async (_url, init) => {
    const headers = new Headers(init.headers)
    streamBodies.push(await new Response(init.body).text())
    if (headers.get("authorization") === "Bearer access-pp") {
      return new Response("usage limit reached", { status: 429 })
    }
    return new Response("stream ok", { status: 200 })
  },
})

const stream = new ReadableStream({
  start(controller) {
    controller.enqueue(new TextEncoder().encode("stream-body"))
    controller.close()
  },
})

assert.equal((await streamFallbackFetch("https://api.openai.com/v1/responses", { method: "POST", body: stream, duplex: "half" })).status, 200)
assert.deepEqual(streamBodies, ["stream-body", "stream-body"])

console.warn = originalWarn

console.log("PASS: openai auto fallback plugin rotates profiles on usage limits")
