# maintainer release signing

This document is for maintainers who publish official releases. Contributors and self-hosters do not need
these credentials.

Bettercast has two signing paths:

| build | identity | hardened runtime | notarization |
| --- | --- | --- | --- |
| Debug / `Bettercast Dev.app` | unsigned by default; Apple Development optional | off | no |
| Release | Developer ID Application | on | yes |

Debug and release use separate bundle identifiers. Debug is for local development and permissions; release
is the artifact distributed outside the Mac App Store. The release path follows Apple's Developer ID and
notary service requirements.

## 1. developer account setup

Create a **Developer ID Application** certificate in the Apple Developer account. Do not use Apple
Distribution, Apple Development, ad hoc, or a self-signed certificate for a distributed macOS app.

The project currently uses team ID `Z66C58Z3RC`, detected from the installed Apple Distribution identity.
Change `DEVELOPMENT_TEAM` in `project.yml` if the app belongs to another team, then run:

```sh
xcodegen generate
```

Install the Developer ID certificate and its private key in the login keychain. Verify both identities:

```sh
security find-identity -v -p codesigning
```

The output must contain:

```text
Apple Development: … (Z66C58Z3RC)
Developer ID Application: … (Z66C58Z3RC)
```

If enabled, the Apple Development identity signs local Debug builds. The Developer ID identity signs
releases. Never commit certificates, private keys, provisioning profiles, or API keys.

## 2. local notarization credentials

Create a **Team Key** under App Store Connect → Users and Access → Integrations → App Store Connect API.
Use the **Developer** access role, download its `.p8` private key once, and store it in a protected local
directory. Then save a notarytool keychain profile; the private key stays in Keychain
Services instead of being passed in every build command:

```sh
xcrun notarytool store-credentials bettercast-notary \
  --key ~/Library/Developer/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

Check the profile without submitting anything:

```sh
xcrun notarytool history --keychain-profile bettercast-notary
```

The first command may return an empty history. That is a valid credential check; authentication errors
are not.

## 3. local builds

The default local Debug build is unsigned and needs no Apple account:

```sh
make build
```

Xcode can use automatic Apple Development signing when an account is configured.

A local release build requires the Developer ID certificate and the notary profile:

```sh
./build-dmg.sh
```

The script performs this sequence:

1. Build the Release app with Developer ID Application signing and a secure timestamp.
2. Verify the code signature.
3. Zip and submit the app with `notarytool`.
4. Wait for acceptance and staple the ticket to the app.
5. Validate the stapled app.
6. Package the stapled app in a DMG and run a Gatekeeper assessment.

For a local signed-but-not-notarized smoke test only:

```sh
SKIP_NOTARIZATION=1 ./build-dmg.sh
```

Do not distribute an artifact built with `SKIP_NOTARIZATION=1`.

## 4. CI secrets

The release workflow imports the Developer ID certificate into an ephemeral keychain and authenticates
notarytool with the Team Key. Add these GitHub Actions secrets:

- `DEVELOPER_ID_P12_BASE64` — base64-encoded Developer ID Application `.p12` containing its private key.
- `DEVELOPER_ID_P12_PASSWORD` — password for that `.p12`.
- `NOTARY_API_KEY_ID` — App Store Connect API key ID.
- `NOTARY_API_ISSUER_ID` — App Store Connect API issuer ID.
- `NOTARY_API_KEY_P8_BASE64` — base64-encoded `.p8` private key.

Export the Developer ID identity from Xcode's **Manage Certificates…** as a `.p12`, then encode it without
line breaks before adding the secret:

```sh
base64 -i ~/Downloads/BettercastDeveloperID.p12 | tr -d '\n' | pbcopy
```

Paste that value into `DEVELOPER_ID_P12_BASE64`. Keep the `.p12` password in
`DEVELOPER_ID_P12_PASSWORD`; never put it in the repository.

The release workflow never uses Apple Development signing, Apple Distribution signing, self-signed
certificates, or plaintext Apple passwords. It signs the single release with Developer ID Application,
notarizes the app, staples its ticket, and only then creates the DMG.

## 5. self-hosting

Official GitHub Releases and Homebrew packages are already Developer ID-signed and notarized. Users do not
need an Apple Developer account, certificate, or notarization credentials to install them.

A self-host build does not need Apple signing either:

```sh
make build          # unsigned Debug app
make unsigned-dmg   # unsigned Release DMG for local use
```

Unsigned artifacts are for local use only. macOS may require opening the app from Finder with **Open**, or
removing quarantine after inspecting it. Self-hosters who have their own Apple account can optionally use
Apple Development signing for Debug, but it is not required.

## 6. verification

Run these checks against a release artifact before publishing it:

```sh
APP="build/DerivedData/Build/Products/Release/Bettercast.app"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

`codesign` must report a Developer ID Application authority and hardened runtime. `stapler validate` must
succeed. `spctl` must accept the app.

## signing identity migration

Replacing the old self-signed identity with Developer ID changes the code signature. Existing Accessibility
and Input Monitoring grants may need to be granted once again. After that, the Developer ID identity stays
stable across releases as long as the same certificate is used.

## quarantine

A notarized Developer ID app normally opens without the manual quarantine workaround. Direct downloads can
still be affected by a stale quarantine attribute; inspect first and clear it only when Gatekeeper reports
that specific issue:

```sh
xattr -l "/Applications/Bettercast.app"
xattr -dr com.apple.quarantine "/Applications/Bettercast.app"
```
