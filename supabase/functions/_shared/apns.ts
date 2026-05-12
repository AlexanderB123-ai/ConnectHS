// APNs ES256 JWT signing + push send. The JWT is cached in module scope so
// every request inside the same warm function instance reuses it (Apple
// rejects fresh JWTs more aggressively than reused ones — see APNs error
// "TooManyProviderTokenUpdates").

import { create as createJWT } from "https://deno.land/x/djwt@v3.0.2/mod.ts"

export interface APNsConfig {
  keyId: string       // APNs Key ID (KID), 10 chars
  teamId: string      // Apple Developer Team ID, 10 chars
  privateKey: string  // .p8 file contents (PEM-encoded PKCS#8)
  bundleId: string    // app bundle id, e.g. com.connecths.ConnectHS
  environment: "sandbox" | "production"
}

export interface PushPayload {
  apnsToken: string
  title: string
  body: string
  threadId?: string
  deepLink: string
  badge?: number
}

export interface PushResult {
  status: number
  apnsToken: string
  isDead: boolean   // true on HTTP 410 — caller should delete the token
}

let cachedJWT: { token: string; expiresAt: number } | null = null
let cachedKey: CryptoKey | null = null
let cachedKeyFingerprint: string | null = null

export function configFromEnv(): APNsConfig {
  const env = Deno.env
  const required = ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID", "APNS_ENV"] as const
  for (const k of required) {
    if (!env.get(k)) throw new Error(`Missing env ${k}`)
  }
  return {
    keyId: env.get("APNS_KEY_ID")!,
    teamId: env.get("APNS_TEAM_ID")!,
    privateKey: env.get("APNS_PRIVATE_KEY")!,
    bundleId: env.get("APNS_BUNDLE_ID")!,
    environment: env.get("APNS_ENV") === "production" ? "production" : "sandbox"
  }
}

export async function sendAPNs(payload: PushPayload, cfg: APNsConfig): Promise<PushResult> {
  const token = await getOrCreateProviderToken(cfg)
  const host = cfg.environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com"

  const aps: Record<string, unknown> = {
    alert: { title: payload.title, body: payload.body },
    sound: "default"
  }
  if (payload.threadId) aps["thread-id"] = payload.threadId
  if (payload.badge !== undefined) aps.badge = payload.badge

  const body = JSON.stringify({ aps, deep_link: payload.deepLink })

  const response = await fetch(`https://${host}/3/device/${payload.apnsToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": cfg.bundleId,
      "apns-push-type": "alert",
      "content-type": "application/json"
    },
    body
  })

  // Drain the body so the connection is reusable.
  await response.body?.cancel()

  return {
    status: response.status,
    apnsToken: payload.apnsToken,
    isDead: response.status === 410
  }
}

async function getOrCreateProviderToken(cfg: APNsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJWT && cachedJWT.expiresAt > now + 60) return cachedJWT.token

  const fingerprint = `${cfg.keyId}:${cfg.teamId}:${cfg.privateKey.length}`
  if (!cachedKey || cachedKeyFingerprint !== fingerprint) {
    cachedKey = await crypto.subtle.importKey(
      "pkcs8",
      pemToArrayBuffer(cfg.privateKey),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"]
    )
    cachedKeyFingerprint = fingerprint
  }

  const token = await createJWT(
    { alg: "ES256", kid: cfg.keyId, typ: "JWT" },
    { iss: cfg.teamId, iat: now },
    cachedKey
  )
  cachedJWT = { token, expiresAt: now + 3500 }  // Apple recommends ~1h
  return token
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const stripped = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "")
  const binary = atob(stripped)
  const buffer = new ArrayBuffer(binary.length)
  const view = new Uint8Array(buffer)
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i)
  return buffer
}
