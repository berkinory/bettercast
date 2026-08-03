import { Form, getPreferenceValues, showToast, Toast } from "@raycast/api";

type Preferences = { defaultLabel?: string };

export default function Command() {
  const preferences = getPreferenceValues<Preferences>();

  return (
    <Form
      actions={
        <Form.ActionPanel>
          <Form.Action title="Save" onAction={async (values) => {
            await showToast({ style: Toast.Style.Success, title: values.label || preferences.defaultLabel || "Saved" });
          }} />
        </Form.ActionPanel>
      }
    >
      <Form.TextField id="label" title="Label" defaultValue={preferences.defaultLabel} />
      <Form.Checkbox id="enabled" title="Enabled" defaultValue={true} />
      <Form.Dropdown id="mode" title="Mode" defaultValue="fast" data={[{ title: "Fast", value: "fast" }, { title: "Safe", value: "safe" }]} />
      <Form.DatePicker id="date" title="Date" />
    </Form>
  );
}
