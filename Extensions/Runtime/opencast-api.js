const runtime = {
  component: null,
  hooks: [],
  hookIndex: 0,
  effects: [],
  effectCleanups: [],
  effectDependencies: [],
  actions: new Map(),
  selectionHandlers: new Map(),
  dropdownHandlers: new Map(),
  formHandlers: new Map(),
  formChangeHandlers: new Map(),
  loadMoreHandlers: new Map(),
  confirmHandlers: new Map(),
  searchHandler: null,
  navigation: [],
  actionIndex: 0,
  mounted: false,
  mode: "view"
};

function element(type, props, children) {
  return { type, props: { ...(props || {}), children } };
}

export const Fragment = Symbol.for("opencast.fragment");

export const Icon = {
  Circle: "circle",
  Checkmark: "checkmark.circle",
  XMarkCircle: "xmark.circle",
  Gear: "gear",
  Plus: "plus",
  Trash: "trash",
  Link: "link",
  Terminal: "terminal",
  ComputerChip: "cpu",
  Applications: "square.grid.2x2",
  Window: "macwindow",
  Clipboard: "doc.on.clipboard",
  MagnifyingGlass: "magnifyingglass"
};

export const Image = {
  Asset: (name) => ({ source: String(name) }),
  File: (path) => ({ source: String(path) }),
  URL: (url) => ({ source: String(url) })
};

export const Color = {
  PrimaryText: "primary",
  SecondaryText: "secondary",
  Blue: "blue",
  Green: "green",
  Red: "red",
  Orange: "orange",
  Yellow: "yellow",
  Purple: "purple"
};

export const Keyboard = {
  Shortcut: (keys) => keys,
  Key: { ArrowUp: "arrowUp", ArrowDown: "arrowDown", Return: "return", Escape: "escape" }
};

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
  const actionNodes = nodes.flatMap((node) => {
    if (node?.kind === "actionPanel" || node?.kind === "actionPanelSection" || node?.kind === "actionPanelSubmenu") {
      return childrenOf(node).flatMap((child) => child?.kind === "actionPanelSection" ? childrenOf(child) : [child]);
    }
    return [node];
  }).filter((node) => node?.kind === "action");
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
  const detailNode = resolve(node.props?.detail);
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
    detail: detailNode?.kind === "listItemDetail"
      ? detailSnapshot(detailNode)
      : detailValue(detailNode || node.props?.detail)
  };
}

function itemNodes(rootNode) {
  return childrenOf(rootNode).flatMap((node) => {
    if (node?.kind === "section" || node?.kind === "gridSection") return childrenOf(node);
    if (node?.kind === "menuSubmenu") return itemNodes(node);
    return [node];
  }).filter((node) => node?.kind === "item" || node?.kind === "menuItem");
}

function emptyViewSnapshot(rootNode) {
  const node = childrenOf(rootNode).find((child) => child?.kind === "emptyView");
  if (!node) return null;
  return {
    title: text(node.props?.title || "") || "",
    description: text(node.props?.description),
    icon: iconValue(node.props?.icon)
  };
}

