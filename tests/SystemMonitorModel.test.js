'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const Model = require('../SystemMonitorModel.js')

const KI = 1024
const MI = KI * KI
const GI = MI * KI
const TI = GI * KI

function sampleStats(overrides) {
  return Object.assign({
    total: 1000,
    idle: 500,
    memoryTotal: 16000,
    memoryAvailable: 8000,
    received: 1000,
    transmitted: 2000,
    loadOne: 1.5,
    loadFive: 1.25,
    loadFifteen: 1,
    uptime: 3600
  }, overrides || {})
}

describe('module shape', () => {
  it('exports exactly the contracted API', () => {
    assert.deepEqual(Object.keys(Model).sort(), [
      'appendHistory', 'buildBoundedCommand', 'buildPidfdSignalCommand', 'buildPsCommand',
      'calculateSystemMetrics', 'chipMonitorEnabled', 'chipMonitorIds', 'clampPercent',
      'commandOutputLimit', 'compareProcessRows', 'defaultChipMonitors',
      'filterAndSortProcesses', 'findProcessByPid', 'finiteNumber', 'formatBytes',
      'formatCompactRate', 'formatCompactUptime', 'formatLoad', 'formatPercent',
      'formatRate', 'formatUptime', 'isSensorMonitorId', 'localFilePath',
      'networkScaleFor', 'normalizeChipMode', 'normalizeChipMonitors',
      'normalizeHardwareValue', 'normalizeStartToken', 'parseCpuInfo', 'parseDiskOutput',
      'parseGpuOutput', 'parseKernelInfo', 'parseLspciGraphics', 'parseMemInfo',
      'parseNvidiaHardware', 'parseOsRelease', 'parsePsOutput', 'parseSensorsJson',
      'parseStatsOutput', 'recentHistory', 'sensorMonitorId', 'sensorMonitorType',
      'toggleChipMonitor', 'utilizationLevel'
    ])
    for (const name of Object.keys(Model)) assert.equal(typeof Model[name], 'function', name)
  })
})

describe('finiteNumber', () => {
  it('passes finite values through', () => {
    assert.equal(Model.finiteNumber(5, -1), 5)
    assert.equal(Model.finiteNumber(3.5, -1), 3.5)
    assert.equal(Model.finiteNumber(-2, -1), -2)
  })
  it('coerces numeric strings', () => {
    assert.equal(Model.finiteNumber('3.5', -1), 3.5)
    assert.equal(Model.finiteNumber('', -1), 0) // Number('') === 0, as in production
  })
  it('returns the fallback for non-finite input', () => {
    assert.equal(Model.finiteNumber(NaN, 7), 7)
    assert.equal(Model.finiteNumber(Infinity, 7), 7)
    assert.equal(Model.finiteNumber(-Infinity, 7), 7)
    assert.equal(Model.finiteNumber(undefined, 7), 7)
    assert.equal(Model.finiteNumber('abc', 7), 7)
  })
})

describe('recentHistory', () => {
  it('returns an empty array for missing or non-list history', () => {
    assert.deepEqual(Model.recentHistory(null), [])
    assert.deepEqual(Model.recentHistory(undefined), [])
    assert.deepEqual(Model.recentHistory(42), [])
  })
  it('copies short histories without truncation', () => {
    const input = [1, 2, 3]
    const out = Model.recentHistory(input)
    assert.deepEqual(out, [1, 2, 3])
    assert.notEqual(out, input)
  })
  it('keeps only the last 60 samples', () => {
    const input = []
    for (let i = 0; i < 65; i++) input.push(i)
    const out = Model.recentHistory(input)
    assert.equal(out.length, 60)
    assert.equal(out[0], 5)
    assert.equal(out[59], 64)
    assert.equal(input.length, 65) // input untouched
  })
  it('returns exactly 60 samples as-is at capacity', () => {
    const input = []
    for (let i = 0; i < 60; i++) input.push(i)
    assert.deepEqual(Model.recentHistory(input), input)
  })
})

describe('appendHistory', () => {
  it('starts a fresh history for missing input', () => {
    assert.deepEqual(Model.appendHistory(null, 7), [7])
    assert.deepEqual(Model.appendHistory(undefined, 7), [7])
  })
  it('appends without mutating the input', () => {
    const input = [1, 2]
    const out = Model.appendHistory(input, 3)
    assert.deepEqual(out, [1, 2, 3])
    assert.deepEqual(input, [1, 2])
  })
  it('drops the oldest samples past 60', () => {
    const input = []
    for (let i = 0; i < 61; i++) input.push(i)
    const out = Model.appendHistory(input, 999)
    assert.equal(out.length, 60)
    assert.equal(out[0], 2)
    assert.equal(out[59], 999)
    assert.equal(input.length, 61)
  })
  it('rolls over exactly at capacity', () => {
    const input = []
    for (let i = 0; i < 60; i++) input.push(i)
    const out = Model.appendHistory(input, 999)
    assert.equal(out.length, 60)
    assert.equal(out[0], 1)
    assert.equal(out[59], 999)
  })
})

describe('clampPercent', () => {
  it('clamps out-of-range values to 0 and 100', () => {
    assert.equal(Model.clampPercent(-0.1), 0)
    assert.equal(Model.clampPercent(-9000), 0)
    assert.equal(Model.clampPercent(100.5), 100)
    assert.equal(Model.clampPercent(9000), 100)
  })
  it('keeps in-range values including boundaries', () => {
    assert.equal(Model.clampPercent(0), 0)
    assert.equal(Model.clampPercent(100), 100)
    assert.equal(Model.clampPercent(42.7), 42.7)
  })
  it('treats non-finite input as 0', () => {
    assert.equal(Model.clampPercent(NaN), 0)
    assert.equal(Model.clampPercent(undefined), 0)
    assert.equal(Model.clampPercent('abc'), 0)
  })
})

describe('formatPercent', () => {
  it('formats rounded clamped percents', () => {
    assert.equal(Model.formatPercent(0), '0%')
    assert.equal(Model.formatPercent(42.4), '42%')
    assert.equal(Model.formatPercent(42.5), '43%')
    assert.equal(Model.formatPercent(100), '100%')
  })
  it('clamps and falls back before formatting', () => {
    assert.equal(Model.formatPercent(-5), '0%')
    assert.equal(Model.formatPercent(149.6), '100%')
    assert.equal(Model.formatPercent(NaN), '0%')
    assert.equal(Model.formatPercent('87.4'), '87%')
  })
})

describe('formatRate', () => {
  it('returns 0 B/s for zero, negative, and non-finite input', () => {
    assert.equal(Model.formatRate(0), '0 B/s')
    assert.equal(Model.formatRate(-100), '0 B/s')
    assert.equal(Model.formatRate(NaN), '0 B/s')
    assert.equal(Model.formatRate('abc'), '0 B/s')
  })
  it('formats the byte tier with rounding', () => {
    assert.equal(Model.formatRate(512), '512 B/s')
    assert.equal(Model.formatRate(512.4), '512 B/s')
    assert.equal(Model.formatRate(1023.5), '1024 B/s')
  })
  it('formats KiB and MiB tiers with one decimal below 10', () => {
    assert.equal(Model.formatRate(KI), '1.0 KiB/s')
    assert.equal(Model.formatRate(1.5 * KI), '1.5 KiB/s')
    assert.equal(Model.formatRate(10 * KI - 0.1), '10.0 KiB/s')
    assert.equal(Model.formatRate(10 * KI), '10 KiB/s')
    assert.equal(Model.formatRate(1.5 * MI), '1.5 MiB/s')
    assert.equal(Model.formatRate(10 * MI), '10 MiB/s')
  })
  it('formats the GiB tier including values past 10 GiB/s', () => {
    assert.equal(Model.formatRate(GI), '1.0 GiB/s')
    assert.equal(Model.formatRate(2.5 * GI), '2.5 GiB/s')
    assert.equal(Model.formatRate(10 * GI), '10 GiB/s')
    assert.equal(Model.formatRate(3 * TI), '3072 GiB/s')
  })
})

describe('formatCompactRate', () => {
  it('returns 0B for zero, negative, and non-finite input', () => {
    assert.equal(Model.formatCompactRate(0), '0B')
    assert.equal(Model.formatCompactRate(-5), '0B')
    assert.equal(Model.formatCompactRate(NaN), '0B')
    assert.equal(Model.formatCompactRate(Infinity), '0B')
  })
  it('keeps compact bytes and kibibytes within four characters', () => {
    assert.equal(Model.formatCompactRate(100.4), '100B')
    assert.equal(Model.formatCompactRate(999.4), '999B')
    assert.equal(Model.formatCompactRate(999.5), '1.0K')
    assert.equal(Model.formatCompactRate(1023.6), '1.0K')
    assert.equal(Model.formatCompactRate(KI), '1K')
    assert.equal(Model.formatCompactRate(1.5 * KI), '2K')
    assert.equal(Model.formatCompactRate(2.5 * KI), '3K')
    assert.equal(Model.formatCompactRate(999.4 * KI), '999K')
    assert.equal(Model.formatCompactRate(999.5 * KI), '1.0M')
  })
  it('formats mebibytes without growing at double-digit values', () => {
    assert.equal(Model.formatCompactRate(MI), '1.0M')
    assert.equal(Model.formatCompactRate(1.5 * MI), '1.5M')
    assert.equal(Model.formatCompactRate(10 * MI), '10M')
    assert.equal(Model.formatCompactRate(20.8 * MI), '21M')
    assert.equal(Model.formatCompactRate(999.5 * MI), '1.0G')
  })
  it('rolls large rates through gibibytes and tebibytes', () => {
    assert.equal(Model.formatCompactRate(GI), '1.0G')
    assert.equal(Model.formatCompactRate(20 * GI), '20G')
    assert.equal(Model.formatCompactRate(999.5 * GI), '1.0T')
    assert.equal(Model.formatCompactRate(TI), '1.0T')
    assert.equal(Model.formatCompactRate(20 * TI), '20T')
  })
})

