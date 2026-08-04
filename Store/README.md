# Extension Store

The Extension Store uses static GitHub Release assets. It builds `.ocx.zip` packages and an
`extensions-catalog.json`, then uploads only changed packages to the stable `extensions` release.
Opencast refreshes the catalog automatically and verifies the bundle hash, capability-contract hash,
and capability list. No service or account is required.

Catalog refresh never installs or updates anything. Extensions are never installed or updated
automatically. The user must press Install or Update in the Store every time, without a second
confirmation dialog. A bundle or capability-contract change with the same version is rejected during
catalog generation.

Generate a catalog locally with:

```sh
node Tools/extensions/build-store.js \
  --release-base https://github.com/berkinory/opencast/releases/download/extensions \
  --out build/extension-store \
  --catalog build/extensions-catalog.json
```
