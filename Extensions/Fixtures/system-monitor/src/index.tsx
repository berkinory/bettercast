import { Detail, System } from "@raycast/api";

function bytes(value) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let amount = Number(value || 0);
  let index = 0;
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024;
    index += 1;
  }
  return `${amount.toFixed(1)} ${units[index]}`;
}

export default async function Command() {
  const metrics = await System.metrics();
  const battery = metrics.batteryPercent == null
    ? "Unavailable"
    : `${metrics.batteryPercent.toFixed(0)}%${metrics.isCharging ? " · Charging" : ""}`;
  return (
    <Detail markdown="">
      <Detail.Metadata>
        <Detail.Metadata.Label title="CPU" text={`${metrics.cpuPercent.toFixed(1)}%`} />
        <Detail.Metadata.Label title="Memory" text={`${bytes(metrics.memoryUsedBytes)} / ${bytes(metrics.memoryTotalBytes)}`} />
        <Detail.Metadata.Label title="Disk" text={`${bytes(metrics.diskUsedBytes)} / ${bytes(metrics.diskTotalBytes)}`} />
        <Detail.Metadata.Label title="Network In" text={`${bytes(metrics.networkDownloadBytesPerSecond)}/s`} />
        <Detail.Metadata.Label title="Network Out" text={`${bytes(metrics.networkUploadBytesPerSecond)}/s`} />
        <Detail.Metadata.Label title="Battery" text={battery} />
        {metrics.temperatureCelsius != null && (
          <Detail.Metadata.Label title="Temperature" text={`${metrics.temperatureCelsius.toFixed(1)}°C`} />
        )}
      </Detail.Metadata>
    </Detail>
  );
}
