import { Action, ActionPanel, Clipboard, List, showToast, Toast } from "@raycast/api";

export default function Command() {
  const items = ["alpha", "beta", "gamma"];

  return (
    <List>
      {items.map((value) => (
        <List.Item
          key={value}
          id={value}
          title={value}
          actions={
            <ActionPanel>
              <Action.CopyToClipboard content={value} />
              <Action title="Use Clipboard" onAction={async () => {
                await Clipboard.copy(value);
                await showToast({ style: Toast.Style.Success, title: "Copied" });
              }} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
