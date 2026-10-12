import { parseArgs } from "node:util";
import readline from "node:readline";
import {
  CONTROL_KEYS,
  CONTROL_VALUES,
  clearCredentials,
  loadCredentials,
} from "./config.js";
import { ensureToken, login } from "./auth.js";
import {
  acDevices,
  controlTopic,
  flattenDevices,
  getDeviceStatus,
  getHomes,
  resolveDevice,
  restControl,
  statusTopics,
} from "./api.js";
import { connectClient, publishControl, subscribeTopics } from "./mqtt.js";

const HELP = `openmiraie — control Panasonic MirAIe ACs via the MirAIe cloud

usage: openmiraie <command> [options]

commands:
  login      sign in (prompts for mobile/email and password)
  logout     remove cached credentials
  homes      list homes, spaces and devices
  status     fetch device status (REST)
  listen     subscribe to MQTT status messages
  control    send a control command (MQTT by default)

common options:
  --device <id|name>   select device (default: first AC)
  --json               raw JSON output
  -h, --help           show this help

login options:
  --mobile <number> | --email <address>

listen options:
  --seconds <n>        listen duration (default 30)

control options:
  --power on|off
  --mode auto|cool|heat|dry|fan
  --temp <16..30>
  --fan auto|high|medium|low|quiet
  --via mqtt|rest      transport (default mqtt)
  --dry-run            print payloads without sending
`;

