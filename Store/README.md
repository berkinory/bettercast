# Extension Store

The store has no application backend. Release automation builds `.ocx.zip` assets and a static
`extensions-catalog.json` file, then uploads both to the GitHub Release. Opencast reads the latest
catalog asset directly from GitHub and verifies each package hash before installation.

Generate a catalog locally with:

```sh
node Tools/extensions/build-catalog.js \
  --version 0.1.3 \
  --release-base https://github.com/berkinory/opencast/releases/download/v0.1.3 \
  --out build/extensions-catalog.json \
  build/extensions/kill-process.ocx build/extensions/port-manager.ocx \
  build/extensions/system-monitor.ocx
```