function renderSnapshot(root) {
  runtime.actions.clear();
  runtime.selectionHandlers.clear();
  runtime.dropdownHandlers.clear();
  runtime.loadMoreHandlers.clear();
  runtime.formChangeHandlers.clear();
  runtime.actionIndex = 0;
  const rootNode = resolve(root);
  if (!rootNode || typeof rootNode !== "object") throw new Error("Command did not return a supported view.");

  if (rootNode.kind === "list" || rootNode.kind === "grid" || rootNode.kind === "menuBar") {
    if (typeof rootNode.props?.onLoadMore === "function") {
      runtime.loadMoreHandlers.set(rootNode.kind === "grid" ? "grid" : "list", rootNode.props.onLoadMore);
    }
    runtime.searchHandler = typeof rootNode.props?.onSearchTextChange === "function"
      ? rootNode.props.onSearchTextChange : null;
    if (typeof rootNode.props?.onSelectionChange === "function") {
      for (const item of itemNodes(rootNode)) {
        const itemID = text(item.props?.id || item.props?.key);
        if (itemID) runtime.selectionHandlers.set(itemID, rootNode.props.onSelectionChange);
      }
    }
    const items = itemNodes(rootNode).map(itemSnapshot);
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
      loading: rootNode.props?.isLoading === true,
      emptyView: emptyViewSnapshot(rootNode),
      pagination: rootNode.props?.pagination
        ? { hasMore: rootNode.props.pagination.hasMore === true, cursor: text(rootNode.props.pagination.cursor) }
        : null,
      searchBarPlaceholder: text(rootNode.props?.searchBarPlaceholder),
      selectedItemID: text(rootNode.props?.selectedItemId),
      filtering: rootNode.props?.filtering !== false
    };
  }

  if (rootNode.kind === "detail") {
    const actions = registerActions(rootNode.props?.actions, "detail");
    return {
      root: "detail",
      items: [],
      actions,
      detail: detailSnapshot(rootNode),
      loading: rootNode.props?.isLoading === true,
      emptyView: emptyViewSnapshot(rootNode)
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
    childrenOf(rootNode).filter((node) => node?.kind === "field").forEach((node) => {
      if (typeof node.props?.onChange === "function") runtime.formChangeHandlers.set(text(node.props?.id || "") || "", node.props.onChange);
    });
    const actions = registerActions(rootNode.props?.actions, "form");
    if (typeof rootNode.props?.onSubmit === "function") runtime.formHandlers.set("form", rootNode.props.onSubmit);
    return { root: "form", items: [], fields, actions, loading: rootNode.props?.isLoading === true };
  }

  throw new Error(`Unsupported render root: ${rootNode.kind}`);
}

