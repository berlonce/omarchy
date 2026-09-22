#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')
JS

# A percentage that covers the whole subscription and a token count that
# covers one machine look identical once they are stacked in the same panel,
# so every section header carries the population its numbers describe.
run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const start = panelSource.indexOf('function scopeSuffix')
const end = panelSource.indexOf('function heroMeta')
assert(start > 0 && end > start, 'agents panel exposes its scope-label helper')
eval(panelSource.slice(start, end))

assertEqual(scopeSuffix('account', 0), ' \u00b7 ACCOUNT', 'agents panel marks account-wide numbers')
assertEqual(scopeSuffix('device', 0), ' \u00b7 THIS MACHINE', 'agents panel marks machine-local numbers')
assertEqual(scopeSuffix('', 0), ' \u00b7 THIS MACHINE', 'agents panel treats an unstated scope as machine-local')
assertEqual(scopeSuffix('synced', 3), ' \u00b7 3 MACHINES', 'agents panel counts the machines behind a merged total')
assertEqual(scopeSuffix('synced', 1), ' \u00b7 SYNCED', 'agents panel does not boast of one machine')

const headers = [
  ['BALANCE', 'root.scopeSuffix("account", 0)'],
  ['LIMITS', 'root.scopeSuffix("account", 0)'],
  ['TOKENS BY DAY', 'root.scopeSuffix(root.daysScope, root.scopeDeviceCount)'],
  ['TOKENS BY MODEL', 'root.scopeSuffix(root.modelUsageScope, root.scopeDeviceCount)']
]
for (const [title, suffix] of headers) {
  assert(
    panelSource.includes(`text: "${title}" + ${suffix}`),
    `agents panel labels the ${title.toLowerCase()} section with its source`
  )
}

// Limits and balances describe the subscription itself. They are never
// merged across machines, so they must not follow a synced day total into
// claiming several machines.
assert(
  !/text: "(LIMITS|BALANCE)" \+ root\.scopeSuffix\((?!"account")/.test(panelSource),
  'agents panel keeps limits and balances account-labelled'
)
JS

# The record's own scope drives those labels, and a collector may scope its
# model split apart from its day totals.
run_node_test <<'JS'
const fs = require('fs')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')
const start = mainSource.indexOf('function displayProvider')
const end = mainSource.indexOf('function setting')
assert(start > 0 && end > start, 'agents plugin exposes its record mapper')

let syncedStats = null
const aggregateData = { deviceCount: 4, updatedAt: '2026-01-01T00:00:00Z' }
function syncedStatsFor() { return syncedStats }
function numberValue(value) { return Number(value || 0) }
function balanceValue() { return null }
eval(mainSource.slice(start, end))

const local = displayProvider({ id: 'claude', name: 'Claude Code' })
assertEqual(local.daysScope, 'device', 'a record without a scope describes this machine')
assertEqual(local.modelUsageScope, 'device', 'its model split describes this machine too')

const account = displayProvider({ id: 'fireworks', name: 'Fireworks', scope: 'account' })
assertEqual(account.daysScope, 'account', 'an account-scoped record describes the whole account')
assertEqual(account.modelUsageScope, 'account', 'and its model split follows that scope')

const split = displayProvider({ id: 'codex', name: 'Codex', scope: 'account', modelUsageScope: 'device' })
assertEqual(split.daysScope, 'account', 'account-wide day totals stay account-scoped')
assertEqual(split.modelUsageScope, 'device', 'a narrower model split keeps its own scope')

syncedStats = { deviceCount: 4 }
const merged = displayProvider({ id: 'codex', name: 'Codex', scope: 'account', modelUsageScope: 'device' })
assertEqual(merged.daysScope, 'synced', 'merged snapshots describe every synced machine')
assertEqual(merged.modelUsageScope, 'synced', 'including the model split they merge')
JS
