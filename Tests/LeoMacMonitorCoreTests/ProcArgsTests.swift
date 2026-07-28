//
//  File:      ProcArgsTests.swift
//  Created:   2026-06-14
//  Updated:   2026-06-14
//  Developer: Leo Yuan
//  Overview:  Tests the sudoless KERN_PROCARGS2 argv reader (ProcessSampler.processArgs),
//             the single most bug-prone new syscall in the local-AI feature work.
//  Notes:     Verified against this very test process (a known, user-owned pid) so the
//             argc framing / exec-path skip / NUL splitting are exercised on real data,
//             plus a denied-pid path that must degrade to nil without crashing.
//
import XCTest
@testable import LeoMacMonitorCore

final class ProcArgsTests: XCTestCase {

    /// processArgs on our own pid must round-trip this process's argv: same count and
    /// argv[0] as CommandLine.arguments. This exercises argc framing + NUL splitting on
    /// real kernel data (no synthetic buffer needed).
    func testSelfArgvMatchesCommandLine() {
        let argv = ProcessSampler.processArgs(getpid())
        XCTAssertNotNil(argv, "processArgs should read our own (user-owned) argv sudolessly")
        guard let argv else { return }
        XCTAssertFalse(argv.isEmpty)
        XCTAssertEqual(argv.count, CommandLine.arguments.count,
                       "argc framing must yield the same number of args as CommandLine")
        XCTAssertEqual(argv.first, CommandLine.arguments.first,
                       "argv[0] (exec path) must match after the exec-path skip")
    }

    /// A clearly-invalid pid must degrade to nil (no crash, no permission prompt).
    func testInvalidPidReturnsNil() {
        XCTAssertNil(ProcessSampler.processArgs(pid_t(999_999)))
    }

    /// Every returned argument must be a clean, NUL-free string (NUL is the separator).
    func testNoEmbeddedNULsInResult() {
        guard let argv = ProcessSampler.processArgs(getpid()) else {
            return XCTFail("expected argv for self")
        }
        for arg in argv {
            XCTAssertFalse(arg.contains("\0"), "argv element should not contain NUL")
        }
    }
}
