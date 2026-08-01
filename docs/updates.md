# Updates

Opencast checks GitHub Releases only after the user grants consent and runs `Check for Updates`. Automatic
checks are off by default. The consent flag belongs to `UpdateStore`, not `AppSettings`, and every network
entry point checks it before and after awaiting the request.

The release workflow uploads both the Homebrew DMG and an app ZIP. The updater prefers the ZIP and accepts
the DMG for older releases. It verifies the GitHub-provided SHA-256 digest while streaming the download,
then verifies that the extracted bundle has the same bundle ID, version, and designated code-signing
requirement as the running app. The archive is staged before asking to install.

Installation runs the existing executable in a short-lived updater mode. It waits for the parent app to exit,
atomically swaps the verified bundle with a rollback path, and relaunches Opencast. No updater framework or
SwiftPM dependency is embedded.

Versions use SemVer ordering, including prerelease identifiers. Homebrew casks write a marker outside the
app bundle. A Homebrew-managed installation does not self-update; an explicit check asks Homebrew for its
outdated cask status and shows the user the `brew update && brew upgrade --cask opencast` command when needed.
Homebrew remains the owner of that install. Development builds have no update feed.
