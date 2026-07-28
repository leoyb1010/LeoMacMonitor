//
//  File:      SystemInfo.swift
//  Created:   2026-06-19
//  Updated:   2026-06-19
//  Developer: Leo Yuan
//  Overview:  Small sudoless system facts for the rich menu-bar dropdowns: load average
//             (getloadavg) and uptime (sysctl kern.boottime).
//  Notes:     Both are cheap, allocation-free libc calls. Uptime is now − boottime.
//
import Foundation

enum SystemInfo {
    /// 1 / 5 / 15-minute load averages, e.g. "2.31 · 2.10 · 1.88".
    static func loadAverageString() -> String {
        var l = [Double](repeating: 0, count: 3)
        guard getloadavg(&l, 3) == 3 else { return "—" }
        return String(format: "%.2f · %.2f · %.2f", l[0], l[1], l[2])
    }

    /// Compact uptime, e.g. "4d 9h" / "3h 12m" / "8m".
    static func uptimeString() -> String {
        var bt = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bt, &size, nil, 0) == 0, bt.tv_sec > 0 else { return "—" }
        let secs = Int(Date().timeIntervalSince1970) - bt.tv_sec
        guard secs > 0 else { return "—" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
