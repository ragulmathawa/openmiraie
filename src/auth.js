import {
  ENDPOINTS,
  IAM_CLIENT_ID,
  loadCredentials,
  saveCredentials,
} from "./config.js";

async function postJson(url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
  }
  return text ? JSON.parse(text) : null;
}

export async function login({ mobile, email, password }) {
  const body = {
    clientId: IAM_CLIENT_ID,
    password,
    scope: `an_${Math.floor(Math.random() * 1e9)}`,
  };
  if (mobile) body.mobile = mobile;
  else body.email = email;
  const data = await postJson(`${ENDPOINTS.auth}/userManagement/login`, body);
  if (!data?.accessToken) throw new Error("login response missing accessToken");
  const creds = {
    identifier: mobile ?? email,
    userId: data.userId,
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAt: Date.now() + (Number(data.expiresIn) || 3600) * 1000,
  };
  saveCredentials(creds);
  return creds;
}

export async function refreshCredentials(creds) {
  if (!creds?.refreshToken) {
    throw new Error("no refresh token; run login again");
  }
  const data = await postJson(`${ENDPOINTS.auth}/userManagement/tokenRefresh`, {
    clientId: IAM_CLIENT_ID,
    token: creds.refreshToken,
  });
  creds.accessToken = data.accessToken;
  if (data.refreshToken) creds.refreshToken = data.refreshToken;
  creds.expiresAt = Date.now() + (Number(data.expiresIn) || 3600) * 1000;
  saveCredentials(creds);
  return creds;
}

export async function ensureToken() {
  const creds = loadCredentials();
  if (!creds) throw new Error("not logged in; run: openmiraie login");
  if (Date.now() > creds.expiresAt - 60000) return refreshCredentials(creds);
  return creds;
}

function requestInit(creds, init) {
  const headers = {
    authorization: `Bearer ${creds.accessToken}`,
    ...(init?.body ? { "content-type": "application/json" } : {}),
    ...(init?.headers ?? {}),
  };
  return { ...init, headers };
}

export async function authedFetch(path, init = {}) {
  let creds = await ensureToken();
  const url = `${ENDPOINTS.api}/${path}`;
  let res = await fetch(url, requestInit(creds, init));
  if (res.status === 401) {
    creds = await refreshCredentials(creds);
    res = await fetch(url, requestInit(creds, init));
  }
  return res;
}

export async function authedJson(path) {
  const res = await authedFetch(path);
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
  }
  return text ? JSON.parse(text) : null;
}