function render() {
  runtime.hookIndex = 0;
  runtime.effects = [];
  const result = runtime.navigation.length ? runtime.navigation[runtime.navigation.length - 1] : runtime.component();
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
  runtime.hooks = [];
  runtime.effectDependencies = [];
  runtime.effectCleanups = [];
  runtime.confirmHandlers.clear();
  runtime.navigation = [];
  runtime.searchHandler = null;
  runtime.mounted = true;
  globalThis.__opencastUnmount = unmount;
  globalThis.__opencastOnEvent = async (event) => {
    if (event.event === "selectionChanged" && event.itemID) {
      const handler = runtime.selectionHandlers.get(event.itemID);
      if (handler) await handler(event.itemID);
      return;
    }
    if (event.event === "searchChanged") {
      if (runtime.searchHandler) await runtime.searchHandler(event.text || "");
      return;
    }
    if (event.event === "dropdownChanged" && event.dropdownID) {
      const handler = runtime.dropdownHandlers.get(event.dropdownID);
      if (handler) await handler(event.value);
      return;
    }
    if (event.event === "loadMore") {
      const handler = runtime.loadMoreHandlers.get(event.root || "list");
      if (handler) await handler();
      return;
    }
    if (event.event === "formSubmitted") {
      const handler = runtime.formHandlers.get("form");
      if (handler) await handler(event.values || {});
      return;
    }
    if (event.event === "formChanged" && event.fieldID) {
      const handler = runtime.formChangeHandlers.get(event.fieldID);
      if (handler) await handler(event.value);
      return;
    }
    if (event.event === "confirmResponse" && event.requestID) {
      const resolveConfirmation = runtime.confirmHandlers.get(event.requestID);
      if (resolveConfirmation) {
        runtime.confirmHandlers.delete(event.requestID);
        resolveConfirmation(event.confirmed === true);
      }
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

export function unmount() {
  runtime.mounted = false;
  runtime.effectCleanups.forEach((cleanup) => {
    if (typeof cleanup === "function") cleanup();
  });
  runtime.effectCleanups = [];
  runtime.confirmHandlers.forEach((resolve) => resolve(false));
  runtime.confirmHandlers.clear();
}

export function useState(initial) {
  const index = runtime.hookIndex++;
  if (!(index in runtime.hooks)) runtime.hooks[index] = typeof initial === "function" ? initial() : initial;
  return [runtime.hooks[index], (next) => {
    runtime.hooks[index] = typeof next === "function" ? next(runtime.hooks[index]) : next;
    if (runtime.mounted) render();
  }];
}

export function useEffect(effect, dependencies) {
  const index = runtime.hookIndex++;
  const previous = runtime.effectDependencies[index];
  const changed = dependencies == null || !previous || dependencies.length !== previous.length
    || dependencies.some((value, dependencyIndex) => value !== previous[dependencyIndex]);
  runtime.effectDependencies[index] = dependencies;
  if (changed) {
    if (typeof runtime.effectCleanups[index] === "function") runtime.effectCleanups[index]();
    runtime.effects.push(() => {
      runtime.effectCleanups[index] = effect();
    });
  }
}

export function usePromise(promiseFactory, dependencies = [], options = {}) {
  const [state, setState] = useState({
    data: options.initialData,
    isLoading: options.execute !== false,
    error: undefined
  });
  const run = () => {
    setState((current) => ({ ...current, isLoading: true, error: undefined }));
    if (options.execute === false) return;
    let active = true;
    Promise.resolve().then(() => promiseFactory()).then((data) => {
      if (active) setState({ data, isLoading: false, error: undefined });
      options.onData?.(data);
    }).catch((error) => {
      if (active) setState({ data: options.initialData, isLoading: false, error });
      options.onError?.(error);
    });
    return () => { active = false; };
  };
  useEffect(() => {
    const cleanup = run();
    return cleanup;
  }, dependencies);
  return { ...state, revalidate: run };
}

export function useCachedPromise(promiseFactory, dependencies = [], options = {}) {
  return usePromise(promiseFactory, dependencies, options);
}

export function useCachedState(key, initialValue) {
  const [value, setValue] = useState(initialValue);
  return [value, setValue];
}

export function useSQL(query, params = []) {
  return globalThis.__opencast.requestCapability("storage.sqlite", { query, params });
}

export function useMemo(factory) {
  runtime.hookIndex++;
  return factory();
}

export function useCallback(callback) {
  runtime.hookIndex++;
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
List.Item.Detail = primitive("listItemDetail");
List.Item.Accessory = {
  Icon: (icon, tooltip) => ({ icon: iconValue(icon), tooltip }),
  Text: (textValue, options = {}) => ({ text: textValue, icon: iconValue(options.icon), tooltip: options.tooltip }),
  Tag: (textValue, color) => ({ text: textValue, tagColor: color })
};
List.EmptyView = primitive("emptyView");

export const Grid = primitive("grid");
Grid.Item = primitive("item");
Grid.Section = primitive("section");
Grid.EmptyView = primitive("emptyView");

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
Form.FilePicker = (props) => ({ kind: "field", props: { ...props, fieldKind: "file" }, children: [] });
Form.Directory = (props) => ({ kind: "field", props: { ...props, fieldKind: "directory" }, children: [] });

export const ActionPanel = primitive("actionPanel");
Form.ActionPanel = ActionPanel;
ActionPanel.Section = primitive("actionPanelSection");
ActionPanel.Submenu = primitive("actionPanelSubmenu");

export function Action(props) {
  return { kind: "action", props: props || {}, children: [] };
}
Action.CopyToClipboard = (props) => Action({ ...props, title: props?.title || "Copy to Clipboard", onAction: () => Clipboard.copy(props?.content || "") });
Action.OpenInBrowser = (props) => Action({ ...props, title: props?.title || "Open in Browser", onAction: () => open(props?.url || "") });
Action.Open = (props) => Action({ ...props, title: props?.title || "Open", onAction: props?.onAction || (() => open(props?.target || props?.url || "")) });
Action.ShowInFinder = (props) => Action({ ...props, title: props?.title || "Show in Finder", onAction: props?.onAction || (() => globalThis.__opencast.requestCapability("finder.reveal", { path: props?.path || "" })) });
Action.Paste = (props) => Action({ ...props, title: props?.title || "Paste", onAction: () => Clipboard.paste(props?.content || "") });

export const MenuBarExtra = primitive("menuBar");
MenuBarExtra.Item = (props) => ({ kind: "menuItem", props: props || {}, children: [] });
MenuBarExtra.Submenu = primitive("menuSubmenu");
MenuBarExtra.Separator = () => ({ kind: "menuSeparator", props: {}, children: [] });

export const Clipboard = {
  copy: (textValue) => globalThis.__opencast.requestCapability("clipboard.write", { text: String(textValue) }),
  readText: () => globalThis.__opencast.requestCapability("clipboard.read", {}),
  paste: (textValue) => globalThis.__opencast.requestCapability("clipboard.paste", { text: String(textValue) })
};

export const Toast = { Style: { Success: "success", Failure: "failure", Animated: "animated" } };
export function showToast(toast) {
  const toastID = "toast-" + Date.now() + "-" + Math.random().toString(16).slice(2);
  globalThis.__opencast.feedback("toast", { toastID, ...(toast || {}) });
  return Promise.resolve({
    hide: () => globalThis.__opencast.feedback("toastHide", { toastID }),
    show: () => globalThis.__opencast.feedback("toastShow", { toastID }),
    set title(value) { globalThis.__opencast.feedback("toastUpdate", { toastID, title: value }); },
    set message(value) { globalThis.__opencast.feedback("toastUpdate", { toastID, message: value }); },
    set style(value) { globalThis.__opencast.feedback("toastUpdate", { toastID, style: value }); }
  });
}
export function showHUD(message) {
  return globalThis.__opencast.feedback("hud", { message: String(message) });
}
export function open(url) {
  const target = String(url);
  if (/^https?:\/\//i.test(target)) {
    return globalThis.__opencast.requestCapability("open.url", { url: target });
  }
  return globalThis.__opencast.requestCapability("open.application", { path: target });
}
export function openApplication(path) {
  return globalThis.__opencast.requestCapability("open.application", { path: String(path) });
}
export function revealInFinder(path) {
  return globalThis.__opencast.requestCapability("finder.reveal", { path: String(path) });
}
export function getSelectedText() {
  return globalThis.__opencast.requestCapability("selectedText.read", {});
}
export function getSelectedFinderItems() {
  return globalThis.__opencast.requestCapability("finder.selection.read", {});
}
export function getApplications() {
  return globalThis.__opencast.requestCapability("application.list", {});
}
export function getFrontmostApplication() {
  return globalThis.__opencast.requestCapability("application.frontmost", {});
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
export const environment = {
  commandName: globalThis.__opencast.commandName || "",
  extensionName: globalThis.__opencast.extensionName || "",
  isDevelopment: globalThis.__opencast.isDevelopment === true,
  commandMode: globalThis.__opencast.commandMode || "view",
  launchType: globalThis.__opencast.launchType || "userInitiated",
  supportPath: globalThis.__opencast.supportPath || "",
  assetsPath: globalThis.__opencast.assetsPath || ""
};
export function useNavigation() {
  return {
    push: (component) => { runtime.navigation.push(component); render(); },
    pop: () => { runtime.navigation.pop(); render(); },
    popToRoot: () => { runtime.navigation = []; render(); }
  };
}
export function pop() {
  runtime.navigation.pop();
  render();
}
export function popToRoot() {
  runtime.navigation = [];
  render();
}
export function exec(command, args = [], options = {}) {
  return globalThis.__opencast.requestCapability("process.execute", { command, args, options });
}

export async function fetch(input, init = {}) {
  const url = typeof input === "string" ? input : input?.url;
  const result = await globalThis.__opencast.requestCapability("network.request", {
    url,
    method: init.method || "GET",
    headers: init.headers || {},
    body: init.body == null ? undefined : typeof init.body === "string" ? init.body : JSON.stringify(init.body),
    bodyBase64: init.bodyBase64,
    timeout: init.timeout,
    stream: init.stream === true
  });
  const body = result?.body || "";
  return {
    ok: Number(result?.status || 0) >= 200 && Number(result?.status || 0) < 400,
    status: result?.status || 0,
    headers: result?.headers || {},
    url,
    text: async () => body,
    json: async () => JSON.parse(body),
    arrayBuffer: async () => {
      if (result?.bodyBase64) {
        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        let binary = "";
        let buffer = 0;
        let bits = 0;
        for (const character of result.bodyBase64) {
          const value = alphabet.indexOf(character);
          if (value < 0 || value === 64) continue;
          buffer = (buffer << 6) | value;
          bits += 6;
          if (bits >= 8) {
            bits -= 8;
            binary += String.fromCharCode((buffer >> bits) & 0xff);
          }
        }
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
        return bytes.buffer;
      }
      return new TextEncoder().encode(body).buffer;
    }
  };
}

globalThis.fetch = fetch;

export function useFetch(url, options = {}) {
  return usePromise(() => fetch(url, options).then(async (response) => {
    if (!response.ok) throw new Error("HTTP " + response.status);
    return options.parseResponse ? options.parseResponse(response) : response.json();
  }), [url], options);
}

export function useExec(command, args = [], options = {}) {
  return usePromise(
    () => exec(command, args, options).then((result) => result?.stdout || ""),
    [command, JSON.stringify(args), JSON.stringify(options)],
    options
  );
}

export function confirmAlert(options) {
  const requestID = "confirm-" + Date.now() + "-" + Math.random().toString(16).slice(2);
  return new Promise((resolve) => {
    runtime.confirmHandlers.set(requestID, resolve);
    globalThis.__opencast.feedback("confirm", {
      requestID,
      title: options?.title || "Confirm",
      message: options?.message || "Are you sure?",
      primaryAction: options?.primaryAction?.title || "Continue",
      dismissAction: options?.dismissAction?.title || "Cancel"
    });
  });
}

export function runAppleScript(script, options = {}) {
  return globalThis.__opencast.requestCapability("applescript.execute", {
    script: String(script),
    language: options.language || "AppleScript"
  });
}

export const FilePicker = {
  pickFile: (options = {}) => globalThis.__opencast.requestCapability("filesystem.pick", options),
  pickDirectory: (options = {}) => globalThis.__opencast.requestCapability("filesystem.pick", { ...options, directory: true })
};

export const Filesystem = {
  read: (path) => globalThis.__opencast.requestCapability("filesystem.read", { path }),
  write: (path, value) => globalThis.__opencast.requestCapability("filesystem.write", {
    path,
    ...(typeof value === "string" ? { text: value } : value)
  }),
  list: (path) => globalThis.__opencast.requestCapability("filesystem.list", { path }),
  quickLook: (path) => globalThis.__opencast.requestCapability("filesystem.quickLook", { path })
};

export function openExtensionPreferences() {
  return globalThis.__opencast.feedback("openPreferences", {});
}

export const Browser = {
  tabs: (browser = "Safari") => globalThis.__opencast.requestCapability("browser.read", { browser }),
  history: (browser = "Safari") => globalThis.__opencast.requestCapability("browser.read", { browser, resource: "history" }),
  bookmarks: (browser = "Safari") => globalThis.__opencast.requestCapability("browser.read", { browser, resource: "bookmarks" }),
  closeTab: (browser, index) => globalThis.__opencast.requestCapability("browser.mutate", { browser, operation: "closeTab", index }),
  createBookmark: (browser, title, url) => globalThis.__opencast.requestCapability(
    "browser.mutate", { browser, operation: "createBookmark", title, url }
  )
};

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

export default {
  createElement,
  Fragment,
  useState,
  useEffect,
  useMemo,
  useCallback,
  useRef
};
