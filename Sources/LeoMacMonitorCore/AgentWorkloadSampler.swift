//
//  AgentWorkloadSampler.swift
//  LeoMacMonitorCore
//
//  Aggregates matching process families and derives an honest resource-activity state. The state
//  never claims to know prompt/task contents: `working` means observed CPU or disk activity.
//

import Foundation

public final class AgentWorkloadSampler {
    private struct ActivityMemory {
        var activeSince: Date?
        var lastActive: Date?
    }

    private var memory: [AgentKind: ActivityMemory] = [:]
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func sample(from rows: [ProcessRow]) -> AgentWorkloadSample {
        let sampledAt = now()
        let groups = Dictionary(grouping: rows) { AgentKind.match(path: $0.path, name: $0.name) }
        var result: [AgentWorkload] = []

        for kind in AgentKind.allCases {
            guard let matches = groups[kind], !matches.isEmpty else {
                memory[kind] = nil
                continue
            }

            let cpu = matches.reduce(0) { $0 + $1.cpuPercent }
            let rss = matches.reduce(UInt64(0)) { partial, row in
                let (sum, overflow) = partial.addingReportingOverflow(row.memoryBytes)
                return overflow ? UInt64.max : sum
            }
            let read = matches.reduce(0) { $0 + ($1.diskReadBytesPerSec ?? 0) }
            let write = matches.reduce(0) { $0 + ($1.diskWriteBytesPerSec ?? 0) }
            let resourceActive = cpu >= 2.0 || read + write >= 64 * 1_024

            var history = memory[kind] ?? ActivityMemory()
            let state: AgentActivityState
            if resourceActive {
                history.activeSince = history.activeSince ?? sampledAt
                history.lastActive = sampledAt
                state = .working
            } else if let last = history.lastActive, sampledAt.timeIntervalSince(last) < 8 {
                history.activeSince = nil
                state = .recentlyActive
            } else {
                history.activeSince = nil
                state = .waiting
            }
            memory[kind] = history

            let primary = matches.max { $0.cpuPercent < $1.cpuPercent }
            let activeSeconds = history.activeSince.map { sampledAt.timeIntervalSince($0) } ?? 0
            result.append(AgentWorkload(
                kind: kind,
                state: state,
                processCount: matches.count,
                cpuPercent: cpu,
                memoryBytes: rss,
                diskReadBytesPerSec: read,
                diskWriteBytesPerSec: write,
                primaryPID: primary?.pid,
                activeSeconds: activeSeconds
            ))
        }

        result.sort {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            return $0.kind.displayName < $1.kind.displayName
        }
        return AgentWorkloadSample(workloads: result)
    }
}