describe('formatBytes', () => {
  it('returns 0 B for zero, negative, and non-finite input', () => {
    assert.equal(Model.formatBytes(0), '0 B')
    assert.equal(Model.formatBytes(-10), '0 B')
    assert.equal(Model.formatBytes(NaN), '0 B')
    assert.equal(Model.formatBytes('abc'), '0 B')
  })
  it('formats every binary tier with one decimal', () => {
    assert.equal(Model.formatBytes(512), '512 B')
    assert.equal(Model.formatBytes(1023), '1023 B')
    assert.equal(Model.formatBytes(KI), '1.0 KiB')
    assert.equal(Model.formatBytes(1.5 * KI), '1.5 KiB')
    assert.equal(Model.formatBytes(MI), '1.0 MiB')
    assert.equal(Model.formatBytes(1.5 * MI), '1.5 MiB')
    assert.equal(Model.formatBytes(GI), '1.0 GiB')
    assert.equal(Model.formatBytes(2.5 * GI), '2.5 GiB')
    assert.equal(Model.formatBytes(TI), '1.0 TiB')
    assert.equal(Model.formatBytes(3.5 * TI), '3.5 TiB')
  })
})

describe('formatUptime', () => {
  it('shows at least one minute', () => {
    assert.equal(Model.formatUptime(0), '1m')
    assert.equal(Model.formatUptime(59), '1m')
    assert.equal(Model.formatUptime(60), '1m')
    assert.equal(Model.formatUptime(-100), '1m')
    assert.equal(Model.formatUptime(NaN), '1m')
  })
  it('formats minutes and hours', () => {
    assert.equal(Model.formatUptime(125), '2m')
    assert.equal(Model.formatUptime(3599), '59m')
    assert.equal(Model.formatUptime(3600), '1h 0m')
    assert.equal(Model.formatUptime(3661), '1h 1m')
    assert.equal(Model.formatUptime(86399), '23h 59m')
  })
  it('formats days once they exist', () => {
    assert.equal(Model.formatUptime(86400), '1d 0h 0m')
    assert.equal(Model.formatUptime(90061), '1d 1h 1m')
    assert.equal(Model.formatUptime(2 * 86400 + 3 * 3600 + 4 * 60), '2d 3h 4m')
  })
})

describe('formatCompactUptime', () => {
  it('shows at least one minute', () => {
    assert.equal(Model.formatCompactUptime(0), '1m')
    assert.equal(Model.formatCompactUptime(59), '1m')
    assert.equal(Model.formatCompactUptime(60), '1m')
    assert.equal(Model.formatCompactUptime(-100), '1m')
    assert.equal(Model.formatCompactUptime(NaN), '1m')
    assert.equal(Model.formatCompactUptime(Infinity), '1m')
  })
  it('formats minutes-only below one hour', () => {
    assert.equal(Model.formatCompactUptime(125), '2m')
    assert.equal(Model.formatCompactUptime(3599), '59m')
  })
  it('drops minutes once hours exist', () => {
    assert.equal(Model.formatCompactUptime(3600), '1h 0m')
    assert.equal(Model.formatCompactUptime(3661), '1h 1m')
    assert.equal(Model.formatCompactUptime(7325), '2h 2m')
    assert.equal(Model.formatCompactUptime(86399), '23h 59m')
  })
  it('drops hours once days exist', () => {
    assert.equal(Model.formatCompactUptime(86400), '1d 0h')
    assert.equal(Model.formatCompactUptime(90061), '1d 1h')
    assert.equal(Model.formatCompactUptime(2 * 86400 + 3 * 3600 + 4 * 60), '2d 3h')
    assert.equal(Model.formatCompactUptime(400 * 86400), '400d 0h')
  })
  it('coerces numeric strings like the other formatters', () => {
    assert.equal(Model.formatCompactUptime('7200'), '2h 0m')
    assert.equal(Model.formatCompactUptime('bogus'), '1m')
  })
})

describe('formatLoad', () => {
  it('formats two decimals', () => {
    assert.equal(Model.formatLoad(0), '0.00')
    assert.equal(Model.formatLoad(1.236), '1.24')
    assert.equal(Model.formatLoad(4), '4.00')
    assert.equal(Model.formatLoad('2.5'), '2.50')
  })
  it('clamps negatives and non-finite values to 0.00', () => {
    assert.equal(Model.formatLoad(-3), '0.00')
    assert.equal(Model.formatLoad(NaN), '0.00')
    assert.equal(Model.formatLoad(undefined), '0.00')
  })
})

describe('networkScaleFor', () => {
  it('uses the smallest stop that covers quiet histories', () => {
    assert.equal(Model.networkScaleFor([], []), 32 * KI)
    assert.equal(Model.networkScaleFor(null, null), 32 * KI)
    assert.equal(Model.networkScaleFor([100], null), 32 * KI)
    assert.equal(Model.networkScaleFor([2048], []), 32 * KI)
  })
  it('stops at the exact boundary value', () => {
    assert.equal(Model.networkScaleFor([32 * KI], []), 32 * KI)
    assert.equal(Model.networkScaleFor([GI], []), GI)
  })
  it('picks the first stop above the maximum across both histories', () => {
    assert.equal(Model.networkScaleFor([32 * KI + 1], []), 64 * KI)
    assert.equal(Model.networkScaleFor([5 * KI], [100 * KI]), 128 * KI)
  })
  it('ignores negative and non-finite samples', () => {
    assert.equal(Model.networkScaleFor([-5000], []), 32 * KI)
    assert.equal(Model.networkScaleFor([NaN], [2048]), 32 * KI)
  })
  it('doubles past the last stop for extreme traffic', () => {
    assert.equal(Model.networkScaleFor([3 * GI], []), 4 * GI)
    assert.equal(Model.networkScaleFor([2 * GI], []), 2 * GI)
    assert.equal(Model.networkScaleFor([5 * GI], [1024]), 8 * GI)
  })
})

describe('parseDiskOutput', () => {
  const dfOutput = [
    'Filesystem       1024-blocks      Used Available Capacity Mounted on',
    '/dev/nvme0n1p2  2000000000000 500000000000 1500000000000  25% /'
  ].join('\n')

  it('parses df -P -B1 output into bytes and a rounded percent', () => {
    assert.deepEqual(Model.parseDiskOutput(dfOutput), {
      totalBytes: 2000000000000,
      usedBytes: 500000000000,
      usedPercent: 25
    })
  })
  it('clamps the percent to 0 and 100', () => {
    const header = 'Filesystem 1024-blocks Used Available Capacity Mounted on'
    assert.equal(Model.parseDiskOutput(header + '\n/dev/x 1000 3000 0 300% /').usedPercent, 100)
    assert.equal(Model.parseDiskOutput(header + '\n/dev/x 1000 0 1000 0% /').usedPercent, 0)
  })
  it('returns null for malformed output', () => {
    assert.equal(Model.parseDiskOutput(''), null)
    assert.equal(Model.parseDiskOutput(null), null)
    assert.equal(Model.parseDiskOutput('only one line'), null)
    assert.equal(Model.parseDiskOutput('header\n/dev/x 1000 2000'), null) // last line too short
    assert.equal(Model.parseDiskOutput('header\n/dev/x N/A 2000 1000 66% /'), null)
    assert.equal(Model.parseDiskOutput('header\n/dev/x 0 0 0 0% /'), null) // total must be positive
    assert.equal(Model.parseDiskOutput('header\n/dev/x 1000 -5 1000 0% /'), null) // used must be >= 0
  })
})

describe('parseGpuOutput', () => {
  it('parses nvidia-smi csv output with or without spaces', () => {
    const expected = { usage: 45, memoryUsedMiB: 8192, memoryTotalMiB: 16384, temperature: 65 }
    assert.deepEqual(Model.parseGpuOutput('45, 8192, 16384, 65'), expected)
    assert.deepEqual(Model.parseGpuOutput('45,8192,16384,65'), expected)
    assert.deepEqual(Model.parseGpuOutput('  45, 8192, 16384, 65\n0, 0, 0, 0'), expected)
  })
  it('rounds and clamps usage, keeps memory values, rounds temperature', () => {
    assert.deepEqual(
      Model.parseGpuOutput('45.4, 8192.6, 16384, 65.7'),
      { usage: 45, memoryUsedMiB: 8192.6, memoryTotalMiB: 16384, temperature: 66 }
    )
    assert.deepEqual(
      Model.parseGpuOutput('150, 8192, 16384, 65'),
      { usage: 100, memoryUsedMiB: 8192, memoryTotalMiB: 16384, temperature: 65 }
    )
    assert.deepEqual(
      Model.parseGpuOutput('-5, -100, 16384, 65'),
      { usage: 0, memoryUsedMiB: 0, memoryTotalMiB: 16384, temperature: 65 }
    )
  })
  it('parses a missing temperature as -1 without failing', () => {
    assert.deepEqual(
      Model.parseGpuOutput('45, 8192, 16384, [N/A]'),
      { usage: 45, memoryUsedMiB: 8192, memoryTotalMiB: 16384, temperature: -1 }
    )
  })
  it('returns null for malformed output', () => {
    assert.equal(Model.parseGpuOutput(''), null)
    assert.equal(Model.parseGpuOutput(null), null)
    assert.equal(Model.parseGpuOutput('45, 8192, 16384'), null) // too few fields
    assert.equal(Model.parseGpuOutput('x, 1, 2, 3'), null)
    assert.equal(Model.parseGpuOutput('45, 8192, 0, 65'), null) // total must be positive
    assert.equal(Model.parseGpuOutput('45, N/A, 16384, 65'), null)
  })
})

describe('parseStatsOutput', () => {
  it('parses ten whitespace-separated numbers into the stats object', () => {
    assert.deepEqual(Model.parseStatsOutput('1000 500 16000 8000 123456 654321 1.5 1.25 1 3600'), {
      total: 1000,
      idle: 500,
      memoryTotal: 16000,
      memoryAvailable: 8000,
      received: 123456,
      transmitted: 654321,
      loadOne: 1.5,
      loadFive: 1.25,
      loadFifteen: 1,
      uptime: 3600
    })
  })
  it('tolerates mixed whitespace and surrounding padding', () => {
    const stats = Model.parseStatsOutput('  1000\t500\n16000 8000 1 2 0 0 0 3600  ')
    assert.equal(stats.total, 1000)
    assert.equal(stats.uptime, 3600)
  })
  it('accepts negative numbers as finite and leaves range checks downstream', () => {
    assert.equal(Model.parseStatsOutput('-1 -1 0 0 0 0 0 0 0 0').total, -1)
  })
  it('returns null for the wrong field count or non-numeric fields', () => {
    assert.equal(Model.parseStatsOutput(''), null)
    assert.equal(Model.parseStatsOutput('1 2 3 4 5 6 7 8 9'), null)
    assert.equal(Model.parseStatsOutput('1 2 3 4 5 6 7 8 9 10 11'), null)
    assert.equal(Model.parseStatsOutput('1 2 3 4 5 6 7 8 x 10'), null)
    assert.equal(Model.parseStatsOutput('1 2 3 4 5 6 7 8 9 1e999'), null) // Infinity is not finite
  })
})

