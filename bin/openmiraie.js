#!/usr/bin/env node
import { main } from "../src/cli.js";

main().catch((err) => {
  console.error(`error: ${err.message}`);
  process.exit(1);
});
