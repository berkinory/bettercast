# Extension Store

The store has no application backend. The `Extension Store` workflow builds `.ocx.zip` assets and a
static `extensions-catalog.json` file, then uploads both to the stable `extensions` GitHub Release.
Opencast reads that catalog directly from GitHub and verifies each package hash before installation.
Only changed allowlisted extensions are rebuilt. A bundle change with the same version is rejected.

Generate a catalog locally with:

```sh
node Tools/extensions/build-store.js \
  --release-base https://github.com/berkinory/opencast/releases/download/extensions \
  --out build/extension-store \
  --catalog build/extensions-catalog.json
```