describe('calculateSystemMetrics', () => {
  it('returns null without a current sample', () => {
    assert.equal(Model.calculateSystemMetrics(null, sampleStats(), 0, 2000), null)
  })
  it('first sample: cpu null, memory computed, rates zero', () => {
    const metrics = Model.calculateSystemMetrics(sampleStats(), null, 0, 1000)
    assert.deepEqual(metrics, {
      cpuValue: null,
      memoryValue: 50,
      receiveRate: 0,
      transmitRate: 0
    })
  })
  it('second sample: cpu delta, memory share, byte-rate deltas', () => {
    const previous = sampleStats()
    const current = sampleStats({ total: 2000, idle: 750, received: 3000, transmitted: 2600 })
    const metrics = Model.calculateSystemMetrics(current, previous, 1000, 3000)
    assert.equal(metrics.cpuValue, 75) // 100 * (1 - 250/1000)
    assert.equal(metrics.memoryValue, 50)
    assert.equal(metrics.receiveRate, 1000) // (3000 - 1000) / 2
    assert.equal(metrics.transmitRate, 300) // (2600 - 2000) / 2
  })
  it('cpu counter reset yields null cpu but still computes memory and rates', () => {
    const previous = sampleStats()
    const current = sampleStats({ total: 500, received: 3000, transmitted: 2600 })
    const metrics = Model.calculateSystemMetrics(current, previous, 1000, 3000)
    assert.equal(metrics.cpuValue, null)
    assert.equal(metrics.memoryValue, 50)
    assert.equal(metrics.receiveRate, 1000)
    assert.equal(metrics.transmitRate, 300)
  })
  it('negative previous total blocks the cpu delta', () => {
    const previous = sampleStats({ total: -1 })
    const current = sampleStats({ total: 10 })
    assert.equal(Model.calculateSystemMetrics(current, previous, 1000, 3000).cpuValue, null)
  })
  it('network counter reset clamps the rate to zero per direction', () => {
    const previous = sampleStats()
    const current = sampleStats({ received: 500, transmitted: 2600 })
    const metrics = Model.calculateSystemMetrics(current, previous, 1000, 3000)
    assert.equal(metrics.receiveRate, 0)
    assert.equal(metrics.transmitRate, 300)
  })
  it('non-positive or missing elapsed time zeroes the rates but keeps cpu', () => {
    const previous = sampleStats()
    const current = sampleStats({ total: 2000, idle: 750 })
    for (const elapsed of [0, -1, undefined, NaN]) {
      const now = elapsed === undefined ? undefined : 1000 + elapsed * 1000
      const metrics = Model.calculateSystemMetrics(current, previous, 1000, now)
      assert.equal(metrics.cpuValue, 75)
      assert.equal(metrics.receiveRate, 0)
      assert.equal(metrics.transmitRate, 0)
    }
  })
  it('clamps cpu and memory percentages into 0..100', () => {
    const highIdle = Model.calculateSystemMetrics(
      sampleStats({ total: 200, idle: 210 }), sampleStats({ total: 100, idle: 100 }), 1000, 2000)
    assert.equal(highIdle.cpuValue, 0) // idle grew faster than total
    const lowIdle = Model.calculateSystemMetrics(
      sampleStats({ total: 200, idle: 90 }), sampleStats({ total: 100, idle: 100 }), 1000, 2000)
    assert.equal(lowIdle.cpuValue, 100) // idle went backwards
    assert.equal(
      Model.calculateSystemMetrics(sampleStats({ memoryAvailable: 20000 }), null, 0, 1000).memoryValue, 0)
    assert.equal(Model.calculateSystemMetrics(sampleStats({ memoryTotal: 0 }), null, 0, 1000).memoryValue, 0)
  })
})

describe('buildPsCommand', () => {
  const fields = 'pid=,lstart=,pcpu=,pmem=,comm='
  it('wraps ps in a hard 3s timeout with a pinned C locale', () => {
    assert.deepEqual(Model.buildPsCommand('ryan'), [
      'timeout', '--kill-after=1', '3', 'env', 'LC_ALL=C', 'ps', '-u', 'ryan',
      '-o', fields, '--sort=-pcpu'
    ])
    assert.deepEqual(Model.buildPsCommand('  ryan  '), [
      'timeout', '--kill-after=1', '3', 'env', 'LC_ALL=C', 'ps', '-u', 'ryan',
      '-o', fields, '--sort=-pcpu'
    ])
  })
  it('omits -u when no usable username exists', () => {
    const bare = [
      'timeout', '--kill-after=1', '3', 'env', 'LC_ALL=C', 'ps',
      '-o', fields, '--sort=-pcpu'
    ]
    assert.deepEqual(Model.buildPsCommand(''), bare)
    assert.deepEqual(Model.buildPsCommand('   '), bare)
    assert.deepEqual(Model.buildPsCommand(undefined), bare)
    assert.deepEqual(Model.buildPsCommand(null), bare)
  })
  it('returns a fresh argv array per call', () => {
    assert.notEqual(Model.buildPsCommand('a'), Model.buildPsCommand('a'))
  })
})


describe('parsePsOutput', () => {
  const psOutput = [
    '  1234  Mon Aug 25 12:00:01 2026  12.5  4.2  firefox',
    '   7 Wed Sep  3 09:08:15 2025 0.0 0.1 systemd',
    '  99  Tue Aug 25 08:00:00 2026  1.0  0.5  Code Helper (Renderer)',
    '',
    '   ',
    'bad line',
    '  0  Mon Aug 25 12:00:01 2026  1  1  zero-pid',
    '  -5  Mon Aug 25 12:00:01 2026  1  1  negative-pid',
    '  abc  Mon Aug 25 12:00:01 2026  1  1  not-a-pid',
    '  42  Mon Aug 25 12:00:01 2026  x  1  bad-cpu',
    '  43  Mon Aug 25 12:00:01 2026  1  y  bad-memory',
    '  44  Mon Aug 25 12:00:01 2026  1  1',
    '  45  Mon Aug 25 12:00:01 2026  1  1  legacy-four-column-row',
    '  46  Mon Aug 25 12:00:01  1  1  four-token-lstart',
    ''
  ].join('\n')

  it('parses valid rows and skips malformed ones', () => {
    const rows = Model.parsePsOutput(psOutput)
    assert.deepEqual(rows.map(row => row.pid), [1234, 7, 99, 45])
    assert.deepEqual(rows[2], {
      pid: 99,
      name: 'Code Helper (Renderer)',
      search: 'code helper (renderer) 99',
      startToken: 'Tue Aug 25 08:00:00 2026',
      cpu: 1,
      memory: 0.5
    })
  })
  it('collapses padded lstart days into the start token', () => {
    const [row] = Model.parsePsOutput('7 Wed Sep  3 09:08:15 2025 0.0 0.1 systemd')
    assert.equal(row.startToken, 'Wed Sep 3 09:08:15 2025')
  })
  it('keeps multi-word command names intact in search and name', () => {
    const [row] = Model.parsePsOutput(
      '55 Mon Aug 25 09:01:02 2026 0.1 0.2  My Cool App')
    assert.equal(row.name, 'My Cool App')
    assert.equal(row.search, 'my cool app 55')
  })
  it('parses numeric strings for pid with base 10', () => {
    const [row] = Model.parsePsOutput('007 Mon Aug 25 09:01:02 2026 1 1 ws')
    assert.equal(row.pid, 7)
    assert.equal(row.search, 'ws 7')
  })
  it('caps the snapshot at the requested limit', () => {
    const raw = '10 Mon Aug 25 12:00:00 2026 1 1 a\n' +
      '20 Mon Aug 25 12:00:00 2026 2 2 b\n' +
      '30 Mon Aug 25 12:00:00 2026 3 3 c'
    assert.equal(Model.parsePsOutput(raw, 1).length, 1)
    assert.equal(Model.parsePsOutput(raw, 2).length, 2)
    assert.equal(Model.parsePsOutput(raw, 5).length, 3)
  })
  it('defaults the snapshot limit to 400 rows', () => {
    const lines = []
    for (let i = 0; i < 450; i++) {
      lines.push((i + 1) + ' Mon Aug 25 12:00:00 2026 1 1 p' + i)
    }
    const rows = Model.parsePsOutput(lines.join('\n'))
    assert.equal(rows.length, 400)
    assert.equal(rows[0].pid, 1)
    assert.equal(rows[399].pid, 400)
  })
  it('returns null for empty or missing output', () => {
    assert.equal(Model.parsePsOutput(''), null)
    assert.equal(Model.parsePsOutput(null), null)
    assert.equal(Model.parsePsOutput(undefined), null)
  })
})


describe('compareProcessRows', () => {
  const rows = [
    { pid: 1, name: 'alpha', cpu: 10, memory: 1 },
    { pid: 2, name: 'beta', cpu: 5, memory: 2 },
    { pid: 3, name: 'alpha', cpu: 10, memory: 1 }
  ]

  it('sorts by cpu descending by default and via explicit key', () => {
    assert.equal(Model.compareProcessRows(rows[0], rows[1]), -5)
    assert.equal(Model.compareProcessRows(rows[1], rows[0]), 5)
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'cpu'), -5)
  })
  it('sorts by memory descending when requested', () => {
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'memory'), 1)
    assert.equal(Model.compareProcessRows(rows[1], rows[0], 'memory'), -1)
  })
  it('sorts numeric columns ascending when requested', () => {
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'cpu', false), 5)
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'memory', false), -1)
  })
  it('sorts names case-insensitively in either direction', () => {
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'name', false), -1)
    assert.equal(Model.compareProcessRows(rows[0], rows[1], 'name', true), 1)
    assert.equal(Model.compareProcessRows(
      { name: 'Alpha' }, { name: 'alpha' }, 'name', false), 0)
  })
  it('breaks ties by name ascending, then equal', () => {
    assert.equal(Model.compareProcessRows(rows[0], rows[2]), 0)
    const a = { pid: 1, name: 'b', cpu: 1, memory: 1 }
    const b = { pid: 2, name: 'a', cpu: 1, memory: 1 }
    assert.equal(Model.compareProcessRows(a, b, 'memory'), 1)
    assert.equal(Model.compareProcessRows(b, a, 'memory'), -1)
  })
})

