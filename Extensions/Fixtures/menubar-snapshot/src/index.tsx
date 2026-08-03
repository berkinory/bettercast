import { MenuBarExtra } from "@raycast/api";

export default function Command() {
  return (
    <MenuBarExtra icon="☕" title="Coffee">
      <MenuBarExtra.Item title="Brewed" onAction={() => undefined} />
    </MenuBarExtra>
  );
}