function parseCli(argv) {
  const { values } = parseArgs({
    args: argv.slice(1),
    allowPositionals: true,
    strict: false,
    options: {
      mobile: { type: "string" },
      email: { type: "string" },
      device: { type: "string" },
      seconds: { type: "string" },
      power: { type: "string" },
      mode: { type: "string" },
      temp: { type: "string" },
      fan: { type: "string" },
      via: { type: "string" },
      json: { type: "boolean" },
      "dry-run": { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  return values;
}

function promptLine(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

function promptHidden(label) {
  return new Promise((resolve, reject) => {
    if (!process.stdin.isTTY) {
      reject(new Error("login requires an interactive terminal"));
      return;
    }
    process.stdout.write(label);
    const stdin = process.stdin;
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");
    let value = "";
    const cleanup = () => {
      stdin.removeListener("data", onData);
      stdin.setRawMode(false);
      stdin.pause();
    };
    const onData = (chunk) => {
      for (const c of chunk) {
        if (c === "\r" || c === "\n") {
          cleanup();
          process.stdout.write("\n");
          resolve(value);
          return;
        }
        if (c === "\u0003") {
          cleanup();
          process.stdout.write("\n");
          process.exit(130);
        }
        if (c === "\u007f" || c === "\b") {
          if (value.length > 0) value = value.slice(0, -1);
          continue;
        }
        value += c;
      }
    };
    stdin.on("data", onData);
  });
}

async function cmdLogin(values) {
  let mobile = values.mobile?.trim();
  let email = values.email?.trim();
  if (!mobile && !email) {
    const answer = (await promptLine("Mobile number (enter to use email): ")).trim();
    if (answer) mobile = answer;
    else email = (await promptLine("Email: ")).trim();
  }
  if (!mobile && !email) throw new Error("mobile or email is required");
  const password = await promptHidden("Password: ");
  if (!password) throw new Error("password is required");
  const creds = await login({ mobile, email, password });
  console.log(`logged in as ${creds.identifier} (userId ${creds.userId})`);
}

function cmdLogout() {
  const creds = loadCredentials();
  clearCredentials();
  console.log(creds ? `removed credentials for ${creds.identifier}` : "no cached credentials");
}

async function cmdHomes(values) {
  await ensureToken();
  const homes = await getHomes();
  if (values.json) {
    console.log(JSON.stringify(homes, null, 2));
    return;
  }
  if (homes.length === 0) {
    console.log("no homes found");
    return;
  }
  for (const home of homes) {
    console.log(`home ${home.homeName} (${home.homeId ?? home.id})  metaTopic=${home.metaTopic ?? "-"}`);
    for (const device of flattenDevices([home])) {
      const topics = (device.topic ?? []).join(", ") || "-";
      console.log(
        `  [${device.category}] ${device.deviceName}  id=${device.deviceId}  model=${device.modelId ?? "-"}`,
      );
      console.log(`      space=${device.spaceName}  topic=${topics}`);
    }
  }
}

function printStatus(status) {
  const keys = [
    "onlineStatus",
    "ps",
    "acmd",
    "actmp",
    "acfs",
    "acvs",
    "achvs",
    "acpw",
    "acec",
    "acng",
    "rmtmp",
    "errors",
  ];
  let printed = false;
  for (const key of keys) {
    if (status?.[key] !== undefined) {
      console.log(`${key}: ${JSON.stringify(status[key])}`);
      printed = true;
    }
  }
  if (!printed) console.log(JSON.stringify(status, null, 2));
}

async function cmdStatus(values) {
  await ensureToken();
  const homes = await getHomes();
  const device = resolveDevice(homes, values.device);
  const status = await getDeviceStatus(device.deviceId);
  console.log(`device ${device.deviceName} (${device.deviceId})`);
  if (values.json) console.log(JSON.stringify(status, null, 2));
  else printStatus(status);
}

async function cmdListen(values) {
  const seconds = Number(values.seconds ?? 30);
  const creds = await ensureToken();
  const homes = await getHomes();
  const device = resolveDevice(homes, values.device);
  const topics = [...statusTopics(device)];
  if (device.metaTopic) topics.push(`${device.metaTopic}/#`);
  const client = await connectClient({
    homeId: device.homeId,
    token: creds.accessToken,
  });
  const granted = await subscribeTopics(client, topics);
  console.log(
    `subscribed: ${granted.map((g) => `${g.topic} (qos ${g.qos})`).join(", ")}`,
  );
  console.log(`listening ${seconds}s on device ${device.deviceName} ...`);
  client.on("message", (topic, payload) => {
    console.log(`${new Date().toISOString()} ${topic} ${payload.toString().slice(0, 600)}`);
  });
  await new Promise((resolve) => setTimeout(resolve, seconds * 1000));
  client.end(true);
  console.log("done");
}

function buildCommands(values) {
  const commands = [];
  if (values.power !== undefined) {
    const power = String(values.power).toLowerCase();
    if (power !== "on" && power !== "off") throw new Error("--power must be on or off");
    commands.push({ [CONTROL_KEYS.power.key]: power, ki: CONTROL_KEYS.power.ki });
  }
  if (values.mode !== undefined) {
    const mode = String(values.mode).toLowerCase();
    if (!CONTROL_VALUES.mode.has(mode)) {
      throw new Error(`--mode must be one of ${[...CONTROL_VALUES.mode].join(", ")}`);
    }
    commands.push({ [CONTROL_KEYS.mode.key]: mode, ki: CONTROL_KEYS.mode.ki });
  }
  if (values.temp !== undefined) {
    const temp = Number(values.temp);
    if (!Number.isFinite(temp) || temp < 16 || temp > 30) {
      throw new Error("--temp must be between 16 and 30");
    }
    commands.push({ [CONTROL_KEYS.temp.key]: temp.toFixed(1), ki: CONTROL_KEYS.temp.ki });
  }
  if (values.fan !== undefined) {
    const fan = String(values.fan).toLowerCase();
    if (!CONTROL_VALUES.fan.has(fan)) {
      throw new Error(`--fan must be one of ${[...CONTROL_VALUES.fan].join(", ")}`);
    }
    commands.push({ [CONTROL_KEYS.fan.key]: fan, ki: CONTROL_KEYS.fan.ki });
  }
  if (commands.length === 0) {
    throw new Error("nothing to do: pass --power, --mode, --temp or --fan");
  }
  return commands;
}

async function cmdControl(values) {
  const via = String(values.via ?? "mqtt").toLowerCase();
  if (via !== "mqtt" && via !== "rest") throw new Error("--via must be mqtt or rest");
  const creds = await ensureToken();
  const homes = await getHomes();
  const device = resolveDevice(homes, values.device);
  const commands = buildCommands(values);

  if (values["dry-run"]) {
    console.log(`target ${device.deviceName} (${device.deviceId}) via ${via}`);
    for (const command of commands) console.log(JSON.stringify(command));
    return;
  }

  if (via === "rest") {
    for (const command of commands) {
      await restControl(device.deviceId, command);
      console.log(`sent (rest): ${JSON.stringify(command)}`);
    }
    return;
  }

  const topic = controlTopic(device);
  const client = await connectClient({
    homeId: device.homeId,
    token: creds.accessToken,
  });
  for (const command of commands) {
    const payload = await publishControl(client, topic, command);
    console.log(`sent (mqtt) to ${topic}: ${JSON.stringify(payload)}`);
  }
  client.end(true);
}

export async function main() {
  const command = process.argv[2];
  const values = parseCli(process.argv);
  if (!command || command === "help" || values.help) {
    console.log(HELP);
    return;
  }
  switch (command) {
    case "login":
      return cmdLogin(values);
    case "logout":
      return cmdLogout();
    case "homes":
      return cmdHomes(values);
    case "status":
      return cmdStatus(values);
    case "listen":
      return cmdListen(values);
    case "control":
      return cmdControl(values);
    default:
      throw new Error(`unknown command: ${command} (run with --help)`);
  }
}
