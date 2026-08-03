const runtime = {
  component: null,
  hooks: [],
  hookIndex: 0,
  effects: [],
  actions: new Map(),
  selectionHandlers: new Map(),
  dropdownHandlers: new Map(),
  actionIndex: 0,
  mounted: false,
  mode: "view"
};

function element(type, props, children) {
  return { type, props: { ...(props || {}), children } };
}

export const Fragment = Symbol.for("opencast.fragment");

export function jsx(type, props, key) {
  return { type, key: key == null ? null : String(key), props: props || {} };
}

export const jsxs = jsx;

export function createElement(type, props, ...children) {
  return element(type, props, children);
}

function primitive(kind, props) {
  const component = function Component(componentProps) {
    return { kind, props: componentProps || {}, children: componentProps?.children || [] };
  };
  component.__opencastKind = kind;
  return component;
}

function resolve(value) {
  if (value == null || typeof value === "boolean") return null;
  if (Array.isArray(value)) return value.flatMap((item) => {
    const resolved = resolve(item);
    return resolved == null ? [] : Array.isArray(resolved) ? resolved : [resolved];
  });
  if (typeof value === "string" || typeof value === "number") return value;
  if (value.kind) return { ...value, children: resolve(value.children) };
  if (value.type === Fragment) return resolve(value.props?.children || []);
  if (typeof value.type === "function") {
    if (value.type.__opencastKind) {
      const props = value.props || {};
      return { kind: value.type.__opencastKind, props, children: resolve(props.children || []) };
    }
    return resolve(value.type({ ...(value.props || {}), children: value.props?.children || [] }));
  }
  return null;
}

function childrenOf(node) {
  const children = node?.children || [];
  return Array.isArray(children) ? children.flat(Infinity).filter(Boolean) : [children].filter(Boolean);
}

function text(value) {
  if (value == null) return undefined;
  if (typeof value === "string" || typeof value === "number") return String(value);
  return typeof value === "object" ? JSON.stringify(value) : String(value);
}

function iconValue(icon) {
  if (icon == null) return undefined;
  if (typeof icon === "string") return icon;
  if (icon.source) return icon.source;
  return text(icon);
}

function registerActions(actions, itemID) {
  const resolved = resolve(actions);
  const nodes = resolved == null ? [] : Array.isArray(resolved) ? resolved : [resolved];
  const actionNodes = nodes.flatMap((node) => node?.kind === "actionPanel" ? childrenOf(node) : [node]).filter((node) => node?.kind === "action");
  return actionNodes.map((node) => {
    const id = `${itemID}:action-${runtime.actionIndex++}`;
    if (typeof node.props?.onAction === "function") runtime.actions.set(id, node.props.onAction);
    return {
      id,
      title: text(node.props?.title || "Action") || "Action",
      shortcut: text(node.props?.shortcut),
      section: text(node.props?.section),
      destructive: node.props?.style === "destructive",
      requiresConfirmation: node.props?.requiresConfirmation === true
    };
  });
}

function optionSnapshot(option) {
  if (typeof option === "string" || typeof option === "number") {
    const value = String(option);
    return { title: value, value };
  }
  return {
    title: text(option?.title || option?.label || option?.value || "") || "",
    value: text(option?.value || option?.title || option?.label || "") || ""
  };
}

function detailValue(value) {
  if (!value || typeof value !== "object") return null;
  return {
    markdown: text(value.markdown || "") || "",
    metadata: Array.isArray(value.metadata) ? value.metadata.map((entry, index) => ({
      id: text(entry?.id || `metadata-${index}`) || `metadata-${index}`,
      label: text(entry?.label || entry?.title || "") || "",
      value: text(entry?.value || entry?.text || "") || "",
      kind: text(entry?.kind || "label") || "label"
    })) : [],
    sections: [],
    links: []
  };
}

