import { Action, ActionPanel, List, Process, useState } from "@raycast/api";

export default async function Command() {
  const [sortBy, setSortBy] = useState("cpu");
  const processes = await Process.list({ sortBy, limit: 256 });
  return (
    <List>
      <List.Dropdown tooltip="Sort by" value={sortBy} onChange={setSortBy}>
        <List.Dropdown.Item title="CPU Usage" value="cpu" />
        <List.Dropdown.Item title="Memory Usage" value="memory" />
        <List.Dropdown.Item title="Name" value="name" />
      </List.Dropdown>
      {processes.map((process) => (
        <List.Item
          key={process.pid}
          id={String(process.pid)}
          title={process.name}
          subtitle={`${process.pid} · ${process.user}`}
          icon={`process:${process.pid}|${process.path || ""}`}
          accessories={[
            { icon: "gauge.with.dots.needle.33percent", text: `${process.cpuPercent.toFixed(1)}%` },
            { icon: "memorychip", text: `${process.memoryPercent.toFixed(1)}%` }
          ]}
          actions={
            <ActionPanel>
              <Action
                title="Kill"
                style="destructive"
                onAction={() => Process.terminate(process.pid, { signal: "term" })}
              />
              <Action
                title="Force Kill"
                style="destructive"
                onAction={() => Process.terminate(process.pid, { signal: "kill" })}
              />
              <Action title="Restart" style="destructive" onAction={() => Process.restart(process.pid)} />
              <Action
                title="Force Restart"
                style="destructive"
                onAction={() => Process.restart(process.pid, { force: true })}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
