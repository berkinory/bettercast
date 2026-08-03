import { Grid } from "@raycast/api";

export default function Command() {
  return (
    <Grid>
      <Grid.Item id="ready" title="Ready" subtitle="Native" icon="checkmark.circle" />
      <Grid.Item id="waiting" title="Waiting" subtitle="Queued" icon="clock" />
    </Grid>
  );
}
