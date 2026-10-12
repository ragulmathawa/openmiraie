# MirAIe cloud protocol — reverse-engineering notes

Artifact: `MirAIe.apk` — `com.panasonic.in.miraie` v01.4.32 (versionCode 231301432), minSdk 26, targetSdk 35
SHA-256: `62a36f534b6e38802e9a1ff2138a6342d1328e0f0a4928ce37ba2299e2f867a1`

Tooling / provenance (REA 6.4.0):

- `inspect_artifact` — evidence `ev_d1deaffea0f94d2309272b26d7676fa4ebfb6073253f31bcc13d73993efe3eca`
- `inspect_android_package` (jadx provider) — evidence `ev_25c7af8d486f47442617417ae10bbe309c0df2f1206084409d7bd0ee1d05f034`
- `inspect_android_method` MQTTService.doConnect — evidence `ev_65b2539a5a58285ecb90a4de0889b7f738a40634d9df468e30bda4c796d6146d`
- apktool 3.0.3, jadx-headless-mcp 0.7.1 (SHA-256 `6e5eacf5…75`), jadx 1.5.6 full decompile (21,308 classes)

All findings are static-analysis evidence; they were not verified against the live backend.

## 1. Cloud endpoints (from `BuildConfig`)

| Role | Value |
| --- | --- |
| REST API | `https://app.miraie.in/simplifi/v1/` |
| Auth API | `https://auth.miraie.in/simplifi/v1/` |
| Identity API | `https://iam.miraie.in/api/identity/v1/` |
| MQTT broker | `ssl://mqtt.miraie.in:8883` (TLS) |
| User OAuth client id | `292d99d7-5623-4157-8a71-846ee3ff5dbf` |
| Vetaar/Anchor API | `https://vetaar-anchor.com/VCAPI3/` |

## 2. Authentication

```
POST https://auth.miraie.in/simplifi/v1/userManagement/login
{ "mobile": "<10-digit>"   // or "email": "<addr>"
, "password": "<password>"
, "clientId": "292d99d7-5623-4157-8a71-846ee3ff5dbf"
, "scope": "an_<random 0-999999999>" }

200 → { "accessToken": "...", "refreshToken": "...", "expiresIn": <seconds>, "userId": "..." }
```

- Refresh: `POST .../userManagement/tokenRefresh` with `{ "clientId": "<same>", "token": "<refreshToken>" }` → same `LoginResponse`.
- Logout: `POST .../userManagement/logout` with `{ "clientId": "<same>" }`.
- Every `app.miraie.in` call: `Authorization: Bearer <accessToken>`; on 401 the app refreshes (OkHttp `TokenAuthenticator`) and retries.
- Tokens are stored in `UserPrefsManager` (`refresh_token`, access-token + expiry).

## 3. Home / device discovery

```
GET https://app.miraie.in/simplifi/v1/homeManagement/homes        (Bearer token)
→ [ {
    "id": "<homeId>", "homeName": "...", "metaTopic": "<home topic prefix>",
    "primaryUser": "<email>", "secondaryUsers": [...],
    "spaces": [ { "spaceId", "spaceName", "spaceType",
        "devices": [ { "deviceId", "deviceName", "modelId", "category",
                       "topic": ["<device mqtt prefix>", ...],   // ← per-device MQTT prefix(es)
                       "password", "virtualAppliance", "sleepProfiles" } ] } ] } ]
```

Device capability model (defines the exact wire keys):

```
GET .../deviceManagement/deviceModels/modelId/{modelId}
→ { "controlCapabilities": [...], "statusCapabilitiesV2": [...], "configCapabilities": [...] }
   each: { "capability": "ACMode", "attributes": [ { "key": "acmd", "values": [...] } ], "MinFWVersion": ... }
```

- The wire key of a capability is `attributes[0].key` (e.g. `acmd`, `actmp`, `acfs`); `ki` is a fixed per-capability index (below).
- REST status: `GET .../deviceManagement/devices/{deviceId}/mobile/status` → JSON with `onlineStatus` and capability keys (e.g. `"ps":"on"`).

## 4. MQTT connection

| Parameter | Value |
| --- | --- |
| Broker | `ssl://mqtt.miraie.in:8883` (equivalently `mqtts`, MQTT 3.1.1 via Eclipse Paho) |
| Username | `homeId` (app brand is empty; device-side is `homeId@brand`) |
| Password | user `accessToken` |
| Clean session | `true` |
| Client id | any unique string; app uses `"AN" + sha256(userId + "##" + homeId)[:16] + <installTime last 5>` |
| Reconnect | app handles manually with 2 s backoff (max 64 s) |
| Subscribe | `<metaTopic>/#` at QoS 0 for home-level events; device `status` topics per device |

