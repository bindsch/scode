#!/usr/bin/env node
// Merge kcov cobertura reports for `scode` and enforce a line-coverage floor.
//
// Usage: node scripts/coverage-gate.js <minimum-percent> <report.xml>...
//
// A line counts as covered when any report hit it. macOS and Linux each
// skip the other platform's runtime-sandbox tests, so neither report alone
// reflects what the suite exercises; the floor applies to their union.
//
// Every report must describe the scode in this tree: `make coverage` writes
// a <report>.source-sha256 sidecar, and a report whose sidecar is missing or
// names another scode is refused, so a stale report cannot lift the result.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");

const [minArg, ...reports] = process.argv.slice(2);
const min = Number(minArg);
if (!Number.isFinite(min) || reports.length === 0) {
  console.error("usage: coverage-gate.js <minimum-percent> <cobertura.xml>...");
  process.exit(2);
}

const source = path.join(__dirname, "..", "scode");
const sourceHash = createHash("sha256").update(fs.readFileSync(source)).digest("hex");

const hits = new Map();
for (const report of reports) {
  let sidecar;
  try {
    sidecar = fs.readFileSync(`${report}.source-sha256`, "utf8").trim();
  } catch {
    console.error(`coverage-gate: ${report} has no .source-sha256 sidecar (run make coverage)`);
    process.exit(2);
  }
  if (sidecar !== sourceHash) {
    console.error(`coverage-gate: ${report} measured a different scode than the one in this tree; re-run make coverage`);
    process.exit(2);
  }
  const xml = fs.readFileSync(report, "utf8");
  let seen = 0;
  for (const match of xml.matchAll(/<line\s+number="(\d+)"\s+hits="(\d+)"/g)) {
    const line = Number(match[1]);
    hits.set(line, (hits.get(line) ?? 0) + Number(match[2]));
    seen += 1;
  }
  if (seen === 0) {
    console.error(`coverage-gate: no <line> entries in ${report}`);
    process.exit(2);
  }
}

const total = hits.size;
let covered = 0;
for (const count of hits.values()) if (count > 0) covered += 1;
const percent = total === 0 ? 0 : (100 * covered) / total;
const scope = reports.length === 1 ? reports[0] : `${reports.length} reports merged`;
console.log(
  `Shell line coverage: ${percent.toFixed(2)}% (${covered}/${total}), minimum ${min}% [${scope}]`
);
if (percent < min) process.exit(1);
