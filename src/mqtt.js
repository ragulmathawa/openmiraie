import mqtt from "mqtt";
import { randomBytes } from "node:crypto";
import { ENDPOINTS } from "./config.js";

let sequenceId = 1;

export function connectClient({ homeId, token }) {
  return new Promise((resolve, reject) => {
    const client = mqtt.connect(ENDPOINTS.mqtt, {
      username: homeId,
      password: token,
      clean: true,
      reconnectPeriod: 2000,
      connectTimeout: 15000,
      clientId: `openmiraie-${randomBytes(6).toString("hex")}`,
    });
    const onError = (err) => {
      client.removeListener("connect", onConnect);
      reject(err);
    };
    const onConnect = () => {
      client.removeListener("error", onError);
      resolve(client);
    };
    client.once("connect", onConnect);
    client.once("error", onError);
  });
}

export function subscribeTopics(client, topics) {
  return new Promise((resolve, reject) => {
    client.subscribe(topics, { qos: 0 }, (err, granted) => {
      if (err) reject(err);
      else resolve(granted);
    });
  });
}

export function publishControl(client, topic, params) {
  const payload = { ...params, cnt: "an", sid: String(sequenceId++) };
  return new Promise((resolve, reject) => {
    client.publish(topic, JSON.stringify(payload), { qos: 1 }, (err) => {
      if (err) reject(err);
      else resolve(payload);
    });
  });
}
