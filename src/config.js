import { homedir } from "node:os";
import { join } from "node:path";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";

export const ENDPOINTS = {
  api: process.env.OPENMIRAIE_API ?? "https://app.miraie.in/simplifi/v1",
  auth: process.env.OPENMIRAIE_AUTH ?? "https://auth.miraie.in/simplifi/v1",
  mqtt: process.env.OPENMIRAIE_MQTT ?? "mqtts://mqtt.miraie.in:8883",
};

export const IAM_CLIENT_ID = "292d99d7-5623-4157-8a71-846ee3ff5dbf";

export const AC_CATEGORIES = new Set([
  "AC",
  "RAC",
  "CAC",
  "TAC",
  "MAC",
  "IAC",
  "PAC",
]);

export const CONTROL_KEYS = {
  power: { key: "ps", ki: 1 },
  mode: { key: "acmd", ki: 0 },
  temp: { key: "actmp", ki: 2 },
  fan: { key: "acfs", ki: 4 },
};

export const CONTROL_VALUES = {
  mode: new Set(["auto", "cool", "heat", "dry", "fan"]),
  fan: new Set(["auto", "high", "medium", "low", "quiet"]),
};

const configDir = join(
  process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"),
  "openmiraie",
);

export const credentialsPath = join(configDir, "credentials.json");

export function loadCredentials() {
  if (!existsSync(credentialsPath)) return null;
  try {
    return JSON.parse(readFileSync(credentialsPath, "utf8"));
  } catch {
    throw new Error(`cannot parse ${credentialsPath}; run logout then login`);
  }
}

export function saveCredentials(creds) {
  mkdirSync(configDir, { recursive: true, mode: 0o700 });
  writeFileSync(credentialsPath, `${JSON.stringify(creds, null, 2)}\n`, {
    mode: 0o600,
  });
  chmodSync(credentialsPath, 0o600);
}

export function clearCredentials() {
  if (existsSync(credentialsPath)) rmSync(credentialsPath);
}
