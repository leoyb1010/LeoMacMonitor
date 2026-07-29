import XCTest
@testable import LeoMacMonitorCore

final class AgentWorkloadTests: XCTestCase {
    func testMatchesSupportedAgentFamiliesWithoutLooseFalsePositives() {
        XCTAssertEqual(AgentKind.match(path: "/Applications/ChatGPT.app/Contents/Resources/codex",
                                       name: "codex"), .codex)
        XCTAssertEqual(AgentKind.match(path: "/Applications/Claude.app/Contents/MacOS/Claude",
                                       name: "Claude"), .claude)
        XCTAssertEqual(AgentKind.match(path: "/Applications/WorkBuddy.app/Contents/MacOS/WorkBuddy",
                                       name: "WorkBuddy"), .workBuddy)
        XCTAssertEqual(AgentKind.match(path: "/opt/homebrew/bin/opencode", name: "opencode"), .openCode)
        XCTAssertEqual(AgentKind.match(path: "/Users/x/.local/bin/gemini", name: "gemini"), .gemini)
        XCTAssertNil(AgentKind.match(path: "/usr/bin/code", name: "code"))
        XCTAssertNil(AgentKind.match(path: "/Applications/Claude Monet.app/paint", name: "paint"))
    }

    func testAggregatesProcessFamilyResourcesAndPrimaryPID() {
        let sampler = AgentWorkloadSampler()
        let sample = sampler.sample(from: [
            row(pid: 10, name: "codex", path: "/Applications/ChatGPT.app/Contents/Resources/codex",
                cpu: 12, memory: 100, read: 20, write: 30),
            row(pid: 11, name: "Codex (Renderer)",
                path: "/Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Renderer",
                cpu: 4, memory: 200, read: 40, write: 50),
        ])

        let codex = sample.workload(for: .codex)
        XCTAssertEqual(codex?.state, .working)
        XCTAssertEqual(codex?.processCount, 2)
        XCTAssertEqual(codex?.cpuPercent, 16)
        XCTAssertEqual(codex?.memoryBytes, 300)
        XCTAssertEqual(codex?.diskReadBytesPerSec, 60)
        XCTAssertEqual(codex?.diskWriteBytesPerSec, 80)
        XCTAssertEqual(codex?.primaryPID, 10)
    }

    func testActivityStateDoesNotClaimTaskSemantics() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let sampler = AgentWorkloadSampler(now: { clock })
        let active = row(pid: 20, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude",
                         cpu: 8, memory: 1_000)
        XCTAssertEqual(sampler.sample(from: [active]).workload(for: .claude)?.state, .working)

        clock.addTimeInterval(3)
        let quiet = row(pid: 20, name: "Claude", path: active.path, cpu: 0, memory: 1_000)
        XCTAssertEqual(sampler.sample(from: [quiet]).workload(for: .claude)?.state, .recentlyActive)

        clock.addTimeInterval(9)
        XCTAssertEqual(sampler.sample(from: [quiet]).workload(for: .claude)?.state, .waiting)
    }

    private func row(pid: Int32, name: String, path: String, cpu: Double, memory: UInt64,
                     read: Double? = nil, write: Double? = nil) -> ProcessRow {
        ProcessRow(pid: pid, name: name, cpuPercent: cpu, memoryBytes: memory, path: path,
                   diskReadBytesPerSec: read, diskWriteBytesPerSec: write)
    }
}