describe('filterAndSortProcesses', () => {
  const firefox = { pid: 100, name: 'firefox', search: 'firefox 100', cpu: 30, memory: 10 }
  const chrome = { pid: 200, name: 'chrome', search: 'chrome 200', cpu: 50, memory: 5 }
  const code = { pid: 300, name: 'code', search: 'code helper 300', cpu: 20, memory: 40 }
  const processes = [firefox, chrome, code]

  it('returns everything sorted by cpu when the query is blank', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, ''), [chrome, firefox, code])
    assert.deepEqual(Model.filterAndSortProcesses(processes, '   '), [chrome, firefox, code])
  })
  it('filters case-insensitively on the trimmed query', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, 'FIRE '), [firefox])
    assert.deepEqual(Model.filterAndSortProcesses(processes, '  Chrome  '), [chrome])
  })
  it('matches pids through the search field', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, '200'), [chrome])
    assert.deepEqual(Model.filterAndSortProcesses(processes, 'code helper'), [code])
  })
  it('returns an empty list when nothing matches', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, 'zzz'), [])
    assert.deepEqual(Model.filterAndSortProcesses([], 'fire'), [])
    assert.deepEqual(Model.filterAndSortProcesses(null, 'fire'), [])
    assert.deepEqual(Model.filterAndSortProcesses(null), [])
  })
  it('honors the memory sort key', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'memory', 200),
      [code, firefox, chrome])
  })
  it('sorts alphabetically in either direction', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'name', 200, false),
      [chrome, code, firefox])
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'name', 200, true),
      [firefox, code, chrome])
  })
  it('supports ascending CPU and memory order', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'cpu', 200, false),
      [code, firefox, chrome])
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'memory', 200, false),
      [chrome, firefox, code])
  })
  it('truncates only past the limit', () => {
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'cpu', 1), [chrome])
    assert.deepEqual(Model.filterAndSortProcesses(processes, '', 'cpu', 2), [chrome, firefox])
    assert.equal(Model.filterAndSortProcesses(processes, '', 'cpu', 3).length, 3)
    assert.equal(Model.filterAndSortProcesses(processes, '', 'cpu', 0).length, 3) // 0 falls back to 200
  })
  it('never mutates the input snapshot', () => {
    const snapshot = [code, firefox, chrome]
    Model.filterAndSortProcesses(snapshot, '', 'memory', 200)
    assert.deepEqual(snapshot, [code, firefox, chrome])
  })
  it('breaks sorting ties by name', () => {
    const tieA = { pid: 1, name: 'b-app', search: 'b-app 1', cpu: 5, memory: 0 }
    const tieB = { pid: 2, name: 'a-app', search: 'a-app 2', cpu: 5, memory: 0 }
    assert.deepEqual(Model.filterAndSortProcesses([tieA, tieB], ''), [tieB, tieA])
  })
})

describe('findProcessByPid', () => {
  const rows = [
    { pid: 100, name: 'firefox', startToken: 'Mon Aug 25 12:00:00 2026' },
    { pid: 200, name: 'chrome', startToken: 'Tue Aug 25 08:00:00 2026' }
  ]

  it('finds the row for a live pid and matching birth token', () => {
    assert.equal(Model.findProcessByPid(rows, 100, 'Mon Aug 25 12:00:00 2026'), rows[0])
    assert.equal(Model.findProcessByPid(rows, 200, 'Tue Aug 25 08:00:00 2026'), rows[1])
  })
  it('rejects a reused pid whose birth token differs', () => {
    assert.equal(Model.findProcessByPid(rows, 100, 'Mon Aug 25 13:00:00 2027'), null)
    assert.equal(Model.findProcessByPid(rows, 100, 'Mon Aug 25 12:00:00'), null)
  })
  it('falls back to pid-only matching without a token', () => {
    assert.equal(Model.findProcessByPid(rows, 100), rows[0])
  })
  it('returns null for exited or missing pids', () => {
    assert.equal(Model.findProcessByPid(rows, 999, 'Mon Aug 25 12:00:00 2026'), null)
    assert.equal(Model.findProcessByPid([], 100), null)
    assert.equal(Model.findProcessByPid(null, 100), null)
  })
})

describe('normalizeStartToken', () => {
  it('trims and collapses whitespace runs to single spaces', () => {
    assert.equal(Model.normalizeStartToken('  Mon Aug  5 09:08:15  2026 \n'),
      'Mon Aug 5 09:08:15 2026')
    assert.equal(Model.normalizeStartToken('Mon\tAug 25 12:00:00 2026'),
      'Mon Aug 25 12:00:00 2026')
  })
  it('normalizes absent input to an empty string', () => {
    assert.equal(Model.normalizeStartToken(''), '')
    assert.equal(Model.normalizeStartToken('   '), '')
    assert.equal(Model.normalizeStartToken(null), '')
    assert.equal(Model.normalizeStartToken(undefined), '')
  })
})

describe('buildPidfdSignalCommand', () => {
  it('builds a single helper argv from pid and normalized lstart token', () => {
    assert.deepEqual(Model.buildPidfdSignalCommand('/plugin/bin/pidfd-signal', 1234,
      'Mon Aug  5 09:08:15 2026'), [
      '/plugin/bin/pidfd-signal', '1234', 'Mon Aug 5 09:08:15 2026'
    ])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', '4321', ' Tue  Sep  1 10:00:00 2026 '), [
      '/h', '4321', 'Tue Sep 1 10:00:00 2026'
    ])
  })
  it('refuses invalid pids with an empty argv', () => {
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 0, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', -1, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 12.5, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 'abc', 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', null, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', NaN, 'Mon Jan 1 00:00:00 2026'), [])
  })
  it('refuses a missing identity token — an unconfirmable process is never signalled', () => {
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 1234, ''), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 1234, '   '), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 1234, null), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('/h', 1234, undefined), [])
  })
  it('refuses a missing helper path and returns a fresh argv per call', () => {
    assert.deepEqual(Model.buildPidfdSignalCommand('', 1234, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand('   ', 1234, 'Mon Jan 1 00:00:00 2026'), [])
    assert.deepEqual(Model.buildPidfdSignalCommand(null, 1234, 'Mon Jan 1 00:00:00 2026'), [])
    const a = Model.buildPidfdSignalCommand('/h', 1, 'Mon Jan 1 00:00:00 2026')
    const b = Model.buildPidfdSignalCommand('/h', 1, 'Mon Jan 1 00:00:00 2026')
    assert.notEqual(a, b)
    assert.deepEqual(a, b)
  })
})

// ---- bounded command boundary ----------------------------------------------

describe('localFilePath', () => {
  it('strips a leading file:// and decodes valid percent escapes', () => {
    assert.equal(Model.localFilePath(
      'file:///home/ryan/.config/omarchy/plugins/bitr0t.system-monitor/bin/bounded-command'),
    '/home/ryan/.config/omarchy/plugins/bitr0t.system-monitor/bin/bounded-command')
    assert.equal(Model.localFilePath('file:///home/my%20dir/tool'), '/home/my dir/tool')
    assert.equal(Model.localFilePath('file:///opt/a%2Fb'), '/opt/a/b')
  })
  it('stringifies QUrl-like values and passes plain paths through untouched', () => {
    assert.equal(Model.localFilePath({ toString: () => 'file:///opt/tool' }), '/opt/tool')
    assert.equal(Model.localFilePath('/usr/bin/python3'), '/usr/bin/python3')
    assert.equal(Model.localFilePath('bin/bounded-command'), 'bin/bounded-command')
  })
  it('strips only a leading file://', () => {
    assert.equal(Model.localFilePath('https://example.com/x'), 'https://example.com/x')
    assert.equal(Model.localFilePath('/x/file:///y'), '/x/file:///y')
  })
  it('returns the undecoded stripped value instead of throwing on malformed escapes', () => {
    assert.equal(Model.localFilePath('file:///home/100%/x'), '/home/100%/x')
    assert.equal(Model.localFilePath('file:///a%zz'), '/a%zz')
    assert.equal(Model.localFilePath('file:///a%2'), '/a%2')
    assert.equal(Model.localFilePath('file:///%'), '/%')
  })
  it('normalizes missing input to an empty string', () => {
    assert.equal(Model.localFilePath(null), '')
    assert.equal(Model.localFilePath(undefined), '')
  })
})

describe('commandOutputLimit', () => {
  it('returns the contracted cap for every producer kind', () => {
    assert.equal(Model.commandOutputLimit('stats'), 4096)
    assert.equal(Model.commandOutputLimit('sensors'), 1048576)
    assert.equal(Model.commandOutputLimit('disk'), 16384)
    assert.equal(Model.commandOutputLimit('gpu'), 65536)
    assert.equal(Model.commandOutputLimit('processes'), 2097152)
    assert.equal(Model.commandOutputLimit('lspci'), 1048576)
    assert.equal(Model.commandOutputLimit('uname'), 8192)
    assert.equal(Model.commandOutputLimit('nvidiaInfo'), 65536)
  })
  it('returns 0 for unknown kinds', () => {
    assert.equal(Model.commandOutputLimit('bogus'), 0)
    assert.equal(Model.commandOutputLimit(''), 0)
    assert.equal(Model.commandOutputLimit('Stats'), 0) // kinds are case-sensitive
    assert.equal(Model.commandOutputLimit(null), 0)
    assert.equal(Model.commandOutputLimit(undefined), 0)
    assert.equal(Model.commandOutputLimit('constructor'), 0) // no prototype leak
  })
})

