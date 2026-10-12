import { AC_CATEGORIES } from "./config.js";
import { authedFetch, authedJson } from "./auth.js";

export async function getHomes() {
  const homes = await authedJson("homeManagement/homes");
  return Array.isArray(homes) ? homes : [];
}

export function flattenDevices(homes) {
  const out = [];
  for (const home of homes) {
    for (const space of home.spaces ?? []) {
      for (const device of space.devices ?? []) {
        out.push({
          ...device,
          homeId: home.homeId ?? home.id,
          homeName: home.homeName,
          metaTopic: home.metaTopic,
          spaceId: space.spaceId,
          spaceName: space.spaceName,
        });
      }
    }
  }
  return out;
}

export function acDevices(homes) {
  return flattenDevices(homes).filter((d) =>
    AC_CATEGORIES.has(String(d.category ?? "").toUpperCase()),
  );
}

export function findDevice(devices, selector) {
  if (!selector) return null;
  const needle = selector.toLowerCase();
  return (
    devices.find((d) => String(d.deviceId).toLowerCase() === needle) ??
    devices.find((d) => String(d.deviceName).toLowerCase() === needle) ??
    devices.find((d) => String(d.deviceName).toLowerCase().includes(needle)) ??
    null
  );
}

export function resolveDevice(homes, selector) {
  const devices = flattenDevices(homes);
  if (selector) {
    const device = findDevice(devices, selector);
    if (!device) throw new Error(`device not found: ${selector}`);
    return device;
  }
  const acs = acDevices(homes);
  if (acs.length === 0) throw new Error("no AC device found in your homes");
  return acs[0];
}

export async function getDeviceStatus(deviceId) {
  return authedJson(`deviceManagement/devices/${deviceId}/mobile/status`);
}

export function controlTopic(device) {
  const prefix = (device.topic ?? [])[0];
  if (!prefix) throw new Error(`device ${device.deviceId} has no mqtt topic`);
  const category = String(device.category ?? "").toUpperCase();
  const suffix =
    category === "IAC" || category === "PAC" ? "tcontrol" : "control";
  return `${prefix}/${suffix}`;
}

export function statusTopics(device) {
  return (device.topic ?? []).map((prefix) => `${prefix}/status`);
}

export async function restControl(deviceId, controlParams) {
  const res = await authedFetch("deviceManagement/control", {
    method: "POST",
    body: JSON.stringify({ deviceId, control_params: controlParams }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
  }
  return text ? JSON.parse(text) : null;
}
