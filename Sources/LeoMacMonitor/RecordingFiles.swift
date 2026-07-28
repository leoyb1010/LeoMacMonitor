//
//  File:      RecordingFiles.swift
//  Created:   2026-06-25
//  Updated:   2026-06-25
//  Developer: Leo Yuan
//  Overview:  Small shared helpers for where session recordings live and how they're named —
//             a default ~/LeoMacMonitor folder (created on first use) and a timestamped base name.
//             Used by both RecordBar (open) and ReplayBar (export).
//
import Foundation

enum RecordingFiles {
    /// ~/LeoMac监控器, created on first use. The default location for recordings.
    static func defaultDir() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("LeoMac监控器", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A sortable, identifiable base name, e.g. "LeoMacMonitor-20260728-134522".
    static func timestampedName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        return "LeoMacMonitor-\(f.string(from: Date()))"
    }
}