describe('buildBoundedCommand', () => {
  it('wraps a complete producer argv under the helper and cap', () => {
    const ps = ['timeout', '3', 'env', 'LC_ALL=C', 'ps', '-o', 'pid=', '--sort=-pcpu']
    assert.deepEqual(Model.buildBoundedCommand('/plugin/bin/bounded-command', 2097152, ps), [
      '/plugin/bin/bounded-command', '2097152',
      'timeout', '3', 'env', 'LC_ALL=C', 'ps', '-o', 'pid=', '--sort=-pcpu'
    ])
    // numeric-string caps coerce, like every other numeric helper here
    assert.deepEqual(Model.buildBoundedCommand('/h', '4096', ['uname', '-srmo']),
      ['/h', '4096', 'uname', '-srmo'])
  })
  it('accepts the full valid cap range', () => {
    assert.deepEqual(Model.buildBoundedCommand('/h', 1, ['x']), ['/h', '1', 'x'])
    assert.deepEqual(Model.buildBoundedCommand('/h', 8388608, ['x']),
      ['/h', '8388608', 'x'])
  })
  it('refuses caps outside 1..8388608 or non-integers', () => {
    for (const cap of [0, -1, 8388609, 12.5, NaN, Infinity, 'abc', null, undefined])
      assert.deepEqual(Model.buildBoundedCommand('/h', cap, ['x']), [], `cap ${cap}`)
  })
  it('refuses a missing helper path', () => {
    for (const helper of ['', '   ', null, undefined])
      assert.deepEqual(Model.buildBoundedCommand(helper, 4096, ['x']), [], `helper ${helper}`)
  })
  it('refuses an empty or missing argv', () => {
    assert.deepEqual(Model.buildBoundedCommand('/h', 4096, []), [])
    assert.deepEqual(Model.buildBoundedCommand('/h', 4096, null), [])
    assert.deepEqual(Model.buildBoundedCommand('/h', 4096, undefined), [])
    assert.deepEqual(Model.buildBoundedCommand('/h', 4096, 'uname'), [])
    assert.deepEqual(Model.buildBoundedCommand('/h', 4096, { 0: 'uname', length: 1 }), [])
  })
  it('returns a fresh wrapped argv without mutating the producer argv', () => {
    const argv = ['sensors', '-j']
    const first = Model.buildBoundedCommand('/h', 1048576, argv)
    const second = Model.buildBoundedCommand('/h', 1048576, argv)
    assert.deepEqual(argv, ['sensors', '-j']) // input untouched
    assert.notEqual(first, second)            // fresh array per call
    assert.deepEqual(first, second)
    first.push('poison')                      // results never share state
    assert.deepEqual(Model.buildBoundedCommand('/h', 1048576, argv),
      ['/h', '1048576', 'sensors', '-j'])
  })
})

describe('utilizationLevel', () => {
  it('maps thresholds to levels with inclusive boundaries', () => {
    assert.equal(Model.utilizationLevel(0), 'normal')
    assert.equal(Model.utilizationLevel(69.9), 'normal')
    assert.equal(Model.utilizationLevel(70), 'warning')
    assert.equal(Model.utilizationLevel(89.9), 'warning')
    assert.equal(Model.utilizationLevel(90), 'critical')
    assert.equal(Model.utilizationLevel(100), 'critical')
    assert.equal(Model.utilizationLevel(150), 'critical')
  })
  it('treats non-finite values as normal', () => {
    assert.equal(Model.utilizationLevel(NaN), 'normal')
    assert.equal(Model.utilizationLevel(-5), 'normal')
    assert.equal(Model.utilizationLevel(undefined), 'normal')
  })
})

describe('chipMonitorIds / defaultChipMonitors', () => {
  it('list monitors in the fixed chip order', () => {
    assert.deepEqual(Model.chipMonitorIds(), ['cpu', 'memory', 'gpu', 'network', 'load', 'uptime'])
    assert.deepEqual(Model.defaultChipMonitors(), ['cpu', 'memory', 'network'])
    for (const id of Model.defaultChipMonitors()) {
      assert.ok(Model.chipMonitorIds().includes(id), id)
    }
  })
  it('return fresh arrays so callers cannot poison the constants', () => {
    const ids = Model.chipMonitorIds()
    ids.push('bogus')
    ids.shift()
    assert.deepEqual(Model.chipMonitorIds(), ['cpu', 'memory', 'gpu', 'network', 'load', 'uptime'])

    const defaults = Model.defaultChipMonitors()
    defaults.pop()
    assert.deepEqual(Model.defaultChipMonitors(), ['cpu', 'memory', 'network'])
  })
})

describe('normalizeChipMode', () => {
  it('passes the two valid modes through', () => {
    assert.equal(Model.normalizeChipMode('instrument'), 'instrument')
    assert.equal(Model.normalizeChipMode('minimal'), 'minimal')
  })
  it('falls back to instrument for anything else', () => {
    assert.equal(Model.normalizeChipMode(null), 'instrument')
    assert.equal(Model.normalizeChipMode(undefined), 'instrument')
    assert.equal(Model.normalizeChipMode(''), 'instrument')
    assert.equal(Model.normalizeChipMode('Instrument'), 'instrument') // case-sensitive
    assert.equal(Model.normalizeChipMode('graphs'), 'instrument')
    assert.equal(Model.normalizeChipMode(42), 'instrument')
    assert.equal(Model.normalizeChipMode(true), 'instrument')
  })
})

describe('normalizeChipMonitors', () => {
  it('falls back to defaults for non-array values', () => {
    assert.deepEqual(Model.normalizeChipMonitors(null), ['cpu', 'memory', 'network'])
    assert.deepEqual(Model.normalizeChipMonitors(undefined), ['cpu', 'memory', 'network'])
    assert.deepEqual(Model.normalizeChipMonitors('cpu'), [])
  })
  it('keeps an explicitly empty selection', () => {
    assert.deepEqual(Model.normalizeChipMonitors([]), [])
  })
  it('keeps GPU and drops unknown ids', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors(['cpu', 'gpu', 'swap', 'memory']),
      ['cpu', 'memory', 'gpu'])
    assert.deepEqual(Model.normalizeChipMonitors(['bogus']), [])
  })
  it('deduplicates repeated ids', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors(['cpu', 'cpu', 'memory', 'memory']),
      ['cpu', 'memory'])
  })
  it('restores the canonical chip order', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors(['uptime', 'network', 'memory', 'cpu', 'load']),
      ['cpu', 'memory', 'network', 'load', 'uptime'])
  })
  it('returns a fresh array without mutating the input', () => {
    const input = ['network', 'cpu']
    const normalized = Model.normalizeChipMonitors(input)
    assert.deepEqual(input, ['network', 'cpu'])
    normalized.push('cpu')
    assert.deepEqual(Model.normalizeChipMonitors(input), ['cpu', 'network'])
  })
})

describe('toggleChipMonitor', () => {
  it('enables a monitor in canonical position', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'memory', true), ['cpu', 'memory'])
    assert.deepEqual(Model.toggleChipMonitor(['memory'], 'cpu', true), ['cpu', 'memory'])
    assert.deepEqual(Model.toggleChipMonitor([], 'uptime', true), ['uptime'])
    assert.deepEqual(Model.toggleChipMonitor(['network'], 'gpu', true), ['gpu', 'network'])
    // enabling onto defaults starts from the default selection
    assert.deepEqual(
      Model.toggleChipMonitor(null, 'load', true),
      ['cpu', 'memory', 'network', 'load'])
  })
  it('enabling an already-enabled monitor is a no-op', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu', 'memory'], 'cpu', true), ['cpu', 'memory'])
  })
  it('disables a monitor and keeps the rest', () => {
    assert.deepEqual(
      Model.toggleChipMonitor(['cpu', 'memory', 'network'], 'memory', false),
      ['cpu', 'network'])
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'cpu', false), [])
  })
  it('disabling an absent monitor changes nothing', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu', 'network'], 'memory', false),
      ['cpu', 'network'])
  })
  it('ignores unknown ids', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'bogus', true), ['cpu'])
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'bogus', false), ['cpu'])
    assert.deepEqual(Model.toggleChipMonitor(null, '', true), ['cpu', 'memory', 'network'])
  })
  it('never mutates the input array', () => {
    const input = ['network', 'cpu']
    const enabled = Model.toggleChipMonitor(input, 'memory', true)
    assert.deepEqual(input, ['network', 'cpu'])
    assert.notEqual(enabled, input)

    const disabled = Model.toggleChipMonitor(input, 'cpu', false)
    assert.deepEqual(input, ['network', 'cpu'])
    assert.deepEqual(disabled, ['network'])
  })
  it('round-trips toggling every monitor off and back on', () => {
    let selection = Model.defaultChipMonitors()
    for (const id of Model.chipMonitorIds()) {
      selection = Model.toggleChipMonitor(selection, id, false)
      assert.equal(Model.toggleChipMonitor(selection, id, false).length, selection.length)
    }
    assert.deepEqual(selection, [])
    for (const id of Model.defaultChipMonitors()) {
      selection = Model.toggleChipMonitor(selection, id, true)
    }
    assert.deepEqual(selection, ['cpu', 'memory', 'network'])
  })
})

describe('chipMonitorEnabled', () => {
  it('reports membership for arrays', () => {
    assert.equal(Model.chipMonitorEnabled(['cpu', 'memory'], 'cpu'), true)
    assert.equal(Model.chipMonitorEnabled(['cpu', 'memory'], 'network'), false)
    assert.equal(Model.chipMonitorEnabled([], 'cpu'), false)
  })
  it('checks the defaults for non-array values', () => {
    assert.equal(Model.chipMonitorEnabled(null, 'cpu'), true)
    assert.equal(Model.chipMonitorEnabled(undefined, 'network'), true)
    assert.equal(Model.chipMonitorEnabled(null, 'load'), false)
  })
  it('unknown ids are never enabled', () => {
    assert.equal(Model.chipMonitorEnabled(['cpu'], 'bogus'), false)
    assert.equal(Model.chipMonitorEnabled(Model.chipMonitorIds(), ''), false)
  })
})

// ---- dynamic sensor monitors ----------------------------------------------

