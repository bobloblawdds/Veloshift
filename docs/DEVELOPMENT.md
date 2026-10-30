# Development

## Layout

- `Sources/Velox`: native SwiftUI interface, Bluetooth hardware client, session coordination, window placement, Carbon shift hotkeys, vector branding.
- `Sources/VeloxCore`: FTMS packet handling, Direct Connect TCP server, Click button decoding, road-load model, profiles, and keyboard state/scope logic.
- `Tests/VeloxChecks`: executable Foundation assertions, including loopback TCP checks. Run `swift run VeloxChecks`; this target does not use XCTest.
- `scripts`: app metadata/icon, build, and release packaging.

The product/executable is `Veloshift`. The preferences domain (`local.velox.kickr5`), saved window key, and trainer serial/network identity retain their original values so existing installations keep their settings and pairing identity. The advertised trainer name is `Veloshift KICKR v5`.

## Build

Requires macOS 14+ and a Swift 5.9-or-newer toolchain with the macOS SDK. No external packages are fetched.

```bash
swift build
swift run VeloxChecks
bash scripts/build-app.sh
```

`build-app.sh` produces a locally ad-hoc-signed `dist/Veloshift.app`. `VELOX_BUILD_DIR` can override Swift’s build directory. `VELOSHIFT_OUTPUT_DIR` can override the app/release output directory. A native build targets the current architecture; only arm64 has been tested.

## Checks and CI

The GitHub workflow builds release, runs all checks, verifies the app signature, packages the app, and uploads build artifacts on macOS. It has read-only repository permissions and does not publish releases automatically. Pull requests do not receive publishing credentials.

Unit/protocol checks do not verify Bluetooth firmware behavior, actual trainer resistance, permissions prompts, global keyboard event delivery to/from Zwift, or disconnect safety. Test those manually with the exact supported hardware. Confirm key release/repeat behavior and normal typing in other foreground apps.

## Architecture and scope

Veloshift owns the physical trainer’s Bluetooth control connection and exposes FTMS over a Wahoo Direct Connect-compatible TCP transport on port 36866 with Bonjour discovery. It accepts one controlling network client. The network transport is unauthenticated; use a trusted network. It does not act as a same-adapter Bluetooth peripheral.

Keep protocol command serialization, timeout handling, stale-telemetry release, and unchanged measured power forwarding when modifying the bridge. Do not replace measured rider power with simulated values outside the clearly labeled offline demo.

## Local data

Profiles and preferences are stored with UserDefaults. Activity entries are held in memory (up to 200). Diagnostic text is written only after the user chooses a destination. Do not commit real profiles, exports, device logs, credentials, signing keys, or build caches.
