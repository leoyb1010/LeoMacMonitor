//
//  File:      CBuffer.swift
//  Created:   2026-06-22
//  Updated:   2026-06-22
//  Developer: Leo Yuan
//  Overview:  Small helper to build a String from a null-terminated C-char buffer, replacing
//             the deprecated `String(cString: [CChar])` (Swift 6.2 / macOS 26 SDK warns on the
//             array overload — the UnsafePointer overload stays fine).
//  Notes:     Truncates at the first NUL, then decodes the rest as UTF-8 — matching the old
//             `String(cString:)` behavior for the ASCII/UTF-8 buffers we read (sysctl strings,
//             interface names, process names).
//
import Foundation

extension String {
    /// Builds a String from a null-terminated `[CChar]` buffer (NUL-truncated, UTF-8 decoded).
    init(cBuffer: [CChar]) {
        self = String(decoding: cBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