Per-device topics (`device.topic[]` prefix from the homes response):

```
<prefix>/control     publish commands (or /tcontrol for Intesis / Panasonic Comfort Cloud ACs)
<prefix>/status      device state (same capability keys as commands)
<prefix>/pstatus     periodic state        <prefix>/rstate   realtime state
<prefix>/fcontrol    firmware control      <prefix>/fstatus  firmware status
<prefix>/aicontrol   AI control            <prefix>/aistatus AI status
<prefix>/onbs        onboarding state      <prefix>/pwC      power consumption
```

## 5. Control payloads

One JSON object per publish. Each capability adds `key: value` plus its `ki`; the MQTT layer then adds:

```json
{ "ps": "on", "cnt": "an", "sid": "17" }
```

- `cnt` = source/controller (`"an"` = Android app, `"gva"` = Google Home voice).
- `sid` = monotonically increasing sequence id (string).
- Multiple capabilities may be batched in one object.

Confirmed commands (AC):

| Action | Payload | Notes |
| --- | --- | --- |
| Power on/off | `{"ps":"on","ki":1}` | `"off"` to turn off |
| Mode | `{"acmd":"cool","ki":0}` | `auto`, `cool`, `heat`, `dry`, `fan` |
| Temperature | `{"actmp":"24.0","ki":2}` | one decimal string; typical range 16–30 °C |
| Fan speed | `{"acfs":"auto","ki":4}` | `auto`, `high`, `medium`, `low`, `quiet` |

Capability → `ki` (from `BaseCapability.Type`; wire key from model attributes):

`0 ACMode (acmd) · 1 PowerStatus (ps) · 2 ACTemperature (actmp) · 3 PowerfulMode · 4 ACFanSpeed (acfs) · 5 VerticalSwing · 6 HorizontalSwing · 7 NanoeG · 8 DisplayControl · 9 EvaporatorClean · 10 ECOMode · 12 SleepProfile · 13 JetStream · 14 ACTimer · 15 FilterDustLevel · 16 Ionizer · 17 MotionSensor · 18 TurboMode · 19 GenMode · 21 EcoNavi · 23 NanoeX · 28 Convertible · 29 LaundryMode · 257 ACModeTemperature (Comfort Cloud ACs)`

Status messages on `<prefix>/status` use the same keys; response examples observed in code: `ps`, `actmp`, `acmd`, `acfs`, plus `onlineStatus`, sensors, faults.

## 6. REST control fallback (used by geofence + voice assistants)

```
POST https://app.miraie.in/simplifi/v1/deviceManagement/control
Authorization: Bearer <accessToken>
Content-Type: application/json

{ "deviceId": "<deviceId>",
  "control_params": { "ps": "on", "cnt": "gva", "ki": 1, "sid": "11" } }
→ 2xx = accepted
```

Useful for a first end-to-end proof before wiring MQTT. Status via the `mobile/status` GET above.

## 7. Blueprint for your own app

Minimal flow:

1. **Login** (`auth.miraie.in`) with the user's mobile/email + password and the client id above; keep `refreshToken`, refresh on 401/expiry.
2. **Discover**: `GET homes` → home `id` + `metaTopic`; pick the AC device → `deviceId`, `topic[]` prefix, `modelId`.
3. **Model**: `GET deviceModels/modelId/{modelId}` → build the key/`ki` map (or hardcode the confirmed AC keys).
4. **MQTT**: connect `mqtts://mqtt.miraie.in:8883`, username = `homeId`, password = current `accessToken`; subscribe `<metaTopic>/#` and `<prefix>/status`.
5. **Control**: publish `{"ps":"on","ki":1}` etc. to `<prefix>/control` (or use the REST fallback). Reconnect with the refreshed token when it expires.

Stack suggestions: Python (`paho-mqtt` + `httpx`) or Node (`mqtt` + `undici`) for a local controller; token persistence in a small config file.

Gotchas:

- The MQTT password **is** the access token — reconnect after refresh.
- Use a unique client id per process; `cleanSession true`.
- Comfort Cloud / Intesis ACs use `<prefix>/tcontrol` and `ACModeTemperature` (`ki` 257).
- Value sets (modes, fan speeds, temp range) can vary by model; read them from `controlCapabilities.attributes`.
- Endpoints/clients are server-side and can change; keep them configurable.

## 8. Legal note

This analysis is for personal interoperability with your own AC and MirAIe account. Do not redistribute Panasonic code, assets, or credentials. The middleware used (jadx-headless-mcp) is Apache-2.0; REA is MIT.
