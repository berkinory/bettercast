# Opencast extensions

Opencast extensions are Raycast-shaped JavaScript commands hosted by JavaScriptCore. Node, Bun,
npm, and a shell daemon are never shipped in the app. Bun or Node is used only while building and
testing an extension. Each command runs in a short-lived host process with a native Swift broker.

OAuth, API keys, tokens, and AI APIs are not supported. If a Raycast extension mixes AI and normal
commands, port the normal commands and omit the AI commands from the package.

## First-party extensions

| Extension | Capabilities |
| --- | --- |
| Kill Process | `process.inspect`, `process.terminate`, `process.restart` |
| Ports | `ports.inspect`, `process.terminate`, `clipboard.write` |
| System Monitor | `system.metrics.read` |

## Develop

Requirements are macOS 15+, Xcode 26, Node.js, and Bun. Bun is a build tool only.

```sh
node Tools/extensions/build-extension.js \
  --package Extensions/Packages/kill-process \
  --out build/extensions/kill-process.ocx
```

Run the contract and package checks with `make extensions-test` and `make extension-store-test`.

For local trusted development, build a package and search for **Import Extension** in Opencast. The
file picker accepts the resulting `.ocx` directory and installs it without publishing to Store.

## Package contract

`package.json` contains development metadata and Raycast command source paths. `opencast.json` is
the security contract and is required for published packages:

```json
{
  "schemaVersion": 1,
  "commands": [{
    "name": "example",
    "src": "src/example.tsx",
    "mode": "view",
    "capabilities": {
      "names": ["network.request"],
      "networkDomains": ["api.example.com", "*.cdn.example.com"]
    }
  }]
}
```

An installable `.ocx` directory contains `bundle.js`, `manifest.json`, `capabilities.json`, and
`build.json`. The builder embeds pure-JavaScript dependencies. Native addons, dynamic native
modules, postinstall scripts, remote code loading, direct Node APIs, and bundles over 8 MB fail
validation. The app bundle contains no extension package or JavaScript runtime.

## Compatibility API

The shims are exposed through `@raycast/api`, `@raycast/utils`, `react`, and JSX runtime imports.

- UI: `List`, sections, filtering, selection IDs, pagination, loading, dropdowns, `Grid`, `Detail`,
  metadata, links, images, `Form`, file and directory fields, `ActionPanel`, sections, submenus,
  shortcuts, destructive actions, `MenuBarExtra`, separators, and empty views.
- Feedback: `showToast`, toast update/hide, `Toast.Style`, `showHUD`, `confirmAlert`.
- Navigation: `useNavigation`, `push`, `pop`, and `popToRoot`.
- Hooks: `useFetch`, `useExec`, `usePromise`, `useCachedPromise`, `useCachedState`, `useNavigation`,
  `environment`, and extension-scoped `useSQL`.
- Native helpers: `fetch`, `exec`, `runAppleScript`, `FilePicker`, `Filesystem`, `Browser`,
  `Clipboard`, `openApplication`, `revealInFinder`, `getSelectedText`, `getSelectedFinderItems`,
  application discovery, `LocalStorage`, and `Cache`.

Unsupported APIs fail explicitly. Capability usage is statically checked during build and checked
again by the package validator and native broker.

The package `build.json` includes a capability-contract hash over `manifest.json` and
`capabilities.json`. Store catalog entries pin that hash as well as the bundle hash, so a scope
change cannot be hidden behind an unchanged bundle.

## Capabilities

Declare every privileged operation in `opencast.json`. Network requests support GET, POST, PUT,
PATCH, DELETE, headers, JSON or text bodies, binary responses, timeout, and cancellation. Domains
are exact by default; `*.example.com` also covers the apex domain and subdomains.

CLI execution requires declared executable paths, bounded arguments, optional stdin, environment,
streaming output, timeout, cancellation, and quotas. Shell execution is not implicit. Filesystem
access is limited to the extension area and declared home paths. Protected system paths, native
modules, and full-disk access are blocked.

Clipboard, selected text, Finder selection, application discovery, AppleScript/JXA, browser tab
reads, browser mutations, local storage, cache, and extension-scoped SQLite are brokered by native
Swift providers. Runtime permission prompts are not shown for Store or local trusted packages.

## Lifecycle and updates

Commands use `view`, `no-view`, or `menu-bar` mode. Background refresh is automatic for eligible
interval commands. Hosts are short-lived and are closed after a snapshot or completion. Persistent
daemons are not supported.

The Store catalog and packages are static GitHub Release assets. Catalog refresh and package
verification happen automatically, but they never install anything. The app never updates an
extension automatically. Pressing Install or Update in the Store is always required, without a
second confirmation dialog.
Capability declarations are included in the package hash.

## Publish

1. Add source and `opencast.json` under `Extensions/Packages/<name>`.
2. Pin pure-JavaScript dependencies and add version, license, source repository, and commit data.
3. Add the package to `Store/approved-extensions.json` with its exact capabilities.
4. Run `make extensions-test`, `make extension-store-test`, and `make extension-budget-test`.
5. Build `.ocx.zip` and update the static catalog with `Tools/extensions/build-store.js`.
6. Upload changed package assets and the catalog to the stable `extensions` GitHub Release.

Review requires a clean validator report, a declared capability manifest, compatibility coverage, a
reproducible bundle hash, and no OAuth, API key, token, or AI command.
