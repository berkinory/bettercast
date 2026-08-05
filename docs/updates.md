# Updates

Direct installations use Sparkle 2.9.5. `UpdateStore` owns the updater controller and the network-consent
flag. Sparkle does not start until the user grants consent. Automatic checks and automatic installation are
off by default, system profiling is disabled, and revoking consent disables both automatic options.

Users can check manually, enable one daily background check, and optionally let Sparkle install updates in
the background. Sparkle owns the update window, download progress, archive verification, installation,
rollback, and relaunch. Development builds do not create an updater.

The release workflow builds and notarizes the app, creates its ZIP, signs the archive with Sparkle's EdDSA
key, embeds the matching `CHANGELOG.md` section, signs the appcast, and uploads the ZIP, DMG, and
`appcast.xml` to the GitHub Release. The app reads the stable latest-release appcast URL. Sparkle verifies
the EdDSA signature before extraction and macOS verifies the Developer ID signature.

Homebrew remains the owner of Homebrew installations. An explicit check runs `brew outdated` with automatic
Homebrew updates disabled. When a newer cask is available, Opencast shows and copies
`brew update && brew upgrade --cask opencast`; it never runs the upgrade itself.

The public Sparkle key is committed in `Opencast/Info.plist`. The private key stays in the maintainer's
keychain and in the protected `SPARKLE_PRIVATE_KEY` GitHub Actions secret. Never commit or print it.