// Fixture mirroring this machine's actual `sensors -j` payload: k10temp CPU
// Tctl/Tccd, two NVMe controllers, an AMD GPU (edge plus voltage/power/
// frequency channels), motherboard generics (acpitz, gigabyte_wmi), a NIC
// PHY, wifi, and an AIO cooler (coolant, pump, fan, pwm channels).
const SENSORS_JSON = '{' +
  '"iwlwifi_1_1-virtual-0":{"Adapter":"Virtual device","temp1":{"temp1_input":36.000000}},' +
  '"r8169_0_800:00-mdio-0":{"Adapter":"MDIO adapter","temp1":{"temp1_input":39.000000,"temp1_max":120.000000}},' +
  '"k10temp-pci-00c3":{"Adapter":"PCI adapter","Tctl":{"temp1_input":56.625000},"Tccd1":{"temp3_input":46.000000}},' +
  '"nvme-pci-1000":{"Adapter":"PCI adapter","Composite":{"temp1_input":38.850000,"temp1_max":80.850000,"temp1_min":-273.150000,"temp1_crit":84.850000,"temp1_alarm":0.000000},"Sensor 1":{"temp2_input":45.850000,"temp2_max":65261.850000,"temp2_min":-273.150000},"Sensor 2":{"temp3_input":38.850000,"temp3_max":65261.850000,"temp3_min":-273.150000}},' +
  '"acpitz_0-acpi-0":{"Adapter":"ACPI interface","temp1":{"temp1_input":16.800000}},' +
  '"z53-hid-3-8":{"Adapter":"HID adapter","Pump speed":{"fan1_input":2197.000000},"Fan speed":{"fan2_input":1050.000000},"Coolant temp":{"temp1_input":33.000000},"pwm1":{"pwm1":89.500000,"pwm1_enable":0.000000},"pwm2":{"pwm2":64.000000,"pwm2_enable":0.000000}},' +
  '"gigabyte_wmi-virtual-0":{"Adapter":"Virtual device","temp1":{"temp1_input":30.000000},"temp2":{"temp2_input":43.000000},"temp3":{"temp3_input":56.000000},"temp4":{"temp4_input":37.000000},"temp5":{"temp5_input":37.000000},"temp6":{"temp6_input":39.000000}},' +
  '"amdgpu-pci-1100":{"Adapter":"PCI adapter","vddgfx":{"in0_input":1.050000},"vddnb":{"in1_input":1.240000},"edge":{"temp1_input":43.000000},"PPT":{"power1_input":50.942000},"sclk":{"freq1_input":2200000000.000000}},' +
  '"nvme-pci-0200":{"Adapter":"PCI adapter","Composite":{"temp1_input":39.850000,"temp1_max":89.850000,"temp1_min":-0.150000,"temp1_crit":94.850000,"temp1_alarm":0.000000}}' +
  '}'

describe('sensorMonitorId', () => {
  it('builds stable prefixed ids with URI-encoded components', () => {
    assert.equal(
      Model.sensorMonitorId('temperature', 'k10temp-pci-00c3', 'Tctl', 'temp1_input'),
      'sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input')
    assert.equal(
      Model.sensorMonitorId('fan', 'z53-hid-3-8', 'Pump speed', 'fan1_input'),
      'sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input')
    assert.equal(
      Model.sensorMonitorId('temperature', 'r8169_0_800:00-mdio-0', 'temp1', 'temp1_input'),
      'sensor:temperature:r8169_0_800%3A00-mdio-0:temp1:temp1_input')
    // deterministic: identical inputs always yield the identical id
    assert.equal(
      Model.sensorMonitorId('fan', 'z53-hid-3-8', 'Fan speed', 'fan2_input'),
      Model.sensorMonitorId('fan', 'z53-hid-3-8', 'Fan speed', 'fan2_input'))
  })
  it('returns null for anything but a temperature/fan source', () => {
    assert.equal(Model.sensorMonitorId('gpu', 'a', 'b', 'c'), null)
    assert.equal(Model.sensorMonitorId('', 'a', 'b', 'c'), null)
    assert.equal(Model.sensorMonitorId(null, 'a', 'b', 'c'), null)
    assert.equal(Model.sensorMonitorId('temperature', '', 'b', 'c'), null)
    assert.equal(Model.sensorMonitorId('temperature', 'a', '', 'c'), null)
    assert.equal(Model.sensorMonitorId('temperature', 'a', 'b', ''), null)
    assert.equal(Model.sensorMonitorId('temperature', null, 'b', 'c'), null)
    assert.equal(Model.sensorMonitorId('temperature', 'a', 'b', null), null)
  })
})

describe('isSensorMonitorId / sensorMonitorType', () => {
  it('recognize well-formed temperature and fan ids', () => {
    const tempId = Model.sensorMonitorId('temperature', 'nvme-pci-1000', 'Composite', 'temp1_input')
    const fanId = Model.sensorMonitorId('fan', 'z53-hid-3-8', 'Fan speed', 'fan2_input')
    assert.equal(Model.isSensorMonitorId(tempId), true)
    assert.equal(Model.sensorMonitorType(tempId), 'temperature')
    assert.equal(Model.isSensorMonitorId(fanId), true)
    assert.equal(Model.sensorMonitorType(fanId), 'fan')
  })
  it('reject fixed, malformed and non-string ids', () => {
    const rejected = [
      'cpu', 'memory', '', 'sensor', 'sensor:temperature', 'sensor:gpu:a:b:c',
      'sensor:temperature:a:b', 'sensor:temperature:a:b:c:d', 'sensor::a:b:c',
      'sensor:temperature::b:c', 'not-a-sensor-id']
    for (const id of rejected) {
      assert.equal(Model.isSensorMonitorId(id), false, id)
      assert.equal(Model.sensorMonitorType(id), null, id)
    }
    assert.equal(Model.isSensorMonitorId(null), false)
    assert.equal(Model.sensorMonitorType(null), null)
    assert.equal(Model.isSensorMonitorId(42), false)
    assert.equal(Model.sensorMonitorType(undefined), null)
  })
})

describe('parseSensorsJson', () => {
  it('parses the machine payload into a fully sorted readings array', () => {
    const readings = Model.parseSensorsJson(SENSORS_JSON)
    assert.equal(readings.length, 19)
    assert.deepEqual(readings.map((reading) => reading.id), [
      'sensor:temperature:acpitz_0-acpi-0:temp1:temp1_input',
      'sensor:temperature:amdgpu-pci-1100:edge:temp1_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp1:temp1_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp2:temp2_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp3:temp3_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp4:temp4_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp5:temp5_input',
      'sensor:temperature:gigabyte_wmi-virtual-0:temp6:temp6_input',
      'sensor:temperature:iwlwifi_1_1-virtual-0:temp1:temp1_input',
      'sensor:temperature:k10temp-pci-00c3:Tccd1:temp3_input',
      'sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input',
      'sensor:temperature:nvme-pci-0200:Composite:temp1_input',
      'sensor:temperature:nvme-pci-1000:Composite:temp1_input',
      'sensor:temperature:nvme-pci-1000:Sensor%201:temp2_input',
      'sensor:temperature:nvme-pci-1000:Sensor%202:temp3_input',
      'sensor:temperature:r8169_0_800%3A00-mdio-0:temp1:temp1_input',
      'sensor:temperature:z53-hid-3-8:Coolant%20temp:temp1_input',
      'sensor:fan:z53-hid-3-8:Fan%20speed:fan2_input',
      'sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input'])
  })
  it('returns readings with the exact contracted shape and labels', () => {
    const readings = Model.parseSensorsJson(SENSORS_JSON)
    const tctl = readings.find((reading) => reading.feature === 'Tctl')
    assert.deepEqual(tctl, {
      id: 'sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input',
      type: 'temperature',
      device: 'k10temp-pci-00c3',
      deviceLabel: 'CPU',
      feature: 'Tctl',
      label: 'CPU Tctl',
      shortLabel: 'Tctl',
      inputKey: 'temp1_input',
      value: 56.625,
      unit: '\u00B0C',
      max: null,
      critical: null
    })
    const pump = readings.find((reading) => reading.feature === 'Pump speed')
    assert.deepEqual(pump, {
      id: 'sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input',
      type: 'fan',
      device: 'z53-hid-3-8',
      deviceLabel: 'Liquid cooler',
      feature: 'Pump speed',
      label: 'Liquid cooler Pump speed',
      shortLabel: 'Pump',
      inputKey: 'fan1_input',
      value: 2197,
      unit: 'RPM',
      max: null,
      critical: null
    })
  })
  it('carries max/critical thresholds and derives readable labels', () => {
    const readings = Model.parseSensorsJson(SENSORS_JSON)
    const composite = readings.find(
      (reading) => reading.device === 'nvme-pci-1000' && reading.feature === 'Composite')
    assert.equal(composite.max, 80.85)
    assert.equal(composite.critical, 84.85)

    const otherComposite = readings.find(
      (reading) => reading.device === 'nvme-pci-0200' && reading.feature === 'Composite')
    assert.equal(composite.deviceLabel, 'NVMe 1000')
    assert.equal(otherComposite.deviceLabel, 'NVMe 0200')

    const motherboard = readings.find((reading) => reading.device === 'acpitz_0-acpi-0')
    assert.equal(motherboard.deviceLabel, 'ACPI')
    assert.equal(motherboard.label, 'ACPI Temperature 1')
    assert.equal(motherboard.shortLabel, 'Temp 1')
    assert.equal(motherboard.value, 16.8)

    assert.equal(
      readings.find((reading) => reading.device === 'iwlwifi_1_1-virtual-0').deviceLabel,
      'Wi-Fi')
    assert.equal(
      readings.find((reading) => reading.device === 'gigabyte_wmi-virtual-0').deviceLabel,
      'Motherboard')
    assert.equal(
      readings.find((reading) => reading.device === 'r8169_0_800:00-mdio-0').deviceLabel,
      'Ethernet')

    const sensorOne = readings.find((reading) => reading.feature === 'Sensor 1')
    assert.equal(sensorOne.max, 65261.85) // vendor nonsense passes through
    assert.equal(sensorOne.critical, null)
    assert.equal(sensorOne.label, 'NVMe 1000 Sensor 1')
    assert.equal(sensorOne.shortLabel, 'Sensor')
  })
  it('ignores pwm, voltage, power, frequency, limit and alarm fields', () => {
    const readings = Model.parseSensorsJson(SENSORS_JSON)
    for (const reading of readings) {
      assert.ok(/^(temp|fan)[0-9]+_input$/.test(reading.inputKey), reading.inputKey)
      assert.ok(['temperature', 'fan'].includes(reading.type), reading.type)
    }
    // the amd gpu chip contributes only its edge temperature
    assert.deepEqual(
      Model.parseSensorsJson(
        '{"amdgpu-pci-1100":{"Adapter":"PCI adapter","vddgfx":{"in0_input":1.05},' +
        '"vddnb":{"in1_input":1.24},"edge":{"temp1_input":43.0},' +
        '"PPT":{"power1_input":50.942},"sclk":{"freq1_input":2200000000.0}}}')
        .map((reading) => reading.feature),
      ['edge'])
    // pwm channels on the cooler contribute nothing
    assert.equal(
      Model.parseSensorsJson(
        '{"z53-hid-3-8":{"Adapter":"HID adapter","pwm1":{"pwm1":89.5,"pwm1_enable":0.0,' +
        '"temp1_alarm":1.0}}}').length, 0)
    // min/lcrit/limit/alarm fields never become readings or thresholds
    const capped = Model.parseSensorsJson(
      '{"chip":{"Adapter":"X","f":{"temp1_input":40.0,"temp1_min":0.0,' +
      '"temp1_lcrit":-20.0,"temp1_lcrit_alarm":0.0,"temp1_max":60.0,' +
      '"temp1_crit_alarm":0.0,"temp1_fault":0.0}}}')
    assert.equal(capped.length, 1)
    assert.equal(capped[0].max, 60)
    assert.equal(capped[0].critical, null)
  })
  it('sorts readings regardless of JSON key order', () => {
    assert.deepEqual(
      Model.parseSensorsJson(
        '{"z53-hid-3-8":{"Adapter":"HID adapter","Coolant temp":{"temp1_input":33.0},' +
        '"Fan speed":{"fan2_input":1050.0}},"k10temp-pci-00c3":{"Adapter":"PCI adapter",' +
        '"Tctl":{"temp1_input":56.625}}}')
        .map((reading) => reading.id),
      ['sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input',
        'sensor:temperature:z53-hid-3-8:Coolant%20temp:temp1_input',
        'sensor:fan:z53-hid-3-8:Fan%20speed:fan2_input'])
  })
  it('returns null for invalid JSON or a non-object root', () => {
    assert.equal(Model.parseSensorsJson(''), null)
    assert.equal(Model.parseSensorsJson(null), null)
    assert.equal(Model.parseSensorsJson(undefined), null)
    assert.equal(Model.parseSensorsJson('not json'), null)
    assert.equal(Model.parseSensorsJson('{"truncated": '), null)
    assert.equal(Model.parseSensorsJson('null'), null)
    assert.equal(Model.parseSensorsJson('[]'), null)
    assert.equal(Model.parseSensorsJson('42'), null)
    assert.equal(Model.parseSensorsJson('"sensors"'), null)
  })
  it('skips non-object chips/features and non-finite inputs', () => {
    assert.deepEqual(Model.parseSensorsJson('{}'), [])
    assert.deepEqual(Model.parseSensorsJson('{"chip":"absent"}'), [])
    assert.deepEqual(Model.parseSensorsJson('{"chip":["array"]}'), [])
    assert.deepEqual(Model.parseSensorsJson('{"chip":{"Adapter":"X","f":[1,2]}}'), [])
    assert.deepEqual(
      Model.parseSensorsJson(
        '{"chip":{"Adapter":"X","f":{"temp1_input":null,"fan1_input":"2197",' +
        '"temp2_input":40.5}}}')
        .map((reading) => reading.inputKey),
      ['temp2_input'])
    const reading = Model.parseSensorsJson(
      '{"chip":{"Adapter":"X","f":{"temp1_input":40.5,"temp1_max":"bad","temp1_crit":null}}}')[0]
    assert.equal(reading.max, null)
    assert.equal(reading.critical, null)
  })
})

