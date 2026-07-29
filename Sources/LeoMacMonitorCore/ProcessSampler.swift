//
//  File:      ProcessSampler.swift
//  Created:   2026-06-08
//  Updated:   2026-07-29
//  Developer: Leo Yuan
//  Overview:  Builds the process table sudolessly via libproc. Stateful: each
//             sample() diffs cumulative CPU time against the previous call to derive
//             CPU%. Memory is resident size (RSS). Also resolves each pid's executable
//             path (proc_pidpath) and, for AI-runtime candidates only, its argv
//             (KERN_PROCARGS2) — the plumbing AIRuntimeSampler builds on.
//  Notes:     proc_pidinfo(PROC_PIDTASKINFO) gives total_user+total_system (ns) and
//             resident_size. Processes the user cannot inspect are skipped. Prime
//             with one sample(), wait, then sample() again for meaningful CPU%.
//             proc_pidpath across ~1k pids is ~7 ms (measured) — cheap. argv is read
//             only for a small candidate shortlist so KERN_PROCARGS2 never runs per-pid.
//
import Foundation

public final class ProcessSampler {
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousTimeNs: UInt64 = 0

    private struct ProcessIdentity: Hashable {
        let pid: pid_t
        let startAbstime: UInt64
    }
    private struct DiskCounters {
        let read: UInt64
        let write: UInt64
    }
    private struct DiskRates {
        let read: Double
        let write: Double
    }
    private var previousDisk: [ProcessIdentity: DiskCounters] = [:]
    private var smoothedDisk: [ProcessIdentity: DiskRates] = [:]
    /// Approximately five seconds of damping keeps the "top writer" useful instead of letting
    /// one metadata burst reshuffle the UI every process-enumeration tick.
    private static let diskSmoothingWindow: TimeInterval = 5

    // Immutable per-pid metadata (executable path, name, basename) cached across ticks — these
    // never change for a process's lifetime, so re-resolving them every tick via proc_pidpath /
    // proc_name over thousands of pids was the enumeration's dominant cost (proc_pidpath alone is
    // ~24 ms/tick at ~3.4k pids). Only NEW pids pay the lookup; existing ones just re-read CPU.
    private struct PidInfo { let path: String; let name: String; let base: String }
    private var infoCache: [pid_t: PidInfo] = [:]

    /// proc_taskinfo's pti_total_user/system are mach-absolute-time ticks, NOT nanoseconds.
    /// On Apple Silicon the timebase is 125/3, so a raw tick count read as ns makes CPU%
    /// come out ~42x too low. Convert ticks → ns with this factor (identity on Intel).
    private static let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()

    /// Path basenames worth reading argv for (AI-runtime candidates only). Keeps the
    /// gated KERN_PROCARGS2 read off the hot path for the ~1k unrelated processes.
    private static let argvCandidateBasenames: Set<String> = [
        "llama-server", "llama-cli", "python", "python3", "lms", "ollama"
    ]

    public init() {}

