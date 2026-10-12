# MirAIe Bar

A native macOS menu bar app — plus a small Node.js reference CLI — for controlling Panasonic MirAIe air conditioners through the MirAIe cloud.

The cloud protocol (authentication, home/device discovery, MQTT topics, control payloads, energy stats) was derived from static analysis of the official Android app and is documented in [docs/miraie-cloud-protocol.md](docs/miraie-cloud-protocol.md).

> Unofficial project. Not affiliated with or endorsed by Panasonic. Use it with your own MirAIe account. No part of the official app is included in this repository.

## Features

- Menu bar AC control: power, mode, temperature, fan, vertical swing, and extra toggles (Powerful, Eco, Display, Evaporator Clean) — capability-driven per device model
- Live state over MQTT (TLS), with reconnect on wake/network change and automatic token refresh
- Energy consumption chart (day / week / month) and live device info (signal, firmware, filter level, and more) in Settings
- Multiple homes and devices, local rename/hide, °C/°F, launch at login
- `MirAIeKit` Swift package with unit tests, and a `miraie-probe` CLI for direct protocol checks

## Repository layout

```
macos/            macOS app + Swift package
  MirAIeKit/      Swift package: auth, REST, MQTT, command encoding, tests, probe CLI
  MirAIeBar/      SwiftUI menu bar app
  project.yml     XcodeGen project definition
src/ bin/         Node.js reference CLI (login, homes, status, listen, control)
docs/             Reverse-engineered protocol documentation
```

## Build the macOS app

Requirements: macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd macos
xcodegen generate
xcodebuild -project MirAIeBar.xcodeproj -scheme MirAIeBar -configuration Release build
```

The build is ad-hoc signed. Launch the produced `MirAIeBar.app` from the build products directory (see `xcodebuild -showBuildSettings` for `BUILT_PRODUCTS_DIR`), or copy it to `~/Applications`.

On first launch, sign in with your MirAIe account (mobile or email + password). Credentials are stored locally at `~/.config/openmiraie/credentials.json` with owner-only permissions (0600). No credentials are sent anywhere except the MirAIe cloud endpoints.

## Releases

Tagged releases (`v*`) are built by GitHub Actions and attached to the GitHub release as a zip. The app is unsigned/ad-hoc signed, so on first launch macOS may require right-click → Open, or:

```bash
xattr -dr com.apple.quarantine MirAIeBar.app
```

## Swift package and probe CLI

```bash
cd macos/MirAIeKit
swift test
swift run miraie-probe status --device "Living Room AC"
swift run miraie-probe listen --seconds 30
swift run miraie-probe control --power on
swift run miraie-probe power --grain Daily
```

## Node.js CLI

Requires Node 20+. Shares the same credentials file.

```bash
npm install
node bin/openmiraie.js login
node bin/openmiraie.js homes
node bin/openmiraie.js status
node bin/openmiraie.js listen --seconds 30
node bin/openmiraie.js control --power on --mode cool --temp 24 --fan auto
```

## Disclaimer

This is an interoperability project for personal use with devices you own. Endpoints, client identifiers, and payloads may change at any time without notice. The software is provided as-is, without warranty of any kind.

## License

MIT — see [LICENSE](LICENSE).
