# Releasing Veloshift

## Prepare a preview

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `scripts/Info.plist`, plus displayed version strings and release notes.
2. Run `bash scripts/package-release.sh` on the architecture you will distribute.
3. Inspect the ZIP contents and try the app on a separate Mac/user account with a browser-downloaded ZIP. Local launch tests do not reproduce Gatekeeper quarantine.
4. Test KICKR v5 + Click 2 + Zwift pairing, resistance, coasting, ERG, stop/disconnect behavior, and single-key shifting with Zwift foregrounded. Describe untested areas in release notes.
5. Commit the source and ensure CI passes.

The package script produces `dist/Veloshift-VERSION-macOS-ARCH.zip` and a matching `.sha256` file. It runs the 29 check groups and verifies the local code signature before creating the archive. The ZIP includes the app, installation notes, and the project license if one has been selected.

## Publish

Authenticate the official GitHub CLI on your own Mac (`gh auth login`). From the repository root, create a preview release, using the exact assets generated above:

```bash
gh release create v0.6.0 \
  dist/Veloshift-0.6.0-macOS-arm64.zip \
  dist/Veloshift-0.6.0-macOS-arm64.zip.sha256 \
  --target main --title "Veloshift 0.6.0 preview" \
  --prerelease --notes-file docs/releases/v0.6.0.md
```

Creating the release tag associates it with the committed source. Do not publish unrelated local files or replace an existing version’s assets without explaining the change. Preview releases are listed under Releases but may not become GitHub’s Latest release. The CI workflow uploads build artifacts; it does not create releases.

## Signing and notarization

Current previews are ad-hoc signed only. Users may need the per-app Open Anyway option described in [Apple’s guidance](https://support.apple.com/en-us/102445). Do not instruct users to disable system security globally.

For a smoother public installation experience, obtain an Apple Developer ID Application certificate, sign with hardened runtime and a timestamp, notarize using `xcrun notarytool`, and staple the notarization ticket before packaging. That requires the maintainer’s Apple Developer account and signing credentials; these are not supplied by this repository. Store credentials in a secure keychain or scoped CI secrets, never in Git.