function detailSnapshot(rootNode) {
  const metadata = [];
  const sections = [];
  const links = [];
  childrenOf(rootNode).forEach((node, index) => {
    if (node?.kind === "detailMetadata") {
      const entries = metadataEntries(node);
      const section = {
        id: text(node.props?.id || `section-${index}`) || `section-${index}`,
        title: text(node.props?.title || "") || "",
        metadata: entries.map((entry, entryIndex) => ({
          id: text(entry.props?.id || `${index}-${entryIndex}`) || `${index}-${entryIndex}`,
          label: text(entry.props?.title || entry.props?.label || "") || "",
          value: text(entry.props?.text || entry.props?.value || entry.props?.content || "") || "",
          kind: entry.kind === "detailMetadataTag" ? "tag" : "label"
        }))
      };
      if (section.title || section.metadata.length) sections.push(section);
      return;
    }
    if (node?.kind === "detailMetadataLabel" || node?.kind === "detailMetadataTag") {
      metadata.push({
        id: text(node.props?.id || `metadata-${index}`) || `metadata-${index}`,
        label: text(node.props?.title || node.props?.label || "") || "",
        value: text(node.props?.text || node.props?.value || node.props?.content || "") || "",
        kind: node.kind === "detailMetadataTag" ? "tag" : "label"
      });
      return;
    }
    if (node?.kind === "detailLink") {
      links.push({
        id: text(node.props?.id || `link-${index}`) || `link-${index}`,
        title: text(node.props?.title || "Open Link") || "Open Link",
        url: text(node.props?.url || "") || ""
      });
    }
  });
  return {
    markdown: text(rootNode.props?.markdown || "") || "",
    metadata,
    sections,
    links
  };
}

function metadataEntries(node) {
  return childrenOf(node).flatMap((child) => {
    if (child?.kind === "detailMetadataLabel" || child?.kind === "detailMetadataTag") return [child];
    if (child?.kind === "detailMetadata") return metadataEntries(child);
    return [];
  });
}

function itemSnapshot(node, index) {
  const itemID = text(node.props?.id || node.props?.key || `item-${index}`) || `item-${index}`;
  if (typeof node.props?.onSelectionChange === "function") runtime.selectionHandlers.set(itemID, node.props.onSelectionChange);
  const actions = registerActions(node.props?.actions, itemID);
  return {
    id: itemID,
    title: text(node.props?.title || "") || "",
    subtitle: text(node.props?.subtitle),
    icon: iconValue(node.props?.icon),
    accessories: (node.props?.accessories || []).map((value) => {
      if (typeof value === "string" || typeof value === "number") return text(value);
      return { icon: text(value?.icon), text: text(value?.text || value?.value) };
    }).filter(Boolean),
    keywords: (node.props?.keywords || []).map(text).filter(Boolean),
    actions,
    detail: detailValue(node.props?.detail)
  };
}

function renderSnapshot(root) {
  runtime.actions.clear();
  runtime.selectionHandlers.clear();
  runtime.dropdownHandlers.clear();
  runtime.actionIndex = 0;
  const rootNode = resolve(root);
  if (!rootNode || typeof rootNode !== "object") throw new Error("Command did not return a supported view.");

  if (rootNode.kind === "list" || rootNode.kind === "grid" || rootNode.kind === "menuBar") {
    const nodes = childrenOf(rootNode).filter((node) => node?.kind === "item" || node?.kind === "menuItem");
      const items = nodes.map(itemSnapshot);
    const dropdownNode = childrenOf(rootNode).find((node) => node?.kind === "listDropdown");
    let listDropdown = null;
    if (dropdownNode) {
      const dropdownID = text(dropdownNode.props?.id || "list-dropdown") || "list-dropdown";
      if (typeof dropdownNode.props?.onChange === "function") runtime.dropdownHandlers.set(dropdownID, dropdownNode.props.onChange);
      listDropdown = {
        id: dropdownID,
        tooltip: text(dropdownNode.props?.tooltip || "Sort") || "Sort",
        value: text(dropdownNode.props?.value || "") || "",
        options: childrenOf(dropdownNode).filter((node) => node?.kind === "listDropdownItem").map((node) => ({
          title: text(node.props?.title || node.props?.value || "") || "",
          value: text(node.props?.value || node.props?.title || "") || ""
        }))
      };
    }
    return {
      root: rootNode.kind === "list" ? "list" : rootNode.kind === "grid" ? "grid" : "menuBarSnapshot",
      items,
      actions: items.flatMap((item) => item.actions || []),
      listDropdown,
      loading: false
    };
  }

  if (rootNode.kind === "detail") {
    const actions = registerActions(rootNode.props?.actions, "detail");
    return {
      root: "detail",
      items: [],
      actions,
      detail: detailSnapshot(rootNode),
      loading: false
    };
  }

  if (rootNode.kind === "form") {
    const fields = childrenOf(rootNode).filter((node) => node?.kind === "field").map((node) => ({
      id: text(node.props?.id || "") || "",
      kind: text(node.props?.fieldKind || "text") || "text",
      title: text(node.props?.title || "") || "",
      value: node.props?.value ?? node.props?.defaultValue ?? null,
      placeholder: text(node.props?.placeholder),
      required: node.props?.isRequired === true || node.props?.required === true,
      options: (node.props?.data || node.props?.options || []).map(optionSnapshot),
      error: text(node.props?.error)
    }));
    const actions = registerActions(rootNode.props?.actions, "form");
    return { root: "form", items: [], fields, actions, loading: false };
  }

  throw new Error(`Unsupported render root: ${rootNode.kind}`);
}