describe('chip settings with dynamic sensor ids', () => {
  const tempId = 'sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input'
  const fanId = 'sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input'

  it('appends valid dynamic ids after the fixed monitors in input order', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors([fanId, 'cpu', tempId, 'memory']),
      ['cpu', 'memory', fanId, tempId])
    assert.deepEqual(Model.normalizeChipMonitors([tempId]), [tempId])
  })
  it('deduplicates dynamic ids and drops malformed ones', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors([tempId, tempId, fanId, 'sensor:gpu:a:b:c', 'sensor:temperature:a:b']),
      [tempId, fanId])
  })
  it('retains dynamic ids while their sensor is temporarily absent', () => {
    assert.deepEqual(
      Model.normalizeChipMonitors(['cpu', 'sensor:temperature:gone-pci-0000:edge:temp1_input']),
      ['cpu', 'sensor:temperature:gone-pci-0000:edge:temp1_input'])
  })
  it('toggles dynamic ids like fixed ones, immutably', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], tempId, true), ['cpu', tempId])
    assert.deepEqual(Model.toggleChipMonitor([tempId], fanId, true), [tempId, fanId])
    assert.deepEqual(Model.toggleChipMonitor(['cpu', tempId], tempId, true), ['cpu', tempId])
    assert.deepEqual(
      Model.toggleChipMonitor(['cpu', tempId, fanId], fanId, false), ['cpu', tempId])
    assert.deepEqual(Model.toggleChipMonitor([tempId], tempId, false), [])

    const input = ['cpu', tempId]
    const disabled = Model.toggleChipMonitor(input, tempId, false)
    assert.deepEqual(input, ['cpu', tempId])
    assert.deepEqual(disabled, ['cpu'])
  })
  it('still ignores malformed sensor-ish ids and reports membership', () => {
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'sensor:gpu:a:b:c', true), ['cpu'])
    assert.deepEqual(Model.toggleChipMonitor(['cpu'], 'sensor:temperature:a:b', false), ['cpu'])
    assert.equal(Model.chipMonitorEnabled(['cpu'], 'sensor:temperature:a:b'), false)
    assert.equal(Model.chipMonitorEnabled(['cpu', tempId], tempId), true)
    assert.equal(Model.chipMonitorEnabled(['cpu', tempId], fanId), false)
    assert.equal(Model.chipMonitorEnabled(null, tempId), false) // defaults only
  })
})

// ---- hardware inventory (system info tab) ----------------------------------

function cpuinfoFixture(options) {
  const config = Object.assign({
    sockets: 1,
    coresPerSocket: 8,
    threadsPerCore: 2,
    vendor: 'AuthenticAMD',
    model: 'AMD Ryzen 7 7800X3D 8-Core Processor',
    cache: '1024 KB',
    withCpuCores: true,
    withTopology: true
  }, options || {})
  const lines = []
  const logical = config.sockets * config.coresPerSocket * config.threadsPerCore
  for (let p = 0; p < logical; p++) {
    const socket = Math.floor(p / (config.coresPerSocket * config.threadsPerCore))
    const local = p - socket * config.coresPerSocket * config.threadsPerCore
    lines.push('processor\t: ' + p)
    lines.push('vendor_id\t: ' + config.vendor)
    lines.push('model\t\t: 97')
    lines.push('model name\t: ' + config.model)
    lines.push('cache size\t: ' + config.cache)
    if (config.withTopology) {
      lines.push('physical id\t: ' + socket)
      lines.push('core id\t\t: ' + Math.floor(local / config.threadsPerCore))
    }
    if (config.withCpuCores) lines.push('cpu cores\t: ' + config.coresPerSocket)
    lines.push('')
  }
  return lines.join('\n')
}

const VM_CPUINFO = [
  'processor\t: 0',
  'vendor_id\t: ',
  'model name\t: ',
  'cache size\t: 4096 KB',
  '',
  'processor\t: 1',
  'vendor_id\t: AuthenticAMD',
  'model name\t: QEMU Virtual CPU version 2.5+',
  'cache size\t: 4096 KB',
  ''
].join('\n')

describe('normalizeHardwareValue', () => {
  it('trims padding and collapses internal whitespace', () => {
    assert.equal(Model.normalizeHardwareValue('  B650 AORUS ELITE AX ICE\n'),
      'B650 AORUS ELITE AX ICE')
    assert.equal(Model.normalizeHardwareValue('Gigabyte Technology Co., Ltd.'),
      'Gigabyte Technology Co., Ltd.')
    assert.equal(Model.normalizeHardwareValue('American Megatrends International, LLC.'),
      'American Megatrends International, LLC.')
    assert.equal(Model.normalizeHardwareValue('\tF31 \r\n'), 'F31')
    assert.equal(Model.normalizeHardwareValue('08/14/2024'), '08/14/2024')
  })
  it('blank or missing input reads as empty', () => {
    assert.equal(Model.normalizeHardwareValue(''), '')
    assert.equal(Model.normalizeHardwareValue('   '), '')
    assert.equal(Model.normalizeHardwareValue('\t\n'), '')
    assert.equal(Model.normalizeHardwareValue(null), '')
    assert.equal(Model.normalizeHardwareValue(undefined), '')
  })
  it('folds common firmware sentinels to empty', () => {
    for (const raw of [
      'To be filled by O.E.M.', 'To Be Filled By O.E.M.', 'to be filled',
      'To  Be  Filled', 'Default string', 'Not Specified', 'none', 'NONE',
      'N/A', 'Unknown', 'UNKNOWN', 'x.x', 'System Product Name', 'OEM',
      'System Manufacturer', 'base board version', 'not available'
    ]) {
      assert.equal(Model.normalizeHardwareValue(raw), '', raw)
    }
  })
})

describe('parseCpuInfo', () => {
  it('reads a realistic single-socket AMD cpuinfo', () => {
    const cpu = Model.parseCpuInfo(cpuinfoFixture())
    assert.equal(cpu.model, 'AMD Ryzen 7 7800X3D 8-Core Processor')
    assert.equal(cpu.vendor, 'AuthenticAMD')
    assert.equal(cpu.logicalProcessors, 16)
    assert.equal(cpu.physicalCores, 8) // cpu cores x 1 socket, not summed per CPU
    assert.equal(cpu.sockets, 1)
    assert.equal(cpu.cache, '1024 KB')
  })
  it('multiplies cpu cores by distinct physical ids (Intel dual socket)', () => {
    const cpu = Model.parseCpuInfo(cpuinfoFixture({
      sockets: 2,
      coresPerSocket: 20,
      threadsPerCore: 1,
      vendor: 'GenuineIntel',
      model: 'Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz',
      cache: '28160 KB'
    }))
    assert.equal(cpu.model, 'Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz')
    assert.equal(cpu.vendor, 'GenuineIntel')
    assert.equal(cpu.logicalProcessors, 40)
    assert.equal(cpu.sockets, 2)
    // "cpu cores : 20" repeats on all 40 entries yet stays cores-per-socket
    assert.equal(cpu.physicalCores, 40)
    assert.equal(cpu.cache, '28160 KB')
  })
  it('falls back to distinct physical-id/core-id pairs without cpu cores', () => {
    const cpu = Model.parseCpuInfo(cpuinfoFixture({
      sockets: 2, coresPerSocket: 2, threadsPerCore: 2, withCpuCores: false
    }))
    assert.equal(cpu.logicalProcessors, 8)
    assert.equal(cpu.sockets, 2)
    assert.equal(cpu.physicalCores, 4) // 4 unique socket:core pairs
  })
  it('non-numeric cpu cores falls through to the pair fallback', () => {
    const raw = cpuinfoFixture({ coresPerSocket: 4, threadsPerCore: 1 })
      .split('\n')
      .map(line => line.replace(/^cpu cores\t: \d+$/, 'cpu cores\t: N/A'))
      .join('\n') + 'cache size\t:\n'
    const cpu = Model.parseCpuInfo(raw)
    assert.equal(cpu.logicalProcessors, 4)
    assert.equal(cpu.physicalCores, 4)
    assert.equal(cpu.cache, '1024 KB') // trailing blank value never overwrites
  })
  it('VM-style cpuinfo without topology reports one socket and null cores', () => {
    const cpu = Model.parseCpuInfo(VM_CPUINFO)
    assert.equal(cpu.logicalProcessors, 2)
    assert.equal(cpu.sockets, 1)
    assert.equal(cpu.physicalCores, null)
    // first non-empty value wins for repeated model name / vendor keys
    assert.equal(cpu.model, 'QEMU Virtual CPU version 2.5+')
    assert.equal(cpu.vendor, 'AuthenticAMD')
    assert.equal(cpu.cache, '4096 KB')
  })
  it('returns null for missing or malformed input', () => {
    assert.equal(Model.parseCpuInfo(''), null)
    assert.equal(Model.parseCpuInfo(null), null)
    assert.equal(Model.parseCpuInfo(undefined), null)
    assert.equal(Model.parseCpuInfo('no colon separated keys here'), null)
    assert.equal(Model.parseCpuInfo('processor\t: abc\nflags\t: fpu'), null)
  })
})

