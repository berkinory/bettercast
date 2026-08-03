import { Action, ActionPanel, Detail } from "@raycast/api";

export default function Command() {
  return (
    <Detail
      markdown="# Opencast\n\nThis is a detail fixture."
      actions={
        <ActionPanel>
          <Action.OpenInBrowser url="https://opencast.app" />
        </ActionPanel>
      }>
      <Detail.Metadata>
        <Detail.Metadata.Label title="Status" text="Ready" />
        <Detail.Metadata.TagList>
          <Detail.Metadata.TagList.Item title="Native" text="SwiftUI" />
        </Detail.Metadata.TagList>
      </Detail.Metadata>
      <Detail.Link title="Open Opencast" url="https://opencast.app" />
    </Detail>
  );
}
