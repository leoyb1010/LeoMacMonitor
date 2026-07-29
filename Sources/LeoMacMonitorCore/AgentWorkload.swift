//
//  AgentWorkload.swift
//  LeoMacMonitorCore
//
//  Local coding-agent identity and resource activity. This layer intentionally records only
//  process metadata and resource counters — never prompts, chat text, source code, or filenames.
//

import Foundation

public enum AgentKind: String, Sendable, CaseIterable, Codable {
    case codex
    case claude
    case workBuddy
    case openCode
    case gemini
    case cursor
    case copilot

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .workBuddy: return "WorkBuddy"
        case .openCode: return "OpenCode"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor Agent"
        case .copilot: return "Copilot"
        }
    }

    /// Bundle/path identity first, then bounded executable names. Deliberately avoids loose
    /// substring matching for short names (for example `code`) that would classify unrelated apps.
    public static func match(path: String, name: String) -> AgentKind? {
        let p = path.lowercased()
        let n = name.lowercased()
        let base = (p as NSString).lastPathComponent

        if p.contains("/codex.app/") || p.contains("/codex framework.framework/")
            || p.contains("/@openai/codex/") || p.contains("/chatgpt.app/contents/resources/codex")
            || base == "codex" || n == "codex" || n.hasPrefix("codex (")
            || n == "codex-code-mode-host" { return .codex }

        if p.contains("/claude.app/") || p.contains("/@anthropic-ai/claude-code/")
            || base == "claude" || n == "claude" || n.hasPrefix("claude helper")
            || n == "claude-code" { return .claude }

        if p.contains("/workbuddy.app/") || p.contains("/work-buddy.app/")
            || base == "workbuddy" || base == "work-buddy"
            || n == "workbuddy" || n.hasPrefix("workbuddy helper") { return .workBuddy }

        if p.contains("/opencode.app/") || p.contains("/opencode-ai/")
            || base == "opencode" || n == "opencode" { return .openCode }

        if p.contains("/gemini.app/") || p.contains("/@google/gemini-cli/")
            || base == "gemini" || n == "gemini" { return .gemini }

        if base == "cursor-agent" || n == "cursor-agent"
            || p.contains("/cursor.app/contents/resources/app/bin/cursor-agent") { return .cursor }

        if base == "github-copilot-cli" || base == "copilot"
            || n == "github-copilot-cli" { return .copilot }

        return nil
    }
}

public enum AgentActivityState: String, Sendable, Codable {
    case working
    case recentlyActive
    case waiting
}

public struct AgentWorkload: Sendable, Equatable, Identifiable, Codable {
    public let kind: AgentKind
    public let state: AgentActivityState
    public let processCount: Int
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let diskReadBytesPerSec: Double
    public let diskWriteBytesPerSec: Double
    public let primaryPID: Int32?
    public let activeSeconds: TimeInterval

    public var id: AgentKind { kind }
    public var isActive: Bool { state == .working }
    public var memoryMB: Double { Double(memoryBytes) / 1_048_576 }
    public var diskBytesPerSec: Double { diskReadBytesPerSec + diskWriteBytesPerSec }

    public init(kind: AgentKind, state: AgentActivityState, processCount: Int,
                cpuPercent: Double, memoryBytes: UInt64,
                diskReadBytesPerSec: Double, diskWriteBytesPerSec: Double,
                primaryPID: Int32?, activeSeconds: TimeInterval) {
        self.kind = kind
        self.state = state
        self.processCount = processCount
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.primaryPID = primaryPID
        self.activeSeconds = activeSeconds
    }
}

public struct AgentWorkloadSample: Sendable, Equatable, Codable {
    public var workloads: [AgentWorkload]

    public init(workloads: [AgentWorkload] = []) { self.workloads = workloads }

    public static let empty = AgentWorkloadSample()
    public var runningCount: Int { workloads.count }
    public var activeCount: Int { workloads.filter(\.isActive).count }
    public var totalCPUPercent: Double { workloads.reduce(0) { $0 + $1.cpuPercent } }
    public var totalMemoryBytes: UInt64 { workloads.reduce(0) { $0 + $1.memoryBytes } }
    public var primary: AgentWorkload? {
        workloads.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.cpuPercent > $1.cpuPercent
        }.first
    }

    public func workload(for kind: AgentKind) -> AgentWorkload? {
        workloads.first { $0.kind == kind }
    }
}