function render() {
  runtime.hookIndex = 0;
  runtime.effects = [];
  const result = runtime.component();
  if (result && typeof result.then === "function") {
    result.then((resolved) => {
      if (runtime.mode === "no-view") {
        globalThis.__opencast.complete();
        return;
      }
      globalThis.__opencast.render(renderSnapshot(resolved));
    }).catch((error) => {
      globalThis.__opencast.log("warn", error?.message || String(error));
      globalThis.__opencast.complete();
    });
  } else {
    globalThis.__opencast.render(renderSnapshot(result));
  }
  for (const effect of runtime.effects) effect();
}

export function mount(component, mode = "view") {
  runtime.component = component;
  runtime.mode = mode;
  runtime.mounted = true;
  globalThis.__opencastOnEvent = async (event) => {
    if (event.event === "selectionChanged" && event.itemID) {
      const handler = runtime.selectionHandlers.get(event.itemID);
      if (handler) await handler(event.itemID);
      return;
    }
    if (event.event === "dropdownChanged" && event.dropdownID) {
      const handler = runtime.dropdownHandlers.get(event.dropdownID);
      if (handler) await handler(event.value);
      return;
    }
    if (event.event === "actionInvoked" && event.actionID) {
      const handler = runtime.actions.get(event.actionID);
      if (handler) await handler(event.fields || event, event);
      if (runtime.mounted && runtime.component) render();
    }
  };
  render();
}

export function useState(initial) {
  const index = runtime.hookIndex++;
  if (!(index in runtime.hooks)) runtime.hooks[index] = typeof initial === "function" ? initial() : initial;
  return [runtime.hooks[index], (next) => {
    runtime.hooks[index] = typeof next === "function" ? next(runtime.hooks[index]) : next;
    if (runtime.mounted) render();
  }];
}

export function useEffect(effect) {
  runtime.effects.push(effect);
}

export function useMemo(factory) {
  return factory();
}

export function useCallback(callback) {
  return callback;
}

export function useRef(value) {
  const [ref] = useState({ current: value });
  return ref;
}

export const List = primitive("list");
List.Item = primitive("item");
List.Section = primitive("section");
List.Dropdown = primitive("listDropdown");
List.Dropdown.Item = primitive("listDropdownItem");

export const Grid = primitive("grid");
Grid.Item = primitive("item");
Grid.Section = primitive("section");

