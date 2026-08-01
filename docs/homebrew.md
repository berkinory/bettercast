# maintainer homebrew

This document is for maintainers who publish official releases. Use one shared public repository for all
your apps:

```text
https://github.com/berkinory/homebrew-brew
```

Create or keep this file in the repository:

```text
Casks/opencast.rb
```

Contents:

```ruby
cask "opencast" do
  version "0.0.1"
  sha256 "REPLACE_AFTER_THE_FIRST_RELEASE"

  url "https://github.com/berkinory/opencast/releases/download/v#{version}/Opencast-#{version}.dmg"
  name "Opencast"
  desc "A fast macOS menu-bar launcher"
  homepage "https://github.com/berkinory/opencast"

  app "Opencast.app"

  postflight do
    marker = Pathname.new(Dir.home).join("Library/Application Support/com.opencast.app/distribution")
    marker.dirname.mkpath
    marker.write("homebrew\\n")
  end

  uninstall_postflight do
    marker = Pathname.new(Dir.home).join("Library/Application Support/com.opencast.app/distribution")
    marker.delete if marker.exist?
  end
end
```

Future apps use more files in the same repository:

```text
Casks/opencast.rb
Casks/another-app.rb
Formula/some-cli.rb
```

The repository uses Homebrew's standard `homebrew-` prefix, so users can tap it directly:

```sh
brew tap berkinory/brew
brew install --cask berkinory/brew/opencast
```

After the first Opencast release, the release workflow updates `version` and `sha256` in
`Casks/opencast.rb` automatically. The cask also marks the installation outside the app bundle so
Opencast can leave updates to Homebrew instead of replacing a package-managed app itself.

To refresh the tap and upgrade Opencast manually:

```sh
brew update
brew outdated --cask opencast
brew upgrade --cask opencast
```

When the user invokes `Check for Updates`, Opencast runs `brew outdated --cask --json=v2 opencast` with
`HOMEBREW_NO_AUTO_UPDATE=1`. It never runs `brew update` or `brew upgrade`; those commands change Homebrew
metadata or replace the cask-managed app and remain user-controlled.

The GitHub Actions `HOMEBREW_TAP_TOKEN` secret must be a fine-grained token with **Contents: read/write**
access to `berkinory/homebrew-brew`. The workflow uses the release repository owner dynamically, so a fork
can use its own shared brew repository.
