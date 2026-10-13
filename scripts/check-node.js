"use strict";

// The development manifest is the supported-runtime authority.
const policy = require("../package.json").engines.node;
const major = process.versions.node.split(".")[0];
if (!policy.split(" || ").includes(`^${major}.0.0`)) {
  console.error(`Node ${policy} is required; found ${process.versions.node}`);
  process.exit(1);
}