export const Detail = primitive("detail");
Detail.Metadata = primitive("detailMetadata");
Detail.Metadata.Label = (props) => ({ kind: "detailMetadataLabel", props: props || {}, children: [] });
Detail.Metadata.TagList = primitive("detailMetadata");
Detail.Metadata.TagList.Item = (props) => ({ kind: "detailMetadataTag", props: props || {}, children: [] });
Detail.Link = (props) => ({ kind: "detailLink", props: props || {}, children: [] });
export const Form = primitive("form");
Form.TextField = (props) => ({ kind: "field", props: { ...props, fieldKind: "text" }, children: [] });
Form.PasswordField = (props) => ({ kind: "field", props: { ...props, fieldKind: "password" }, children: [] });
Form.TextArea = (props) => ({ kind: "field", props: { ...props, fieldKind: "textarea" }, children: [] });
Form.Checkbox = (props) => ({ kind: "field", props: { ...props, fieldKind: "checkbox" }, children: [] });
Form.Dropdown = (props) => ({ kind: "field", props: { ...props, fieldKind: "dropdown" }, children: [] });
Form.DatePicker = (props) => ({ kind: "field", props: { ...props, fieldKind: "date" }, children: [] });

export const ActionPanel = primitive("actionPanel");
Form.ActionPanel = ActionPanel;

export function Action(props) {
  return { kind: "action", props: props || {}, children: [] };
}
Action.CopyToClipboard = (props) => Action({ ...props, title: props?.title || "Copy to Clipboard", onAction: () => Clipboard.copy(props?.content || "") });
Action.OpenInBrowser = (props) => Action({ ...props, title: props?.title || "Open in Browser", onAction: () => open(props?.url || "") });

export const MenuBarExtra = primitive("menuBar");
MenuBarExtra.Item = (props) => ({ kind: "menuItem", props: props || {}, children: [] });

export const Clipboard = {
  copy: (textValue) => globalThis.__opencast.requestCapability("clipboard.write", { text: String(textValue) }),
  readText: () => globalThis.__opencast.requestCapability("clipboard.read", {})
};

export const Toast = { Style: { Success: "success", Failure: "failure", Animated: "animated" } };
export function showToast(toast) {
  return globalThis.__opencast.log("info", toast?.title || "Toast");
}
export function showHUD(message) {
  return globalThis.__opencast.log("info", String(message));
}
export function open(url) {
  return globalThis.__opencast.requestCapability("open.url", { url: String(url) });
}
export function getSelectedText() {
  return globalThis.__opencast.requestCapability("selectedText.read", {});
}
export function getPreferenceValues() {
  return globalThis.__opencast.preferences || {};
}
export const LocalStorage = {
  getItem: (key) => globalThis.__opencast.requestCapability("storage.read", { key }),
  setItem: (key, value) => globalThis.__opencast.requestCapability("storage.write", { key, value }),
  removeItem: (key) => globalThis.__opencast.requestCapability("storage.delete", { key })
};
export const Cache = {
  get: (key) => globalThis.__opencast.requestCapability("storage.read", { namespace: "cache", key }),
  set: (key, value) => globalThis.__opencast.requestCapability("storage.write", { namespace: "cache", key, value }),
  remove: (key) => globalThis.__opencast.requestCapability("storage.delete", { namespace: "cache", key })
};
export const environment = { commandName: "", extensionName: "", isDevelopment: false };
export function useNavigation() {
  return { push: () => undefined, pop: () => undefined, popToRoot: () => undefined };
}
export function pop() {
  return undefined;
}
export function popToRoot() {
  return undefined;
}
export function exec(command, args = [], options = {}) {
  return globalThis.__opencast.requestCapability("process.execute", { command, args, options });
}

export const Process = {
  list: (options = {}) => globalThis.__opencast.requestCapability("process.inspect", options),
  terminate: (pid, options = {}) => globalThis.__opencast.requestCapability("process.terminate", { pid, ...options }),
  restart: (pid, options = {}) => globalThis.__opencast.requestCapability("process.restart", { pid, ...options }),
  start: (command, args = [], options = {}) => {
    const { onProgress, ...safeOptions } = options || {};
    return globalThis.__opencast.requestCapability(
      "process.execute",
      { command, args, options: { ...safeOptions, stream: true } },
      onProgress
    );
  },
  cancel: (jobID) => globalThis.__opencast.requestCapability("process.cancel", { jobID })
};

export const Ports = {
  list: (options = {}) => globalThis.__opencast.requestCapability("ports.inspect", options)
};

export const System = {
  metrics: () => globalThis.__opencast.requestCapability("system.metrics.read", {})
};
