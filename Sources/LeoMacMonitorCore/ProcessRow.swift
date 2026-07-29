//
//  File:      ProcessRow.swift
//  Created:   2026-06-08
//  Updated:   2026-07-29
//  Developer: Leo Yuan
//  Overview:  One row of the process table: pid, name, CPU%, resident memory, plus the
//             full executable path, process I/O counters/rates, and (for AI-runtime
//             candidates only) the argv string.
//  Notes:     cpuPercent is summed across cores (top-style, can exceed 100). It is a
//             delta between two ProcessSampler reads, so the first read reports 0.
//             path is "" when libproc denies it (system pids) — callers fall back to
//             name. args is nil unless the process is an AI-runtime candidate (gated
//             KERN_PROCARGS2 read). Both default in init for source compatibility.
//
import Foundation

public struct ProcessRow: Sendable, Equatable, Identifiable, Codable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let path: String          // full executable path; "" if libproc denied it
    public let args: String?         // argv joined by spaces; nil unless an AI-runtime candidate
    /// Process-wide cumulative I/O and smoothed rates. These are intentionally optional:
    /// libproc denies rusage for some system/other-user processes, and old recordings predate
    /// these fields. A nil value means unavailable, never zero activity.
    public let diskReadBytes: UInt64?
    public let diskWriteBytes: UInt64?
    public let diskReadBytesPerSec: Double?
    public let diskWriteBytesPerSec: Double?
    /// mach absolute start time. Combined with pid it prevents PID-reuse spikes.
    public let startAbstime: UInt64?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64,
                path: String = "", args: String? = nil,
                diskReadBytes: UInt64? = nil, diskWriteBytes: UInt64? = nil,
                diskReadBytesPerSec: Double? = nil, diskWriteBytesPerSec: Double? = nil,
                startAbstime: UInt64? = nil) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.path = path
        self.args = args
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.startAbstime = startAbstime
    }

    public var memoryMB: Double { Double(memoryBytes) / (1024.0 * 1024.0) }
    public var diskTotalBytesPerSec: Double? {
        guard diskReadBytesPerSec != nil || diskWriteBytesPerSec != nil else { return nil }
        return (diskReadBytesPerSec ?? 0) + (diskWriteBytesPerSec ?? 0)
    }
}