    /// Returns processes sorted by CPU% (descending), capped at `count`
    /// (default: all, so the UI can re-sort/filter the full set).
    public func sample(top count: Int = .max) -> [ProcessRow] {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let wallDelta = previousTimeNs > 0 ? Double(nowNs &- previousTimeNs) : 0

        var currentCPU: [pid_t: UInt64] = [:]
        var currentDisk: [ProcessIdentity: DiskCounters] = [:]
        var currentSmoothedDisk: [ProcessIdentity: DiskRates] = [:]
        var rows: [ProcessRow] = []

        for pid in Self.allPIDs() where pid > 0 {
            guard let info = Self.taskInfo(pid) else { continue }
            let cpuTicks = info.pti_total_user + info.pti_total_system
            let cpuNs = cpuTicks * UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)
            currentCPU[pid] = cpuNs

            let prev = previousCPU[pid]
            var cpuPercent = 0.0
            if let prev, wallDelta > 0, cpuNs >= prev {
                cpuPercent = Double(cpuNs - prev) / wallDelta * 100.0
            }

            // Resolve path/name/basename from the cache (immutable per pid). Cumulative CPU only
            // ever rises within one process, so cpuNs < prev means the pid was recycled onto a new
            // process → drop the stale entry and re-resolve.
            if let prev, cpuNs < prev { infoCache[pid] = nil }
            let meta: PidInfo
            if let hit = infoCache[pid] {
                meta = hit
            } else {
                let p = Self.path(pid)
                meta = PidInfo(path: p, name: Self.name(pid), base: Self.basename(p))
                infoCache[pid] = meta
            }

            // argv only for AI-runtime candidates (gated by path basename). Python is
            // prefix-matched so versioned interpreters (python3.12 from conda/homebrew,
            // python3.13, …) still qualify — that's how mlx_lm / rapid-mlx args are seen.
            var args: String? = nil
            if Self.argvCandidateBasenames.contains(meta.base) || meta.base.hasPrefix("python"),
               let argv = Self.processArgs(pid), !argv.isEmpty {
                args = argv.joined(separator: " ")
            }

            let usage = Self.resourceUsage(pid)
            var readRate: Double? = nil
            var writeRate: Double? = nil
            if let usage {
                let identity = ProcessIdentity(pid: pid, startAbstime: usage.startAbstime)
                let counters = DiskCounters(read: usage.read, write: usage.write)
                currentDisk[identity] = counters
                if let old = previousDisk[identity], wallDelta > 0 {
                    let instantaneous = DiskRates(
                        read: Double(usage.read >= old.read ? usage.read - old.read : 0) / (wallDelta / 1_000_000_000),
                        write: Double(usage.write >= old.write ? usage.write - old.write : 0) / (wallDelta / 1_000_000_000)
                    )
                    let alpha = min(1, (wallDelta / 1_000_000_000) / Self.diskSmoothingWindow)
                    let prior = smoothedDisk[identity] ?? instantaneous
                    let smoothed = DiskRates(
                        read: prior.read + alpha * (instantaneous.read - prior.read),
                        write: prior.write + alpha * (instantaneous.write - prior.write)
                    )
                    currentSmoothedDisk[identity] = smoothed
                    readRate = smoothed.read
                    writeRate = smoothed.write
                }
            }

            rows.append(ProcessRow(
                pid: pid,
                name: meta.name,
                cpuPercent: cpuPercent,
                memoryBytes: info.pti_resident_size,
                path: meta.path,
                args: args,
                diskReadBytes: usage?.read,
                diskWriteBytes: usage?.write,
                diskReadBytesPerSec: readRate,
                diskWriteBytesPerSec: writeRate,
                startAbstime: usage?.startAbstime
            ))
        }

        previousCPU = currentCPU
        previousDisk = currentDisk
        smoothedDisk = currentSmoothedDisk
        previousTimeNs = nowNs
        // Drop cached metadata for pids that are gone so the cache can't grow unbounded.
        let live = Set(currentCPU.keys)
        infoCache = infoCache.filter { live.contains($0.key) }

        return Array(rows.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(count))
    }

    // MARK: - libproc helpers

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let byteCount = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }
        let actual = Int(byteCount)
        return Array(pids.prefix(actual))
    }

    private static func taskInfo(_ pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? info : nil
    }

    private static func resourceUsage(_ pid: pid_t) -> (startAbstime: UInt64, read: UInt64, write: UInt64)? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0, info.ri_proc_exit_abstime == 0 else { return nil }
        return (info.ri_proc_start_abstime, info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
    }

    private static func name(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cBuffer: buffer) : "pid \(pid)"
    }

    /// Full executable path, or "" if libproc denies it (root/other-user pids).
    private static func path(_ pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE (4*MAXPATHLEN) isn't importable into Swift (arithmetic
        // macro), so use its literal value.
        let maxSize = 4 * 1024
        var buffer = [CChar](repeating: 0, count: maxSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cBuffer: buffer) : ""
    }

    private static func basename(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }

    /// Reads a process's argv via KERN_PROCARGS2. Sudoless for user-owned processes;
    /// returns nil if denied. Layout: [Int32 argc][exec_path\0...][\0 padding][argv0\0 argv1\0 ...].
    /// Battle-tested parser — handles argc framing, exec-path skip, and NUL padding.
    static func processArgs(_ pid: pid_t) -> [String]? {
        var argmax: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        var mibAM = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibAM, 2, &argmax, &sz, nil, 0) == 0, argmax > 0 else { return nil }

        var buf = [CChar](repeating: 0, count: Int(argmax))
        var size = Int(argmax)
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var argc: Int32 = 0
        memcpy(&argc, buf, MemoryLayout<Int32>.size)
        guard argc > 0 else { return nil }

        var cursor = MemoryLayout<Int32>.size
        while cursor < size && buf[cursor] != 0 { cursor += 1 }      // skip exec path
        while cursor < size && buf[cursor] == 0 { cursor += 1 }      // skip NUL padding

        var result: [String] = []
        var collected = 0
        while collected < Int(argc) && cursor < size {
            let start = cursor
            while cursor < size && buf[cursor] != 0 { cursor += 1 }
            let arg = buf[start..<cursor].withUnsafeBufferPointer { p in
                String(decoding: p.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            result.append(arg)
            collected += 1
            cursor += 1
        }
        return result.isEmpty ? nil : result
    }
}
