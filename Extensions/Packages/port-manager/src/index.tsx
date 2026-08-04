import { Action, ActionPanel, List, Ports, Process } from "@raycast/api";

export default async function Command() {
  const ports = await Ports.list({ limit: 256 });
  return (
    <List>
      {ports.map((port) => (
        <List.Item
          key={port.id}
          id={port.id}
          title={`${port.port} · ${port.processName}`}
          subtitle={`${port.host} · PID ${port.pid}`}
          accessories={[port.protocolName, port.user || ""]}
          actions={
            <ActionPanel>
              <Action.CopyToClipboard title="Copy Address" content={`${port.host}:${port.port}`} />
              <Action
                title="Terminate Process"
                onAction={() => Process.terminate(port.pid, { signal: "term" })}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
