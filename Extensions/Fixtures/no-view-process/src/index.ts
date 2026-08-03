import { Clipboard, getSelectedText, showHUD } from "@raycast/api";
import { exec } from "@raycast/utils";

export default async function Command() {
  const input = await getSelectedText();
  const result = await exec("/usr/bin/python3", ["-c", "import json,sys; print(json.dumps(json.loads(sys.stdin.read()), indent=2))"], { input });
  await Clipboard.copy(result.trim());
  await showHUD("Formatted JSON");
}
