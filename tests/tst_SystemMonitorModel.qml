import QtQuick
import QtTest
import "../SystemMonitorModel.js" as MonitorModel

// Qt V4 engine compatibility suite for the shared SystemMonitorModel.js
// production module. Run with:
//   /usr/lib/qt6/bin/qmltestrunner -input tests
//
// Every assertion mirrors behavior extracted from the former inline logic in
// system-stats.qml, SystemPerformanceView.qml, and SystemProcessView.qml, so
// this file doubles as a regression net for the UI strings users see.

Item {
    TestCase {
        name: "SystemMonitorModel"

        // ---- module surface ------------------------------------------------
        //
        // Importing the script and touching every export proves the file
        // parses and executes under the QML engine (no CommonJS guard leak,
        // no library pragma dependency).

        function test_module_exports_all_contract_functions() {
            compare(typeof MonitorModel.finiteNumber, "function")
            compare(typeof MonitorModel.recentHistory, "function")
            compare(typeof MonitorModel.appendHistory, "function")
            compare(typeof MonitorModel.clampPercent, "function")
            compare(typeof MonitorModel.formatPercent, "function")
            compare(typeof MonitorModel.formatRate, "function")
            compare(typeof MonitorModel.formatCompactRate, "function")
            compare(typeof MonitorModel.formatBytes, "function")
            compare(typeof MonitorModel.formatUptime, "function")
            compare(typeof MonitorModel.formatLoad, "function")
            compare(typeof MonitorModel.networkScaleFor, "function")
            compare(typeof MonitorModel.parseDiskOutput, "function")
            compare(typeof MonitorModel.parseGpuOutput, "function")
            compare(typeof MonitorModel.parseStatsOutput, "function")
            compare(typeof MonitorModel.calculateSystemMetrics, "function")
            compare(typeof MonitorModel.buildPsCommand, "function")
            compare(typeof MonitorModel.parsePsOutput, "function")
            compare(typeof MonitorModel.compareProcessRows, "function")
            compare(typeof MonitorModel.filterAndSortProcesses, "function")
            compare(typeof MonitorModel.findProcessByPid, "function")
            compare(typeof MonitorModel.normalizeStartToken, "function")
            compare(typeof MonitorModel.buildPidfdSignalCommand, "function")
            compare(typeof MonitorModel.formatCompactUptime, "function")
            compare(typeof MonitorModel.chipMonitorIds, "function")
            compare(typeof MonitorModel.defaultChipMonitors, "function")
            compare(typeof MonitorModel.normalizeChipMode, "function")
            compare(typeof MonitorModel.normalizeChipMonitors, "function")
            compare(typeof MonitorModel.toggleChipMonitor, "function")
            compare(typeof MonitorModel.chipMonitorEnabled, "function")
            compare(typeof MonitorModel.normalizeHardwareValue, "function")
            compare(typeof MonitorModel.parseCpuInfo, "function")
            compare(typeof MonitorModel.parseMemInfo, "function")
            compare(typeof MonitorModel.parseOsRelease, "function")
            compare(typeof MonitorModel.parseKernelInfo, "function")
            compare(typeof MonitorModel.parseLspciGraphics, "function")
            compare(typeof MonitorModel.parseNvidiaHardware, "function")
            compare(typeof MonitorModel.parseSensorsJson, "function")
            compare(typeof MonitorModel.sensorMonitorId, "function")
            compare(typeof MonitorModel.isSensorMonitorId, "function")
            compare(typeof MonitorModel.sensorMonitorType, "function")
            compare(typeof MonitorModel.localFilePath, "function")
            compare(typeof MonitorModel.commandOutputLimit, "function")
            compare(typeof MonitorModel.buildBoundedCommand, "function")
        }

        // ---- numeric guarding ----------------------------------------------

        function test_finiteNumber_passes_finite_and_coerces() {
            compare(MonitorModel.finiteNumber(5, 0), 5)
            compare(MonitorModel.finiteNumber("7.5", -1), 7.5)
            compare(MonitorModel.finiteNumber(0, 7), 0)
        }

        function test_finiteNumber_falls_back_on_non_finite() {
            compare(MonitorModel.finiteNumber("abc", 42), 42)
            compare(MonitorModel.finiteNumber(NaN, 3), 3)
            compare(MonitorModel.finiteNumber(Infinity, 9), 9)
            compare(MonitorModel.finiteNumber(undefined, 2), 2)
        }

        function test_clampPercent() {
            compare(MonitorModel.clampPercent(50), 50)
            compare(MonitorModel.clampPercent(-5), 0)
            compare(MonitorModel.clampPercent(150), 100)
        }

        // ---- history handling ----------------------------------------------
        //
        // Histories must be immutable slices: callers reassign the result
        // whole so QML bindings recompute atomically.

        function test_recentHistory_returns_last_sixty_without_mutation() {
            compare(MonitorModel.recentHistory(null).length, 0)
            compare(MonitorModel.recentHistory(undefined).length, 0)
            var short = [1, 2, 3]
            compare(MonitorModel.recentHistory(short).length, 3)
            var long = []
            for (var i = 0; i < 100; i++) long.push(i)
            var recent = MonitorModel.recentHistory(long)
            compare(long.length, 100)
            compare(recent.length, 60)
            compare(recent[0], 40)
            compare(recent[59], 99)
        }

        function test_appendHistory_caps_at_sixty_without_mutation() {
            var next = MonitorModel.appendHistory([], 1)
            compare(next.length, 1)
            compare(next[0], 1)

            var three = MonitorModel.appendHistory([1, 2, 3], 4)
            compare(three.length, 4)
            compare(three[3], 4)

            var full = []
            for (var i = 0; i < 60; i++) full.push(i) // 0..59
            var capped = MonitorModel.appendHistory(full, 60)
            compare(full.length, 60)
            compare(capped.length, 60)
            compare(capped[0], 1) // oldest sample dropped
            compare(capped[59], 60)
        }

        // ---- formatting (user-visible strings) ------------------------------

        function test_formatPercent() {
            compare(MonitorModel.formatPercent(45.6), "46%")
            compare(MonitorModel.formatPercent(72.4), "72%")
            compare(MonitorModel.formatPercent(-3), "0%")
            compare(MonitorModel.formatPercent(250), "100%")
            compare(MonitorModel.formatPercent(NaN), "0%")
        }

        function test_formatRate_byte_based_units() {
            compare(MonitorModel.formatRate(0), "0 B/s")
            compare(MonitorModel.formatRate(-10), "0 B/s")
            compare(MonitorModel.formatRate(NaN), "0 B/s")
            compare(MonitorModel.formatRate(500), "500 B/s")
            compare(MonitorModel.formatRate(512), "512 B/s")
            compare(MonitorModel.formatRate(2048), "2.0 KiB/s")
            compare(MonitorModel.formatRate(20 * 1024), "20 KiB/s")
            compare(MonitorModel.formatRate(1.5 * 1024 * 1024), "1.5 MiB/s")
            compare(MonitorModel.formatRate(20 * 1024 * 1024), "20 MiB/s")
            compare(MonitorModel.formatRate(2 * 1024 * 1024 * 1024), "2.0 GiB/s")
            compare(MonitorModel.formatRate(20 * 1024 * 1024 * 1024), "20 GiB/s")
        }

        function test_formatCompactRate() {
            compare(MonitorModel.formatCompactRate(0), "0B")
            compare(MonitorModel.formatCompactRate(-1), "0B")
            compare(MonitorModel.formatCompactRate(NaN), "0B")
            compare(MonitorModel.formatCompactRate(500), "500B")
            compare(MonitorModel.formatCompactRate(999.5), "1.0K")
            compare(MonitorModel.formatCompactRate(2048), "2K")
            compare(MonitorModel.formatCompactRate(1.5 * 1024 * 1024), "1.5M")
            compare(MonitorModel.formatCompactRate(10 * 1024 * 1024), "10M")
            compare(MonitorModel.formatCompactRate(20.8 * 1024 * 1024), "21M")
            compare(MonitorModel.formatCompactRate(1024 * 1024 * 1024), "1.0G")
            compare(MonitorModel.formatCompactRate(20 * 1024 * 1024 * 1024), "20G")
            compare(MonitorModel.formatCompactRate(1024 * 1024 * 1024 * 1024), "1.0T")
        }

        function test_formatBytes_byte_based_units() {
            compare(MonitorModel.formatBytes(0), "0 B")
            compare(MonitorModel.formatBytes(-5), "0 B")
            compare(MonitorModel.formatBytes(NaN), "0 B")
            compare(MonitorModel.formatBytes(512), "512 B")
            compare(MonitorModel.formatBytes(1024), "1.0 KiB")
            compare(MonitorModel.formatBytes(1536), "1.5 KiB")
            compare(MonitorModel.formatBytes(5 * 1024 * 1024), "5.0 MiB")
            compare(MonitorModel.formatBytes(5 * 1024 * 1024 * 1024), "5.0 GiB")
            compare(MonitorModel.formatBytes(1099511627776), "1.0 TiB")
        }

        function test_formatUptime() {
            compare(MonitorModel.formatUptime(0), "1m")
            compare(MonitorModel.formatUptime(59), "1m")
            compare(MonitorModel.formatUptime(60), "1m")
            compare(MonitorModel.formatUptime(3599), "59m")
            compare(MonitorModel.formatUptime(3600), "1h 0m")
            compare(MonitorModel.formatUptime(7325), "2h 2m")
            compare(MonitorModel.formatUptime(86460), "1d 0h 1m")
            compare(MonitorModel.formatUptime(90061), "1d 1h 1m")
            compare(MonitorModel.formatUptime(-100), "1m")
            compare(MonitorModel.formatUptime(NaN), "1m")
        }

        function test_formatCompactUptime() {
            compare(MonitorModel.formatCompactUptime(0), "1m")
            compare(MonitorModel.formatCompactUptime(59), "1m")
            compare(MonitorModel.formatCompactUptime(60), "1m")
            compare(MonitorModel.formatCompactUptime(125), "2m")
            compare(MonitorModel.formatCompactUptime(3599), "59m")
            compare(MonitorModel.formatCompactUptime(3600), "1h 0m")
            compare(MonitorModel.formatCompactUptime(3661), "1h 1m")
            compare(MonitorModel.formatCompactUptime(7325), "2h 2m")
            compare(MonitorModel.formatCompactUptime(86399), "23h 59m")
            compare(MonitorModel.formatCompactUptime(86400), "1d 0h")
            compare(MonitorModel.formatCompactUptime(90061), "1d 1h")
            compare(MonitorModel.formatCompactUptime(2 * 86400 + 3 * 3600 + 4 * 60), "2d 3h")
            compare(MonitorModel.formatCompactUptime(-100), "1m")
            compare(MonitorModel.formatCompactUptime(NaN), "1m")
        }

        function test_formatLoad() {
            compare(MonitorModel.formatLoad(0), "0.00")
            compare(MonitorModel.formatLoad(1.5), "1.50")
            compare(MonitorModel.formatLoad(12.3), "12.30")
            compare(MonitorModel.formatLoad(-4), "0.00")
            compare(MonitorModel.formatLoad(NaN), "0.00")
        }

        function test_utilizationLevel_thresholds() {
            compare(MonitorModel.utilizationLevel(0), "normal")
            compare(MonitorModel.utilizationLevel(69.9), "normal")
            compare(MonitorModel.utilizationLevel(70), "warning")
            compare(MonitorModel.utilizationLevel(89.9), "warning")
            compare(MonitorModel.utilizationLevel(90), "critical")
            compare(MonitorModel.utilizationLevel(100), "critical")
        }

        function test_networkScaleFor_uses_fixed_stops() {
            compare(MonitorModel.networkScaleFor([], []), 32 * 1024)
            compare(MonitorModel.networkScaleFor(null, null), 32 * 1024)
            compare(MonitorModel.networkScaleFor([1024], [2048]), 32 * 1024)
            compare(MonitorModel.networkScaleFor([64 * 1024], []), 64 * 1024)
            compare(MonitorModel.networkScaleFor([], [64 * 1024]), 64 * 1024)
            compare(MonitorModel.networkScaleFor([100 * 1024 * 1024], []),
                    128 * 1024 * 1024)
        }

        function test_networkScaleFor_ignores_bad_samples_and_doubles_beyond_1gib() {
            compare(MonitorModel.networkScaleFor([-5], [NaN]), 32 * 1024)
            compare(MonitorModel.networkScaleFor([3 * 1024 * 1024 * 1024], []),
                    4 * 1024 * 1024 * 1024)
        }

        // ---- stats parsing ---------------------------------------------------

        function test_parseStatsOutput_accepts_ten_numeric_fields() {
            var stats = MonitorModel.parseStatsOutput(
                "100 50 8000000 4000000 1000 500 1.5 1.2 1.0 7200")
            verify(stats !== null)
            compare(stats.total, 100)
            compare(stats.idle, 50)
            compare(stats.memoryTotal, 8000000)
            compare(stats.memoryAvailable, 4000000)
            compare(stats.received, 1000)
            compare(stats.transmitted, 500)
            compare(stats.loadOne, 1.5)
            compare(stats.loadFive, 1.2)
            compare(stats.loadFifteen, 1.0)
            compare(stats.uptime, 7200)
        }

        function test_parseStatsOutput_tolerates_extra_whitespace() {
            var stats = MonitorModel.parseStatsOutput(
                "  100\t50  8000000\n4000000 1000 500 1.5 1.2 1.0  7200  ")
            verify(stats !== null)
            compare(stats.total, 100)
            compare(stats.uptime, 7200)
        }

        function test_parseStatsOutput_rejects_malformed_input() {
            verify(MonitorModel.parseStatsOutput("") === null)
            verify(MonitorModel.parseStatsOutput(null) === null)
            // nine fields
            verify(MonitorModel.parseStatsOutput("1 2 3 4 5 6 7 8 9") === null)
            // eleven fields
            verify(MonitorModel.parseStatsOutput("1 2 3 4 5 6 7 8 9 10 11") === null)
            // non-numeric tail
            verify(MonitorModel.parseStatsOutput(
                "100 50 8000000 4000000 1000 500 1.5 1.2 1.0 abc") === null)
            // non-finite value
            verify(MonitorModel.parseStatsOutput(
                "Infinity 50 8000000 4000000 1000 500 1.5 1.2 1.0 7200") === null)
        }

        // ---- metrics calculation ---------------------------------------------

        function statsSample(total, idle, memoryTotal, memoryAvailable,
                             received, transmitted) {
            return {
                total: total, idle: idle,
                memoryTotal: memoryTotal, memoryAvailable: memoryAvailable,
                received: received, transmitted: transmitted,
                loadOne: 1.5, loadFive: 1.2, loadFifteen: 1.0, uptime: 7200
            }
        }

        function test_calculateSystemMetrics_first_sample_has_null_cpu() {
            var first = MonitorModel.parseStatsOutput(
                "100 50 8000000 4000000 1000 500 1.5 1.2 1.0 7200")
            var metrics = MonitorModel.calculateSystemMetrics(first, null, 0, 1000)
            compare(metrics.cpuValue, null) // no valid prior delta yet
            compare(metrics.memoryValue, 50)
            compare(metrics.receiveRate, 0)
            compare(metrics.transmitRate, 0)
        }

        function test_calculateSystemMetrics_computes_deltas_over_one_second() {
            var first = MonitorModel.parseStatsOutput(
                "100 50 8000000 4000000 1000 500 1.5 1.2 1.0 7200")
            var second = MonitorModel.parseStatsOutput(
                "200 100 8000000 2000000 5120 505 1.5 1.2 1.0 7200")
            var metrics = MonitorModel.calculateSystemMetrics(second, first, 1000, 2000)
            compare(metrics.cpuValue, 50)      // 100*(1 - 50/100)
            compare(metrics.memoryValue, 75)   // 100*(1 - 2000000/8000000)
            compare(metrics.receiveRate, 4120) // (5120-1000)/1s
            compare(metrics.transmitRate, 5)   // (505-500)/1s
        }

        function test_calculateSystemMetrics_clamps_cpu_and_rates() {
            var priorIdleHigh = statsSample(100, 10, 8, 4, 0, 0)
            var cpuSpike = statsSample(110, 5, 8, 4, 0, 0)
            compare(MonitorModel.calculateSystemMetrics(
                cpuSpike, priorIdleHigh, 1000, 2000).cpuValue, 100) // raw 150

            var priorIdleLow = statsSample(100, 0, 8, 4, 0, 0)
            var cpuDip = statsSample(110, 20, 8, 4, 0, 0)
            compare(MonitorModel.calculateSystemMetrics(
                cpuDip, priorIdleLow, 1000, 2000).cpuValue, 0) // raw -100

            var priorTraffic = statsSample(100, 50, 8, 4, 10000, 5000)
            var countersReset = statsSample(110, 55, 8, 4, 5120, 10)
            var reset = MonitorModel.calculateSystemMetrics(
                countersReset, priorTraffic, 1000, 2000)
            compare(reset.receiveRate, 0)
            compare(reset.transmitRate, 0)
        }

        function test_calculateSystemMetrics_requires_increasing_total_and_time() {
            var first = statsSample(200, 100, 8, 4, 1000, 500)
            var nonIncreasing = statsSample(150, 75, 8, 4, 2000, 600)
            compare(MonitorModel.calculateSystemMetrics(
                nonIncreasing, first, 1000, 2000).cpuValue, null)

            var increasing = statsSample(300, 150, 8, 4, 2000, 600)
            var sameInstant = MonitorModel.calculateSystemMetrics(
                increasing, first, 1000, 1000)
            compare(sameInstant.receiveRate, 0)
            compare(sameInstant.transmitRate, 0)
        }

        function test_calculateSystemMetrics_memory_without_total() {
            var stats = statsSample(100, 50, 0, 0, 0, 0)
            compare(MonitorModel.calculateSystemMetrics(
                stats, null, 0, 1000).memoryValue, 0)
        }

        // ---- disk parsing (df -P -B1 output) ---------------------------------

        function test_parseDiskOutput_reads_last_data_line() {
            var disk = MonitorModel.parseDiskOutput(
                "Filesystem 1B-blocks Used Available Capacity Mounted on\n" +
                "/dev/nvme0n1p2 1000204 500102 500102 50% /")
            verify(disk !== null)
            compare(disk.totalBytes, 1000204)
            compare(disk.usedBytes, 500102)
            compare(disk.usedPercent, 50)

            var lastLineWins = MonitorModel.parseDiskOutput(
                "Filesystem 1B-blocks Used Available Capacity Mounted on\n" +
                "/dev/other 7 7 7 100% /tmp\n" +
                "/dev/nvme0n1p2 2000 500 1500 25% /")
            verify(lastLineWins !== null)
            compare(lastLineWins.totalBytes, 2000)
            compare(lastLineWins.usedBytes, 500)
            compare(lastLineWins.usedPercent, 25)

            var rounded = MonitorModel.parseDiskOutput(
                "h1 h2 h3 h4 h5 h6\n/dev/nvme0n1p2 3 1 2 33% /")
            compare(rounded.usedPercent, 33)
        }

        function test_parseDiskOutput_rejects_malformed_output() {
            verify(MonitorModel.parseDiskOutput("") === null)
            verify(MonitorModel.parseDiskOutput(null) === null)
            // header only — no data line
            verify(MonitorModel.parseDiskOutput("Filesystem 1B-blocks Used") === null)
            // data line with too few columns
            verify(MonitorModel.parseDiskOutput("h1 h2 h3 h4 h5 h6\n/dev/x 1 2 3") === null)
            // non-numeric total
            verify(MonitorModel.parseDiskOutput("h1 h2 h3 h4 h5 h6\n/dev/x abc 500 100 50% /") === null)
            // non-positive total
            verify(MonitorModel.parseDiskOutput("h1 h2 h3 h4 h5 h6\n/dev/x 0 500 100 50% /") === null)
            // negative used
            verify(MonitorModel.parseDiskOutput("h1 h2 h3 h4 h5 h6\n/dev/x 1000 -1 100 50% /") === null)
        }

        // ---- gpu parsing (nvidia-smi csv,noheader,nounits) ---------------------

        function test_parseGpuOutput_reads_csv_fields() {
            var gpu = MonitorModel.parseGpuOutput("37, 12288, 16384, 45")
            verify(gpu !== null)
            compare(gpu.usage, 37)
            compare(gpu.memoryUsedMiB, 12288)
            compare(gpu.memoryTotalMiB, 16384)
            compare(gpu.temperature, 45)

            // only the first line is considered
            var firstLine = MonitorModel.parseGpuOutput(
                "37, 12288, 16384, 45\nsecond, line, ignored, here")
            compare(firstLine.usage, 37)

            // usage clamps to 0..100
            var clamped = MonitorModel.parseGpuOutput("150, 10, 20, 60")
            compare(clamped.usage, 100)

            // missing temperature reports -1 instead of failing
            var noTemp = MonitorModel.parseGpuOutput("37, 12288, 16384, [N/A]")
            compare(noTemp.temperature, -1)

            // temperature rounds
            var rounded = MonitorModel.parseGpuOutput("37, 12288, 16384, 45.6")
            compare(rounded.temperature, 46)
        }

        function test_parseGpuOutput_rejects_malformed_output() {
            verify(MonitorModel.parseGpuOutput("") === null)
            verify(MonitorModel.parseGpuOutput(null) === null)
            // three fields only
            verify(MonitorModel.parseGpuOutput("37, 12288, 16384") === null)
            // non-numeric usage
            verify(MonitorModel.parseGpuOutput("N/A, 12288, 16384, 45") === null)
            // non-positive memory total
            verify(MonitorModel.parseGpuOutput("37, 12288, 0, 45") === null)
        }

        // ---- process commands --------------------------------------------------

        function test_buildPsCommand_with_user() {
            var argv = MonitorModel.buildPsCommand("ryan")
            compare(argv.length, 11)
            compare(argv[0], "timeout")
            compare(argv[1], "--kill-after=1")
            compare(argv[2], "3")
            compare(argv[3], "env")
            compare(argv[4], "LC_ALL=C")
            compare(argv[5], "ps")
            compare(argv[6], "-u")
            compare(argv[7], "ryan")
            compare(argv[8], "-o")
            compare(argv[9], "pid=,lstart=,pcpu=,pmem=,comm=")
            compare(argv[10], "--sort=-pcpu")
        }

        function test_buildPsCommand_without_or_padded_user() {
            var anon = MonitorModel.buildPsCommand("")
            compare(anon.length, 9)
            compare(anon[0], "timeout")
            compare(anon[1], "--kill-after=1")
            compare(anon[2], "3")
            compare(anon[3], "env")
            compare(anon[4], "LC_ALL=C")
            compare(anon[5], "ps")
            compare(anon[6], "-o")
            compare(anon[7], "pid=,lstart=,pcpu=,pmem=,comm=")
            compare(anon[8], "--sort=-pcpu")

            var padded = MonitorModel.buildPsCommand("  ryan  ")
            compare(padded.length, 11)
            compare(padded[7], "ryan")
        }

        function test_buildPidfdSignalCommand() {
            var argv = MonitorModel.buildPidfdSignalCommand("/bin/pidfd-signal", 1234,
                                                            "Mon Aug  5 09:08:15 2026")
            compare(argv.length, 3)
            compare(argv[0], "/bin/pidfd-signal")
            compare(argv[1], "1234")
            compare(argv[2], "Mon Aug 5 09:08:15 2026")

            compare(MonitorModel.buildPidfdSignalCommand("/bin/pidfd-signal", -1,
                                                         "Mon Aug 5 09:08:15 2026").length, 0)
            compare(MonitorModel.buildPidfdSignalCommand("/bin/pidfd-signal", 1234,
                                                         "").length, 0)
            compare(MonitorModel.buildPidfdSignalCommand("", 1234,
                                                         "Mon Aug 5 09:08:15 2026").length, 0)
        }

        // ---- bounded command boundary --------------------------------------

        function test_localFilePath_strips_and_decodes_file_urls() {
            compare(MonitorModel.localFilePath(
                        "file:///home/ryan/.config/omarchy/plugins/bitr0t.system-monitor/bin/bounded-command"),
                    "/home/ryan/.config/omarchy/plugins/bitr0t.system-monitor/bin/bounded-command")
            compare(MonitorModel.localFilePath("file:///home/my%20dir/tool"),
                    "/home/my dir/tool")

            // a real resolved QUrl stringifies and strips the same way
            var resolved = MonitorModel.localFilePath(
                        Qt.resolvedUrl("SystemMonitorModel.js"))
            verify(resolved.indexOf("file://") === -1)
            verify(resolved.length > "SystemMonitorModel.js".length)
            compare(resolved.substring(resolved.length - "SystemMonitorModel.js".length),
                    "SystemMonitorModel.js")
        }

        function test_localFilePath_keeps_plain_and_malformed_values() {
            compare(MonitorModel.localFilePath("/usr/bin/python3"), "/usr/bin/python3")
            compare(MonitorModel.localFilePath("bin/bounded-command"),
                    "bin/bounded-command")
            // only a leading file:// is stripped
            compare(MonitorModel.localFilePath("https://example.com/x"),
                    "https://example.com/x")
            compare(MonitorModel.localFilePath("/x/file:///y"), "/x/file:///y")
            // malformed escapes return undecoded instead of throwing
            compare(MonitorModel.localFilePath("file:///home/100%/x"), "/home/100%/x")
            compare(MonitorModel.localFilePath("file:///a%zz"), "/a%zz")
            compare(MonitorModel.localFilePath("file:///%"), "/%")
            compare(MonitorModel.localFilePath(null), "")
            compare(MonitorModel.localFilePath(undefined), "")
        }

        function test_commandOutputLimit_every_kind_and_unknown() {
            compare(MonitorModel.commandOutputLimit("stats"), 4096)
            compare(MonitorModel.commandOutputLimit("sensors"), 1048576)
            compare(MonitorModel.commandOutputLimit("disk"), 16384)
            compare(MonitorModel.commandOutputLimit("gpu"), 65536)
            compare(MonitorModel.commandOutputLimit("processes"), 2097152)
            compare(MonitorModel.commandOutputLimit("lspci"), 1048576)
            compare(MonitorModel.commandOutputLimit("uname"), 8192)
            compare(MonitorModel.commandOutputLimit("nvidiaInfo"), 65536)
            // unknown kinds report 0 so callers never launch unbounded
            compare(MonitorModel.commandOutputLimit("bogus"), 0)
            compare(MonitorModel.commandOutputLimit(""), 0)
            compare(MonitorModel.commandOutputLimit(null), 0)
            compare(MonitorModel.commandOutputLimit("constructor"), 0)
        }

        function test_buildBoundedCommand_wraps_the_whole_producer_argv() {
            var argv = ["timeout", "3", "env", "LC_ALL=C", "ps", "-o", "pid="]
            compareIdList(MonitorModel.buildBoundedCommand(
                              "/plugin/bin/bounded-command", 2097152, argv),
                          ["/plugin/bin/bounded-command", "2097152",
                           "timeout", "3", "env", "LC_ALL=C", "ps", "-o", "pid="])
            // the cap rides as its decimal string
            compareIdList(MonitorModel.buildBoundedCommand("/h", 4096, ["uname", "-srmo"]),
                          ["/h", "4096", "uname", "-srmo"])
        }

        function test_buildBoundedCommand_rejects_invalid_helper_cap_argv() {
            // caps outside 1..8388608 or non-integers
            var badCaps = [0, -1, 8388609, 12.5, NaN, Infinity, "abc", null, undefined]
            for (var index = 0; index < badCaps.length; index++)
                compare(MonitorModel.buildBoundedCommand(
                            "/h", badCaps[index], ["x"]).length, 0)
            // valid extremes
            compareIdList(MonitorModel.buildBoundedCommand("/h", 1, ["x"]), ["/h", "1", "x"])
            compareIdList(MonitorModel.buildBoundedCommand("/h", 8388608, ["x"]),
                          ["/h", "8388608", "x"])
            // missing helper
            compare(MonitorModel.buildBoundedCommand("", 4096, ["x"]).length, 0)
            compare(MonitorModel.buildBoundedCommand("   ", 4096, ["x"]).length, 0)
            compare(MonitorModel.buildBoundedCommand(null, 4096, ["x"]).length, 0)
            // empty or missing argv
            compare(MonitorModel.buildBoundedCommand("/h", 4096, []).length, 0)
            compare(MonitorModel.buildBoundedCommand("/h", 4096, null).length, 0)
            compare(MonitorModel.buildBoundedCommand("/h", 4096, undefined).length, 0)
            compare(MonitorModel.buildBoundedCommand("/h", 4096, "uname").length, 0)
            compare(MonitorModel.buildBoundedCommand(
                        "/h", 4096, ({ 0: "uname", length: 1 })).length, 0)
        }

        function test_buildBoundedCommand_returns_fresh_arrays() {
            var argv = ["sensors", "-j"]
            var first = MonitorModel.buildBoundedCommand("/h", 1048576, argv)
            var second = MonitorModel.buildBoundedCommand("/h", 1048576, argv)
            verify(first !== second)
            compareIdList(first, second)
            // input argv never mutated, results never share state
            compareIdList(argv, ["sensors", "-j"])
            first.push("poison")
            compareIdList(MonitorModel.buildBoundedCommand("/h", 1048576, argv),
                          ["/h", "1048576", "sensors", "-j"])
        }

        // ---- process parsing -----------------------------------------------------
        function test_normalizeStartToken() {
            compare(MonitorModel.normalizeStartToken(
                        "  Mon Aug  5 09:08:15  2026 \n"),
                    "Mon Aug 5 09:08:15 2026")
            compare(MonitorModel.normalizeStartToken(
                        "Mon\tAug 25 12:00:00 2026"),
                    "Mon Aug 25 12:00:00 2026")
            compare(MonitorModel.normalizeStartToken(""), "")
            compare(MonitorModel.normalizeStartToken("   "), "")
            compare(MonitorModel.normalizeStartToken(null), "")
        }
        function test_parsePsOutput_keeps_names_with_spaces_and_skips_bad_rows() {
            var raw = "  123  Mon Aug 25 12:00:00 2026  4.5  2.0 gnome shell\n" +
                      " 4567 Tue Aug 25 10:00:00 2026 10.0  1.5 firefox\n" +
                      "  789 Wed Sep  3 09:08:15 2025  0.0  0.1 my tool v2\n" +
                      "bad row\n" +
                      "  -5  Mon Aug 25 12:00:00 2026  1.0  1.0 negpid\n" +
                      "  999  Mon Aug 25 12:00:00 2026  abc  1.0 badcpu\n" +
                      "  47  1  1 legacy-row\n" +
                      "  46  Mon Aug 25 12:00:01  1  1 four-token-lstart\n" +
                      "\n"
            var rows = MonitorModel.parsePsOutput(raw, 400)
            verify(rows !== null)
            compare(rows.length, 3)
            compare(rows[0].pid, 123)
            compare(rows[0].name, "gnome shell")
            compare(rows[0].search, "gnome shell 123")
            compare(rows[0].startToken, "Mon Aug 25 12:00:00 2026")
            compare(rows[0].cpu, 4.5)
            compare(rows[0].memory, 2.0)
            compare(rows[2].name, "my tool v2")
            compare(rows[2].search, "my tool v2 789")
            // padded single-digit day collapses into the birth token
            compare(rows[2].startToken, "Wed Sep 3 09:08:15 2025")

            var limited = MonitorModel.parsePsOutput(raw, 1)
            compare(limited.length, 1)
        }

        function test_parsePsOutput_rejects_missing_input() {
            verify(MonitorModel.parsePsOutput(null, 400) === null)
        }

        function makeRow(pid, name, cpu, memory) {
            return {
                pid: pid, name: name, search: name.toLowerCase() + " " + pid,
                cpu: cpu, memory: memory
            }
        }

        function test_compareProcessRows_sorts_by_key_then_name() {
            var alpha = makeRow(1, "alpha", 5.0, 1.0)
            var beta = makeRow(2, "beta", 10.0, 1.0)
            var zeta = makeRow(3, "zeta", 5.0, 9.0)

            verify(MonitorModel.compareProcessRows(alpha, beta, "cpu") > 0)
            verify(MonitorModel.compareProcessRows(beta, alpha, "cpu") < 0)
            // cpu tie falls through to name ordering
            verify(MonitorModel.compareProcessRows(alpha, zeta, "cpu") < 0)
            verify(MonitorModel.compareProcessRows(zeta, alpha, "cpu") > 0)
            // memory key
            verify(MonitorModel.compareProcessRows(alpha, zeta, "memory") > 0)
            // memory tie falls through to name ordering
            var betaTwin = makeRow(4, "beta2", 0.0, 1.0)
            verify(MonitorModel.compareProcessRows(alpha, betaTwin, "memory") < 0)
            // numeric ascending and alphabetical both directions
            verify(MonitorModel.compareProcessRows(alpha, beta, "cpu", false) < 0)
            verify(MonitorModel.compareProcessRows(alpha, beta, "name", false) < 0)
            verify(MonitorModel.compareProcessRows(alpha, beta, "name", true) > 0)
        }

        function test_filterAndSortProcesses_filters_sorts_and_caps() {
            var processes = [
                makeRow(1, "alpha", 1.0, 2.0),
                makeRow(2, "firefox", 5.0, 6.0),
                makeRow(3, "code", 3.0, 9.0)
            ]

            var byCpu = MonitorModel.filterAndSortProcesses(processes, "", "cpu", 200)
            compare(byCpu.length, 3)
            compare(byCpu[0].name, "firefox")
            compare(byCpu[1].name, "code")
            compare(byCpu[2].name, "alpha")

            var byMemory = MonitorModel.filterAndSortProcesses(processes, "", "memory", 200)
            compare(byMemory[0].name, "code")
            compare(byMemory[1].name, "firefox")
            compare(byMemory[2].name, "alpha")

            var byName = MonitorModel.filterAndSortProcesses(
                        processes, "", "name", 200, false)
            compare(byName[0].name, "alpha")
            compare(byName[1].name, "code")
            compare(byName[2].name, "firefox")

            var byNameDescending = MonitorModel.filterAndSortProcesses(
                        processes, "", "name", 200, true)
            compare(byNameDescending[0].name, "firefox")
            compare(byNameDescending[2].name, "alpha")

            // case-insensitive name match
            var filtered = MonitorModel.filterAndSortProcesses(processes, "FIR", "cpu", 200)
            compare(filtered.length, 1)
            compare(filtered[0].name, "firefox")

            // search field also matches the pid as text
            var byPid = MonitorModel.filterAndSortProcesses(processes, "3", "cpu", 200)
            compare(byPid.length, 1)
            compare(byPid[0].name, "code")

            var limited = MonitorModel.filterAndSortProcesses(processes, "", "cpu", 2)
            compare(limited.length, 2)
            compare(limited[0].name, "firefox")

            var none = MonitorModel.filterAndSortProcesses(processes, "nope", "cpu", 200)
            compare(none.length, 0)
        }

        function test_findProcessByPid_matches_pid_and_birth_token() {
            var processes = [
                { pid: 1, name: "alpha", startToken: "Mon Aug 25 12:00:00 2026" },
                { pid: 2, name: "firefox", startToken: "Tue Aug 25 08:00:00 2026" }
            ]
            var found = MonitorModel.findProcessByPid(
                        processes, 2, "Tue Aug 25 08:00:00 2026")
            verify(found !== null)
            compare(found.name, "firefox")
            // a reused pid carries a different birth token and must not match
            verify(MonitorModel.findProcessByPid(
                        processes, 2, "Wed Aug 26 08:00:01 2027") === null)
            // without a token the lookup falls back to pid-only matching
            verify(MonitorModel.findProcessByPid(processes, 2) !== null)
            verify(MonitorModel.findProcessByPid(
                        processes, 999, "Mon Aug 25 12:00:00 2026") === null)
        }

        // ---- chip settings ----------------------------------------------------
        //
        // Element-wise comparison helper: Qt Test compares variants, so
        // arrays are checked like the argv tests above.

        function compareIdList(actual, expected) {
            compare(actual.length, expected.length)
            for (var index = 0; index < expected.length; index++)
                compare(actual[index], expected[index])
        }

        function test_chipMonitorIds_lists_fixed_order_fresh_each_call() {
            var ids = MonitorModel.chipMonitorIds()
            compareIdList(ids, ["cpu", "memory", "gpu", "network", "load", "uptime"])

            // mutating a returned copy must not poison later calls
            ids.push("bogus")
            ids.shift()
            compareIdList(MonitorModel.chipMonitorIds(),
                          ["cpu", "memory", "gpu", "network", "load", "uptime"])

            var defaults = MonitorModel.defaultChipMonitors()
            compareIdList(defaults, ["cpu", "memory", "network"])
            defaults.pop()
            compareIdList(MonitorModel.defaultChipMonitors(),
                          ["cpu", "memory", "network"])
        }

        function test_normalizeChipMode_accepts_only_the_two_modes() {
            compare(MonitorModel.normalizeChipMode("instrument"), "instrument")
            compare(MonitorModel.normalizeChipMode("minimal"), "minimal")
            compare(MonitorModel.normalizeChipMode(null), "instrument")
            compare(MonitorModel.normalizeChipMode(undefined), "instrument")
            compare(MonitorModel.normalizeChipMode(""), "instrument")
            compare(MonitorModel.normalizeChipMode("Instrument"), "instrument")
            compare(MonitorModel.normalizeChipMode(42), "instrument")
        }

        function test_normalizeChipMonitors_defaults_unknown_dupes_order() {
            // non-array falls back to defaults
            compareIdList(MonitorModel.normalizeChipMonitors(null),
                          ["cpu", "memory", "network"])
            compareIdList(MonitorModel.normalizeChipMonitors(undefined),
                          ["cpu", "memory", "network"])

            // empty selection survives
            compareIdList(MonitorModel.normalizeChipMonitors([]), [])

            // unknown ids dropped, duplicates collapsed
            compareIdList(MonitorModel.normalizeChipMonitors(
                              ["gpu", "cpu", "cpu", "swap", "memory"]),
                          ["cpu", "memory", "gpu"])
            compareIdList(MonitorModel.normalizeChipMonitors(["bogus"]), [])

            // canonical order restored
            compareIdList(MonitorModel.normalizeChipMonitors(
                              ["uptime", "network", "memory", "cpu", "load"]),
                          ["cpu", "memory", "network", "load", "uptime"])
        }

        function test_normalizeChipMonitors_does_not_mutate_input() {
            var input = ["network", "cpu"]
            var normalized = MonitorModel.normalizeChipMonitors(input)
            compareIdList(input, ["network", "cpu"])
            normalized.push("cpu")
            compareIdList(MonitorModel.normalizeChipMonitors(input),
                          ["cpu", "network"])
        }

        function test_toggleChipMonitor_enables_in_canonical_position() {
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], "memory", true),
                          ["cpu", "memory"])
            compareIdList(MonitorModel.toggleChipMonitor(["memory"], "cpu", true),
                          ["cpu", "memory"])
            compareIdList(MonitorModel.toggleChipMonitor([], "uptime", true),
                          ["uptime"])
            compareIdList(MonitorModel.toggleChipMonitor(null, "load", true),
                          ["cpu", "memory", "network", "load"])

            // enabling an already-enabled monitor is a no-op
            compareIdList(MonitorModel.toggleChipMonitor(["cpu", "memory"], "cpu", true),
                          ["cpu", "memory"])
        }

        function test_toggleChipMonitor_disables_and_ignores_unknown_ids() {
            compareIdList(
                MonitorModel.toggleChipMonitor(
                    ["cpu", "memory", "network"], "memory", false),
                ["cpu", "network"])
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], "cpu", false), [])

            // disabling an absent monitor changes nothing
            compareIdList(
                MonitorModel.toggleChipMonitor(["cpu", "network"], "memory", false),
                ["cpu", "network"])

            // unknown ids are inert in both directions
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], "bogus", true),
                          ["cpu"])
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], "bogus", false),
                          ["cpu"])
        }

        function test_toggleChipMonitor_never_mutates_the_input() {
            var input = ["network", "cpu"]
            var enabled = MonitorModel.toggleChipMonitor(input, "memory", true)
            compareIdList(input, ["network", "cpu"])
            compareIdList(enabled, ["cpu", "memory", "network"])

            var disabled = MonitorModel.toggleChipMonitor(input, "cpu", false)
            compareIdList(input, ["network", "cpu"])
            compareIdList(disabled, ["network"])
        }

        function test_toggleChipMonitor_round_trips_every_monitor() {
            var selection = MonitorModel.defaultChipMonitors()
            var ids = MonitorModel.chipMonitorIds()
            for (var index = 0; index < ids.length; index++)
                selection = MonitorModel.toggleChipMonitor(selection, ids[index], false)
            compareIdList(selection, [])

            var defaults = MonitorModel.defaultChipMonitors()
            for (var back = 0; back < defaults.length; back++)
                selection = MonitorModel.toggleChipMonitor(selection, defaults[back], true)
            compareIdList(selection, ["cpu", "memory", "network"])
        }

        function test_chipMonitorEnabled_membership_and_defaults() {
            compare(MonitorModel.chipMonitorEnabled(["cpu", "memory"], "cpu"), true)
            compare(MonitorModel.chipMonitorEnabled(["cpu", "memory"], "network"), false)
            compare(MonitorModel.chipMonitorEnabled([], "cpu"), false)

            // non-array values check the default selection
            compare(MonitorModel.chipMonitorEnabled(null, "cpu"), true)
            compare(MonitorModel.chipMonitorEnabled(undefined, "network"), true)
            compare(MonitorModel.chipMonitorEnabled(null, "load"), false)

            // unknown ids are never enabled
            compare(MonitorModel.chipMonitorEnabled(["cpu"], "bogus"), false)
            compare(MonitorModel.chipMonitorEnabled(MonitorModel.chipMonitorIds(), ""), false)
        }

        // ---- dynamic sensor monitors ---------------------------------------

        // Fixture mirroring this machine's actual `sensors -j` payload.
        function sensorsFixture() {
            return '{"iwlwifi_1_1-virtual-0":{"Adapter":"Virtual device","temp1":{"temp1_input":36.000000}},' +
                '"r8169_0_800:00-mdio-0":{"Adapter":"MDIO adapter","temp1":{"temp1_input":39.000000,"temp1_max":120.000000}},' +
                '"k10temp-pci-00c3":{"Adapter":"PCI adapter","Tctl":{"temp1_input":56.625000},"Tccd1":{"temp3_input":46.000000}},' +
                '"nvme-pci-1000":{"Adapter":"PCI adapter","Composite":{"temp1_input":38.850000,"temp1_max":80.850000,"temp1_min":-273.150000,"temp1_crit":84.850000,"temp1_alarm":0.000000},"Sensor 1":{"temp2_input":45.850000,"temp2_max":65261.850000,"temp2_min":-273.150000},"Sensor 2":{"temp3_input":38.850000,"temp3_max":65261.850000,"temp3_min":-273.150000}},' +
                '"acpitz_0-acpi-0":{"Adapter":"ACPI interface","temp1":{"temp1_input":16.800000}},' +
                '"z53-hid-3-8":{"Adapter":"HID adapter","Pump speed":{"fan1_input":2197.000000},"Fan speed":{"fan2_input":1050.000000},"Coolant temp":{"temp1_input":33.000000},"pwm1":{"pwm1":89.500000,"pwm1_enable":0.000000},"pwm2":{"pwm2":64.000000,"pwm2_enable":0.000000}},' +
                '"gigabyte_wmi-virtual-0":{"Adapter":"Virtual device","temp1":{"temp1_input":30.000000},"temp2":{"temp2_input":43.000000},"temp3":{"temp3_input":56.000000},"temp4":{"temp4_input":37.000000},"temp5":{"temp5_input":37.000000},"temp6":{"temp6_input":39.000000}},' +
                '"amdgpu-pci-1100":{"Adapter":"PCI adapter","vddgfx":{"in0_input":1.050000},"vddnb":{"in1_input":1.240000},"edge":{"temp1_input":43.000000},"PPT":{"power1_input":50.942000},"sclk":{"freq1_input":2200000000.000000}},' +
                '"nvme-pci-0200":{"Adapter":"PCI adapter","Composite":{"temp1_input":39.850000,"temp1_max":89.850000,"temp1_min":-0.150000,"temp1_crit":94.850000,"temp1_alarm":0.000000}}}'
        }

        function test_sensorMonitorId_builds_encoded_ids() {
            compare(MonitorModel.sensorMonitorId(
                        "temperature", "k10temp-pci-00c3", "Tctl", "temp1_input"),
                    "sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input")
            compare(MonitorModel.sensorMonitorId(
                        "fan", "z53-hid-3-8", "Pump speed", "fan1_input"),
                    "sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input")
            compare(MonitorModel.sensorMonitorId(
                        "temperature", "r8169_0_800:00-mdio-0", "temp1", "temp1_input"),
                    "sensor:temperature:r8169_0_800%3A00-mdio-0:temp1:temp1_input")
            // deterministic: identical inputs always yield the identical id
            compare(MonitorModel.sensorMonitorId("fan", "z53-hid-3-8", "Fan speed", "fan2_input"),
                    MonitorModel.sensorMonitorId("fan", "z53-hid-3-8", "Fan speed", "fan2_input"))

            verify(MonitorModel.sensorMonitorId("gpu", "a", "b", "c") === null)
            verify(MonitorModel.sensorMonitorId("temperature", "", "b", "c") === null)
            verify(MonitorModel.sensorMonitorId("temperature", "a", "b", "") === null)
            verify(MonitorModel.sensorMonitorId(null, "a", "b", "c") === null)
        }

        function test_isSensorMonitorId_and_sensorMonitorType() {
            compare(MonitorModel.isSensorMonitorId(
                        "sensor:temperature:nvme-pci-1000:Composite:temp1_input"), true)
            compare(MonitorModel.sensorMonitorType(
                        "sensor:temperature:nvme-pci-1000:Composite:temp1_input"), "temperature")
            compare(MonitorModel.isSensorMonitorId(
                        "sensor:fan:z53-hid-3-8:Fan%20speed:fan2_input"), true)
            compare(MonitorModel.sensorMonitorType(
                        "sensor:fan:z53-hid-3-8:Fan%20speed:fan2_input"), "fan")

            compare(MonitorModel.isSensorMonitorId("cpu"), false)
            compare(MonitorModel.isSensorMonitorId(""), false)
            compare(MonitorModel.isSensorMonitorId("sensor:gpu:a:b:c"), false)
            compare(MonitorModel.isSensorMonitorId("sensor:temperature:a:b"), false)
            compare(MonitorModel.isSensorMonitorId("sensor:temperature:a:b:c:d"), false)
            compare(MonitorModel.sensorMonitorType("cpu") === null, true)
            compare(MonitorModel.sensorMonitorType("sensor:gpu:a:b:c") === null, true)
        }

        function test_parseSensorsJson_reads_machine_payload_sorted() {
            var readings = MonitorModel.parseSensorsJson(sensorsFixture())
            verify(readings !== null)
            compare(readings.length, 19)

            // sorted by device, then feature, then input key
            compare(readings[0].id, "sensor:temperature:acpitz_0-acpi-0:temp1:temp1_input")
            compare(readings[0].deviceLabel, "ACPI")
            compare(readings[0].label, "ACPI Temperature 1")
            compare(readings[0].shortLabel, "Temp 1")
            compare(readings[0].unit, "\u00B0C")
            compare(readings[0].value, 16.8)

            compare(readings[10].id, "sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input")
            compare(readings[10].value, 56.625)
            compare(readings[10].label, "CPU Tctl")
            compare(readings[10].shortLabel, "Tctl")

            compare(readings[18].id, "sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input")
            compare(readings[18].type, "fan")
            compare(readings[18].unit, "RPM")
            compare(readings[18].value, 2197)
            compare(readings[18].label, "Liquid cooler Pump speed")
            compare(readings[18].shortLabel, "Pump")
        }

        function test_parseSensorsJson_thresholds_labels_and_exclusions() {
            var readings = MonitorModel.parseSensorsJson(sensorsFixture())
            var composite = null
            var sensorOne = null
            for (var index = 0; index < readings.length; index++) {
                var reading = readings[index]
                verify(/^(temp|fan)[0-9]+_input$/.test(reading.inputKey))
                if (reading.device === "nvme-pci-1000" && reading.feature === "Composite")
                    composite = reading
                if (reading.feature === "Sensor 1")
                    sensorOne = reading
            }
            verify(composite !== null)
            compare(composite.max, 80.85)
            compare(composite.critical, 84.85)
            verify(sensorOne !== null)
            compare(sensorOne.max, 65261.85)
            verify(sensorOne.critical === null)
            compare(sensorOne.label, "NVMe 1000 Sensor 1")
            compare(sensorOne.shortLabel, "Sensor")

            // the amd gpu chip contributes only its edge temperature
            var gpu = MonitorModel.parseSensorsJson(
                '{"amdgpu-pci-1100":{"Adapter":"PCI adapter","vddgfx":{"in0_input":1.05},' +
                '"vddnb":{"in1_input":1.24},"edge":{"temp1_input":43.0},' +
                '"PPT":{"power1_input":50.942},"sclk":{"freq1_input":2200000000.0}}}')
            compare(gpu.length, 1)
            compare(gpu[0].feature, "edge")

            // pwm channels on the cooler contribute nothing
            var cooler = MonitorModel.parseSensorsJson(
                '{"z53-hid-3-8":{"Adapter":"HID adapter","pwm1":{"pwm1":89.5,"pwm1_enable":0.0}}}')
            compare(cooler.length, 0)
        }

        function test_parseSensorsJson_invalid_input() {
            verify(MonitorModel.parseSensorsJson("") === null)
            verify(MonitorModel.parseSensorsJson(null) === null)
            verify(MonitorModel.parseSensorsJson("not json") === null)
            verify(MonitorModel.parseSensorsJson("{\"truncated\": ") === null)
            verify(MonitorModel.parseSensorsJson("null") === null)
            verify(MonitorModel.parseSensorsJson("[]") === null)
            verify(MonitorModel.parseSensorsJson("42") === null)
            compare(MonitorModel.parseSensorsJson("{}").length, 0)
            compare(MonitorModel.parseSensorsJson('{"chip":"absent"}').length, 0)
            compare(MonitorModel.parseSensorsJson(
                '{"chip":{"Adapter":"X","f":{"temp1_input":null,"fan1_input":"2197",' +
                '"temp2_input":40.5}}}').length, 1)
        }

        function test_chip_settings_accept_dynamic_sensor_ids() {
            var tempId = "sensor:temperature:k10temp-pci-00c3:Tctl:temp1_input"
            var fanId = "sensor:fan:z53-hid-3-8:Pump%20speed:fan1_input"

            // dynamic ids follow the fixed monitors in first-seen input order
            compareIdList(
                MonitorModel.normalizeChipMonitors([fanId, "cpu", tempId, "memory"]),
                ["cpu", "memory", fanId, tempId])
            // duplicates collapse, malformed sensor-ish ids drop
            compareIdList(
                MonitorModel.normalizeChipMonitors(
                    [tempId, tempId, "sensor:gpu:a:b:c", "sensor:temperature:a:b"]),
                [tempId])
            // dynamic ids survive temporary sensor absence
            compareIdList(
                MonitorModel.normalizeChipMonitors(
                    ["cpu", "sensor:temperature:gone-pci-0000:edge:temp1_input"]),
                ["cpu", "sensor:temperature:gone-pci-0000:edge:temp1_input"])

            // toggles treat dynamic ids exactly like the fixed monitors
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], tempId, true),
                          ["cpu", tempId])
            compareIdList(
                MonitorModel.toggleChipMonitor(["cpu", tempId, fanId], fanId, false),
                ["cpu", tempId])
            compareIdList(MonitorModel.toggleChipMonitor([tempId], tempId, false), [])
            compareIdList(MonitorModel.toggleChipMonitor(["cpu"], "sensor:gpu:a:b:c", true),
                          ["cpu"])

            // membership and immutability
            compare(MonitorModel.chipMonitorEnabled(["cpu", tempId], tempId), true)
            compare(MonitorModel.chipMonitorEnabled(["cpu", tempId], fanId), false)
            compare(MonitorModel.chipMonitorEnabled(null, tempId), false)
            var input = ["cpu", tempId]
            MonitorModel.toggleChipMonitor(input, tempId, false)
            compareIdList(input, ["cpu", tempId])
        }

        // ---- hardware inventory (system info tab) --------------------------

        function test_normalizeHardwareValue_trims_and_folds_sentinels() {
            compare(MonitorModel.normalizeHardwareValue("  B650 AORUS ELITE AX ICE\n"),
                    "B650 AORUS ELITE AX ICE")
            compare(MonitorModel.normalizeHardwareValue("Gigabyte Technology Co., Ltd."),
                    "Gigabyte Technology Co., Ltd.")
            compare(MonitorModel.normalizeHardwareValue("\tF31 \r\n"), "F31")
            compare(MonitorModel.normalizeHardwareValue("To be filled by O.E.M."), "")
            compare(MonitorModel.normalizeHardwareValue("Default string"), "")
            compare(MonitorModel.normalizeHardwareValue("Not Specified"), "")
            compare(MonitorModel.normalizeHardwareValue("x.x"), "")
            compare(MonitorModel.normalizeHardwareValue("N/A"), "")
            compare(MonitorModel.normalizeHardwareValue(null), "")
            compare(MonitorModel.normalizeHardwareValue("   "), "")
        }

        function test_parseCpuInfo_reads_amd_topology() {
            var raw =
                "processor\t: 0\n" +
                "vendor_id\t: AuthenticAMD\n" +
                "cpu family\t: 25\n" +
                "model\t\t: 97\n" +
                "model name\t: AMD Ryzen 7 7800X3D 8-Core Processor\n" +
                "cache size\t: 1024 KB\n" +
                "physical id\t: 0\n" +
                "siblings\t: 2\n" +
                "core id\t\t: 0\n" +
                "cpu cores\t: 8\n" +
                "\n" +
                "processor\t: 1\n" +
                "vendor_id\t: AuthenticAMD\n" +
                "model\t\t: 97\n" +
                "model name\t: AMD Ryzen 7 7800X3D 8-Core Processor\n" +
                "cache size\t: 1024 KB\n" +
                "physical id\t: 0\n" +
                "siblings\t: 2\n" +
                "core id\t\t: 1\n" +
                "cpu cores\t: 8\n"
            var cpu = MonitorModel.parseCpuInfo(raw)
            verify(cpu !== null)
            compare(cpu.model, "AMD Ryzen 7 7800X3D 8-Core Processor")
            compare(cpu.vendor, "AuthenticAMD")
            compare(cpu.logicalProcessors, 2)
            compare(cpu.physicalCores, 8) // cpu cores once per socket, not per CPU
            compare(cpu.sockets, 1)
            compare(cpu.cache, "1024 KB")
        }

        function test_parseCpuInfo_pair_fallback_without_cpu_cores() {
            var raw =
                "processor\t: 0\nmodel name\t: Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz\n" +
                "physical id\t: 0\ncore id\t\t: 0\n\n" +
                "processor\t: 1\nphysical id\t: 0\ncore id\t\t: 1\n\n" +
                "processor\t: 2\nphysical id\t: 1\ncore id\t\t: 0\n\n" +
                "processor\t: 3\nphysical id\t: 1\ncore id\t\t: 1\n"
            var cpu = MonitorModel.parseCpuInfo(raw)
            verify(cpu !== null)
            compare(cpu.logicalProcessors, 4)
            compare(cpu.sockets, 2)
            compare(cpu.physicalCores, 4) // 4 distinct socket:core pairs
        }

        function test_parseCpuInfo_rejects_missing_or_malformed_input() {
            verify(MonitorModel.parseCpuInfo("") === null)
            verify(MonitorModel.parseCpuInfo(null) === null)
            verify(MonitorModel.parseCpuInfo("no colon separated keys") === null)
            verify(MonitorModel.parseCpuInfo("processor\t: abc\n") === null)
        }

        function test_parseMemInfo_converts_kb_to_bytes() {
            var info = MonitorModel.parseMemInfo(
                "MemTotal:       48403948 kB\n" +
                "MemFree:         1847948 kB\n" +
                "MemAvailable:   23292312 kB\n" +
                "Active(anon):   13294160 kB\n" +
                "SwapTotal:      96807384 kB\n" +
                "SwapFree:       96789836 kB\n")
            verify(info !== null)
            compare(info.totalBytes, 48403948 * 1024)
            compare(info.availableBytes, 23292312 * 1024)
            compare(info.swapTotalBytes, 96807384 * 1024)
            compare(info.swapFreeBytes, 96789836 * 1024)

            var bare = MonitorModel.parseMemInfo("MemTotal: 8000000 kB\nMemFree: 1 kB\n")
            compare(bare.availableBytes, 0)
            compare(bare.swapTotalBytes, 0)

            verify(MonitorModel.parseMemInfo("MemFree: 100 kB\n") === null)
            verify(MonitorModel.parseMemInfo("") === null)
            verify(MonitorModel.parseMemInfo("MemTotal: zero kB\n") === null)
        }

        function test_parseOsRelease_quoted_and_bare_values() {
            var release = MonitorModel.parseOsRelease(
                "NAME=\"Omarchy\"\n" +
                "PRETTY_NAME=\"Omarchy\"\n" +
                "ID=omarchy\n" +
                "ID_LIKE=arch\n" +
                "VERSION_ID=\"4.0.0\"\n" +
                "BUILD_ID=\"4.0.0\"\n")
            verify(release !== null)
            compare(release.prettyName, "Omarchy")
            compare(release.name, "Omarchy")
            compare(release.id, "omarchy")
            compare(release.versionId, "4.0.0")
            compare(release.buildId, "4.0.0")

            var single = MonitorModel.parseOsRelease(
                "NAME='Fedora Linux'\nPRETTY_NAME=Fedora Linux 41\nID=fedora\n")
            compare(single.name, "Fedora Linux")
            compare(single.prettyName, "Fedora Linux 41")
            verify(single.versionId === null)
            verify(single.buildId === null)

            verify(MonitorModel.parseOsRelease("# only comments\n\n") === null)
            verify(MonitorModel.parseOsRelease("") === null)
        }

        function test_parseKernelInfo_splits_uname_srmo() {
            var kernel = MonitorModel.parseKernelInfo("Linux 7.1.8-arch1-3 x86_64 GNU/Linux")
            verify(kernel !== null)
            compare(kernel.full, "Linux 7.1.8-arch1-3 x86_64 GNU/Linux")
            compare(kernel.kernel, "7.1.8-arch1-3")
            compare(kernel.architecture, "x86_64")

            verify(MonitorModel.parseKernelInfo("Linux 6.1") === null)
            verify(MonitorModel.parseKernelInfo("") === null)
        }

        function test_parseLspciGraphics_lists_display_devices() {
            var raw =
                "0000:00:00.0 \"Host bridge\" \"Advanced Micro Devices, Inc. [AMD]\" " +
                "\"Raphael/Granite Ridge Root Complex\"\n" +
                "0000:01:00.0 \"VGA compatible controller\" \"NVIDIA Corporation\" " +
                "\"GB203 [GeForce RTX 5070 Ti]\" -ra1 -p00 \"ASUSTeK Computer Inc.\" \"Device 89f4\"\n" +
                "0000:01:00.1 \"Audio device\" \"NVIDIA Corporation\" " +
                "\"GB203 High Definition Audio Controller\"\n" +
                "0000:11:00.0 \"VGA compatible controller\" " +
                "\"Advanced Micro Devices, Inc. [AMD/ATI]\" \"Raphael\" -rcb\n" +
                "0000:12:00.0 \"Network controller\" \"Intel Corporation\" " +
                "\"Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak]\"\n"
            var gpus = MonitorModel.parseLspciGraphics(raw)
            compare(gpus.length, 2)
            compare(gpus[0].address, "0000:01:00.0")
            compare(gpus[0].className, "VGA compatible controller")
            compare(gpus[0].vendor, "NVIDIA Corporation")
            compare(gpus[0].device, "GB203 [GeForce RTX 5070 Ti]")
            compare(gpus[1].address, "0000:11:00.0")
            compare(gpus[1].device, "Raphael")

            var accelerator = MonitorModel.parseLspciGraphics(
                "0000:05:00.0 \"3D controller\" \"NVIDIA Corporation\" \"GA102GL [A40]\" -ra1\n")
            compare(accelerator.length, 1)
            compare(accelerator[0].className, "3D controller")

            compare(MonitorModel.parseLspciGraphics("").length, 0)
            compare(MonitorModel.parseLspciGraphics("not lspci output").length, 0)
        }

        function test_parseNvidiaHardware_reads_csv_query() {
            var gpu = MonitorModel.parseNvidiaHardware(
                "NVIDIA GeForce RTX 5070 Ti, 610.57.04, 16303")
            verify(gpu !== null)
            compare(gpu.name, "NVIDIA GeForce RTX 5070 Ti")
            compare(gpu.driverVersion, "610.57.04")
            compare(gpu.memoryTotalMiB, 16303)

            var first = MonitorModel.parseNvidiaHardware(
                "\nNVIDIA GeForce RTX 3070, 550.54.14, 8192\nNVIDIA GeForce RTX 3080, 550.54.14, 10240\n")
            compare(first.name, "NVIDIA GeForce RTX 3070")

            verify(MonitorModel.parseNvidiaHardware("") === null)
            verify(MonitorModel.parseNvidiaHardware("NVIDIA GeForce RTX 5070 Ti, 610.57.04") === null)
            verify(MonitorModel.parseNvidiaHardware("GPU, driver, [N/A]") === null)
        }
    }
}
