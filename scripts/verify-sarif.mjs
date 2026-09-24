#!/usr/bin/env node
// Checks a SARIF file from `codeql database analyze` against the `// $ Alert` markers in examples/.
//
// Each examples/<name>/ directory belongs to one rule, js/openapi-backend/<name>. Every marked line
// must get an alert from that rule, and that rule must alert nowhere else in the directory.
// Alerts from other rules are ignored: fixed.js for one rule may still break another.
//
// Usage: node scripts/verify-sarif.mjs <results.sarif> <examples-dir>

import { readFileSync, readdirSync, appendFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const RULE_OVERRIDES = { 'sql-injection': 'js/sql-injection' };
const SOURCE_EXTENSIONS = /\.(c|m)?(j|t)sx?$/;
const ALERT_MARKER = /\/\/\s*\$\s*Alert\b/;

const ruleForExample = (name) => RULE_OVERRIDES[name] ?? `js/openapi-backend/${name}`;

const toKey = ({ rule, file, line }) => `${rule} ${file}:${line}`;

const listSourceFiles = (dir) =>
  readdirSync(dir, { withFileTypes: true, recursive: true })
    .filter((entry) => entry.isFile() && SOURCE_EXTENSIONS.test(entry.name))
    .map((entry) => join(entry.parentPath, entry.name))
    .filter((path) => !path.split(sep).some((part) => part.endsWith('.testproj')));

const readExpectedAlerts = (examplesDir) =>
  listSourceFiles(examplesDir).flatMap((path) => {
    const file = relative(examplesDir, path).split(sep).join('/');
    const rule = ruleForExample(file.split('/')[0]);
    return readFileSync(path, 'utf8')
      .split('\n')
      .flatMap((text, index) => (ALERT_MARKER.test(text) ? [{ rule, file, line: index + 1 }] : []));
  });

const readActualAlerts = (sarifPath) => {
  const sarif = JSON.parse(readFileSync(sarifPath, 'utf8'));
  return sarif.runs.flatMap((run) =>
    (run.results ?? []).flatMap((result) => {
      const rule = result.ruleId ?? run.tool.driver.rules?.[result.ruleIndex]?.id;
      const location = result.locations?.[0]?.physicalLocation;
      if (!rule || !location) return [];
      const file = location.artifactLocation.uri;
      if (ruleForExample(file.split('/')[0]) !== rule) return [];
      return [{ rule, file, line: location.region.startLine }];
    }),
  );
};

const difference = (params) => {
  const exclude = new Set(params.exclude.map(toKey));
  return [...new Map(params.from.map((alert) => [toKey(alert), alert])).values()].filter(
    (alert) => !exclude.has(toKey(alert)),
  );
};

const summarize = (params) => {
  const { expected, actual, missing, unexpected } = params;
  const rules = [...new Set(expected.map((alert) => alert.rule))].sort();
  const rows = rules.map((rule) => {
    const count = (alerts) => alerts.filter((alert) => alert.rule === rule).length;
    const ok = count(missing) === 0 && count(unexpected) === 0;
    return `| ${ok ? '✅' : '❌'} | \`${rule}\` | ${count(expected)} | ${count(actual)} | ${count(missing)} | ${count(unexpected)} |`;
  });
  const details = [
    ...missing.map((alert) => `- missing: \`${toKey(alert)}\``),
    ...unexpected.map((alert) => `- unexpected: \`${toKey(alert)}\``),
  ];
  return [
    '## Example verification',
    '',
    '| | Rule | Expected | Actual | Missing | Unexpected |',
    '| --- | --- | --- | --- | --- | --- |',
    ...rows,
    '',
    ...details,
  ].join('\n');
};

const [sarifPath, examplesDir] = process.argv.slice(2);
if (!sarifPath || !examplesDir) {
  console.error('Usage: node scripts/verify-sarif.mjs <results.sarif> <examples-dir>');
  process.exit(2);
}

const expected = readExpectedAlerts(examplesDir);
const actual = readActualAlerts(sarifPath);
const missing = difference({ from: expected, exclude: actual });
const unexpected = difference({ from: actual, exclude: expected });
const summary = summarize({ expected, actual, missing, unexpected });

console.log(summary);
if (process.env.GITHUB_STEP_SUMMARY) {
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${summary}\n`);
}
process.exit(missing.length === 0 && unexpected.length === 0 ? 0 : 1);
