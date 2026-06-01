import { getStore } from "@netlify/blobs";
import type { Config, Context } from "@netlify/functions";
import { pbkdf2Sync, randomBytes, timingSafeEqual } from "node:crypto";

const MODES = ["sixshot", "tracking", "tracking_fast", "reaction"];
const USERS_STORE = "shoot-training-users";
const SCORES_STORE = "shoot-training-scores";
const TOKEN_TTL_MS = 1000 * 60 * 60 * 24 * 14;

type UserRecord = {
  username: string;
  salt: string;
  passwordHash: string;
  token?: string;
  tokenExpiresAt?: number;
};

type ScoreRecord = {
  username: string;
  score: number;
  updatedAt: string;
};

export default async (req: Request, context: Context) => {
  if (req.method === "OPTIONS") {
    return json({ ok: true });
  }

  try {
    const action = context.params.action;
    if (req.method === "POST" && action === "register") {
      return register(await req.json());
    }
    if (req.method === "POST" && action === "login") {
      return login(await req.json());
    }
    if (req.method === "POST" && action === "submit-score") {
      return submitScore(await req.json());
    }
    if (req.method === "GET" && action === "leaderboard") {
      const mode = new URL(req.url).searchParams.get("mode") ?? "sixshot";
      return leaderboard(mode);
    }
    if (req.method === "GET" && action === "leaderboards") {
      return leaderboards();
    }
    return json({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: "server_error" }, 500);
  }
};

export const config: Config = {
  path: "/api/:action",
};

async function register(body: any): Promise<Response> {
  const username = cleanUsername(body.username);
  const password = cleanPassword(body.password);
  if (!username || !password) {
    return json({ ok: false, error: "invalid_credentials" }, 400);
  }

  const users = getStore({ name: USERS_STORE, consistency: "strong" });
  const key = userKey(username);
  const existing = await users.get(key, { type: "json" }) as UserRecord | null;
  if (existing) {
    return json({ ok: false, error: "username_taken" }, 409);
  }

  const salt = randomBytes(16).toString("hex");
  const passwordHash = hashPassword(password, salt);
  const user: UserRecord = { username, salt, passwordHash };
  await users.setJSON(key, user);
  return json({ ok: true, username });
}

async function login(body: any): Promise<Response> {
  const username = cleanUsername(body.username);
  const password = cleanPassword(body.password);
  if (!username || !password) {
    return json({ ok: false, error: "invalid_credentials" }, 400);
  }

  const users = getStore({ name: USERS_STORE, consistency: "strong" });
  const key = userKey(username);
  const user = await users.get(key, { type: "json" }) as UserRecord | null;
  if (!user || !verifyPassword(password, user.salt, user.passwordHash)) {
    return json({ ok: false, error: "login_failed" }, 401);
  }

  user.token = randomBytes(32).toString("hex");
  user.tokenExpiresAt = Date.now() + TOKEN_TTL_MS;
  await users.setJSON(key, user);
  return json({ ok: true, username, token: user.token });
}

async function submitScore(body: any): Promise<Response> {
  const token = typeof body.token === "string" ? body.token : "";
  const mode = typeof body.mode === "string" ? body.mode : "";
  const score = Math.floor(Number(body.score));
  if (!MODES.includes(mode) || !Number.isFinite(score)) {
    return json({ ok: false, error: "invalid_score" }, 400);
  }

  const user = await userFromToken(token);
  if (!user) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const scores = getStore({ name: SCORES_STORE, consistency: "strong" });
  const key = scoreKey(mode, user.username);
  const previous = await scores.get(key, { type: "json" }) as ScoreRecord | null;
  const best = Math.max(score, previous?.score ?? Number.NEGATIVE_INFINITY);
  await scores.setJSON(key, {
    username: user.username,
    score: best,
    updatedAt: new Date().toISOString(),
  });
  return json({ ok: true, mode, username: user.username, score: best });
}

async function leaderboard(mode: string): Promise<Response> {
  if (!MODES.includes(mode)) {
    return json({ ok: false, error: "invalid_mode" }, 400);
  }
  return json({ ok: true, mode, scores: await topScores(mode) });
}

async function leaderboards(): Promise<Response> {
  const result: Record<string, ScoreRecord[]> = {};
  for (const mode of MODES) {
    result[mode] = await topScores(mode);
  }
  return json({ ok: true, leaderboards: result });
}

async function topScores(mode: string): Promise<ScoreRecord[]> {
  const scores = getStore({ name: SCORES_STORE, consistency: "strong" });
  const { blobs } = await scores.list({ prefix: `${mode}/` });
  const rows: ScoreRecord[] = [];
  for (const blob of blobs) {
    const score = await scores.get(blob.key, { type: "json" }) as ScoreRecord | null;
    if (score) rows.push(score);
  }
  return rows.sort((a, b) => b.score - a.score).slice(0, 10);
}

async function userFromToken(token: string): Promise<UserRecord | null> {
  if (!token) return null;
  const users = getStore({ name: USERS_STORE, consistency: "strong" });
  const { blobs } = await users.list();
  for (const blob of blobs) {
    const user = await users.get(blob.key, { type: "json" }) as UserRecord | null;
    if (user?.token === token && (user.tokenExpiresAt ?? 0) > Date.now()) {
      return user;
    }
  }
  return null;
}

function cleanUsername(value: unknown): string {
  if (typeof value !== "string") return "";
  const username = value.trim().toLowerCase();
  return /^[a-z0-9_]{3,18}$/.test(username) ? username : "";
}

function cleanPassword(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.length >= 6 && value.length <= 64 ? value : "";
}

function userKey(username: string): string {
  return `${username}.json`;
}

function scoreKey(mode: string, username: string): string {
  return `${mode}/${username}.json`;
}

function hashPassword(password: string, salt: string): string {
  return pbkdf2Sync(password, salt, 120000, 32, "sha256").toString("hex");
}

function verifyPassword(password: string, salt: string, expectedHash: string): boolean {
  const actual = Buffer.from(hashPassword(password, salt), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    },
  });
}
