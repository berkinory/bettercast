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
`Casks/opencast.rb` automatically.

The GitHub Actions `HOMEBREW_TAP_TOKEN` secret must be a fine-grained token with **Contents: read/write**
access to `berkinory/homebrew-brew`. The workflow uses the release repository owner dynamically, so a fork
can use its own shared brew repository.