describe('parseMemInfo', () => {
  it('converts kB lines to bytes', () => {
    const raw = [
      'MemTotal:       48403948 kB',
      'MemFree:         1847948 kB',
      'MemAvailable:   23292312 kB',
      'Active(anon):   13294160 kB',
      'SwapTotal:      96807384 kB',
      'SwapFree:       96789836 kB',
      'VmallocTotal:   34359738367 kB',
      ''
    ].join('\n')
    assert.deepEqual(Model.parseMemInfo(raw), {
      totalBytes: 48403948 * 1024,
      availableBytes: 23292312 * 1024,
      swapTotalBytes: 96807384 * 1024,
      swapFreeBytes: 96789836 * 1024
    })
  })
  it('missing MemAvailable and swap lines read as zero', () => {
    assert.deepEqual(Model.parseMemInfo('MemTotal: 8000000 kB\nMemFree: 1 kB\n'), {
      totalBytes: 8000000 * 1024,
      availableBytes: 0,
      swapTotalBytes: 0,
      swapFreeBytes: 0
    })
  })
  it('returns null without a positive MemTotal', () => {
    assert.equal(Model.parseMemInfo(''), null)
    assert.equal(Model.parseMemInfo(null), null)
    assert.equal(Model.parseMemInfo('MemFree: 100 kB\n'), null)
    assert.equal(Model.parseMemInfo('MemTotal: zero kB\n'), null)
    assert.equal(Model.parseMemInfo('MemTotal: 0 kB\n'), null)
    assert.equal(Model.parseMemInfo('MemTotal: -5 kB\n'), null)
    assert.equal(Model.parseMemInfo('garbage'), null)
  })
})

describe('parseOsRelease', () => {
  it('parses quoted and bare assignments', () => {
    const raw = [
      'NAME="Omarchy"',
      'PRETTY_NAME="Omarchy"',
      'ID=omarchy',
      'ID_LIKE=arch',
      'VERSION_ID="4.0.0"',
      'BUILD_ID="4.0.0"',
      'LOGO=omarchy',
      ''
    ].join('\n')
    assert.deepEqual(Model.parseOsRelease(raw), {
      prettyName: 'Omarchy',
      name: 'Omarchy',
      id: 'omarchy',
      versionId: '4.0.0',
      buildId: '4.0.0'
    })
  })
  it('strips single quotes and keeps unquoted spaces', () => {
    const raw = 'NAME=\'Fedora Linux\'\nPRETTY_NAME=Fedora Linux 41\nID=fedora\n'
    assert.deepEqual(Model.parseOsRelease(raw), {
      prettyName: 'Fedora Linux 41',
      name: 'Fedora Linux',
      id: 'fedora',
      versionId: null, // keys absent from the file stay null
      buildId: null
    })
  })
  it('skips comments, blanks and malformed keys; first duplicate wins', () => {
    const raw = '# release data\n\nBAD-KEY=x\n=broken\nID=arch\nID=debian\n'
    assert.deepEqual(Model.parseOsRelease(raw), {
      prettyName: null,
      name: null,
      id: 'arch',
      versionId: null,
      buildId: null
    })
  })
  it('returns null without a single parsable assignment', () => {
    assert.equal(Model.parseOsRelease(''), null)
    assert.equal(Model.parseOsRelease(null), null)
    assert.equal(Model.parseOsRelease('# only comments\n\n'), null)
    assert.equal(Model.parseOsRelease('garbage without assignments'), null)
  })
})

describe('parseKernelInfo', () => {
  it('splits uname -srmo output', () => {
    const kernel = Model.parseKernelInfo('Linux 7.1.8-arch1-3 x86_64 GNU/Linux')
    assert.equal(kernel.full, 'Linux 7.1.8-arch1-3 x86_64 GNU/Linux')
    assert.equal(kernel.kernel, '7.1.8-arch1-3')
    assert.equal(kernel.architecture, 'x86_64')
  })
  it('tolerates trailing newlines and non-x86 machines', () => {
    const kernel = Model.parseKernelInfo('Linux 6.6.87-2-lts aarch64 GNU/Linux\n')
    assert.equal(kernel.kernel, '6.6.87-2-lts')
    assert.equal(kernel.architecture, 'aarch64')
    const collapsed = Model.parseKernelInfo('Linux  6.1\tarmv7l  GNU/Linux')
    assert.equal(collapsed.full, 'Linux 6.1 armv7l GNU/Linux')
    assert.equal(collapsed.architecture, 'armv7l')
  })
  it('returns null for fewer than three fields', () => {
    assert.equal(Model.parseKernelInfo(''), null)
    assert.equal(Model.parseKernelInfo('Linux 6.1'), null)
    assert.equal(Model.parseKernelInfo('   '), null)
    assert.equal(Model.parseKernelInfo(null), null)
  })
})

describe('parseLspciGraphics', () => {
  it('lists only display-class devices from real -mm -D output', () => {
    const raw = [
      '0000:00:00.0 "Host bridge" "Advanced Micro Devices, Inc. [AMD]" ' +
        '"Raphael/Granite Ridge Root Complex" -p00 "Advanced Micro Devices, Inc. [AMD]" ' +
        '"Raphael/Granite Ridge Root Complex"',
      '0000:01:00.0 "VGA compatible controller" "NVIDIA Corporation" ' +
        '"GB203 [GeForce RTX 5070 Ti]" -ra1 -p00 "ASUSTeK Computer Inc." "Device 89f4"',
      '0000:01:00.1 "Audio device" "NVIDIA Corporation" ' +
        '"GB203 High Definition Audio Controller" -ra1 -p00 "NVIDIA Corporation" "Device 0000"',
      '0000:11:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" ' +
        '"Raphael" -rcb -p00 "Gigabyte Technology Co, Ltd" "Device d000"',
      '0000:12:00.0 "Network controller" "Intel Corporation" ' +
        '"Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak]" -r1a -p00 "Intel Corporation" ' +
        '"Wi-Fi 6 AX210 160MHz"',
      ''
    ].join('\n')
    const gpus = Model.parseLspciGraphics(raw)
    assert.equal(gpus.length, 2)
    assert.deepEqual(gpus[0], {
      address: '0000:01:00.0',
      className: 'VGA compatible controller',
      vendor: 'NVIDIA Corporation',
      device: 'GB203 [GeForce RTX 5070 Ti]'
    })
    assert.deepEqual(gpus[1], {
      address: '0000:11:00.0',
      className: 'VGA compatible controller',
      vendor: 'Advanced Micro Devices, Inc. [AMD/ATI]',
      device: 'Raphael'
    })
  })
  it('includes 3D and Display controllers and folds escapes', () => {
    const raw = '0000:05:00.0 "3D controller" "NVIDIA Corporation" "GA102GL [A40]" -ra1\n' +
      '0000:06:00.0 "Display controller" "ASPEED Technology, Inc." "ASPEED Graphics Family"\n' +
      '0000:07:00.0 "VGA compatible controller" "Some Vendor" "Board [\\"Pro\\"]"\n'
    const gpus = Model.parseLspciGraphics(raw)
    assert.equal(gpus.length, 3)
    assert.equal(gpus[0].className, '3D controller')
    assert.equal(gpus[0].device, 'GA102GL [A40]')
    assert.equal(gpus[1].className, 'Display controller')
    assert.equal(gpus[2].device, 'Board ["Pro"]')
  })
  it('returns an empty array for missing or unparsable input', () => {
    assert.deepEqual(Model.parseLspciGraphics(''), [])
    assert.deepEqual(Model.parseLspciGraphics(null), [])
    assert.deepEqual(Model.parseLspciGraphics('not lspci output'), [])
    assert.deepEqual(Model.parseLspciGraphics('0000:01:00.0 unquoted garbage'), [])
    // too few quoted fields to identify the device
    assert.deepEqual(Model.parseLspciGraphics('0000:01:00.0 "VGA compatible controller"'), [])
  })
})

describe('parseNvidiaHardware', () => {
  it('reads the csv query row', () => {
    assert.deepEqual(
      Model.parseNvidiaHardware('NVIDIA GeForce RTX 5070 Ti, 610.57.04, 16303'),
      { name: 'NVIDIA GeForce RTX 5070 Ti', driverVersion: '610.57.04', memoryTotalMiB: 16303 }
    )
  })
  it('uses the first row and tolerates surrounding blank lines', () => {
    const gpu = Model.parseNvidiaHardware(
      '\nNVIDIA GeForce RTX 3070, 550.54.14, 8192\nNVIDIA GeForce RTX 3080, 550.54.14, 10240\n')
    assert.equal(gpu.name, 'NVIDIA GeForce RTX 3070')
    assert.equal(gpu.memoryTotalMiB, 8192)
  })
  it('returns null for missing or malformed output', () => {
    assert.equal(Model.parseNvidiaHardware(''), null)
    assert.equal(Model.parseNvidiaHardware('  \n  '), null)
    assert.equal(Model.parseNvidiaHardware(null), null)
    assert.equal(Model.parseNvidiaHardware('NVIDIA GeForce RTX 5070 Ti, 610.57.04'), null)
    assert.equal(Model.parseNvidiaHardware('NVIDIA GeForce RTX 5070 Ti, 610.57.04, [N/A]'), null)
    assert.equal(Model.parseNvidiaHardware('GPU, driver, 0'), null)
  })
})
