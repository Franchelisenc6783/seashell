// PermissionGuard.swift

// Pineapple 🍍
//
// Risk-tier classification for Wave Control Plane tools.
//
// Tier A (safe):    Read-only operations — log and proceed immediately.
// Tier B (confirm): Config writes — return a confirmation prompt; require
//                   caller to pass `approved: true` on the second call.
// Tier C (approve): Destructive or secret-touching operations — require
//                   explicit approval with a reason string.

import Foundation
import MCP

// MARK: - PermissionGuard

struct PermissionGuard {

    // MARK: Tier enum

    enum Tier: Equatable {
        case safe       // Tier A
        case confirm    // Tier B
        case approve    // Tier C
    }

    // MARK: Static tier map

    private static let tierMap: [String: Tier] = [
        // ── Tier A: reads ──────────────────────────────────────────────────
        "wave_get_settings":   .safe,
        "wave_get_widgets":    .safe,
        "wave_get_ai_presets": .safe,
        "wave_get_backgrounds":.safe,

        // ── Tier B: config writes ──────────────────────────────────────────
        "wave_set_setting":    .confirm,
        "wave_create_widget":  .confirm,
        "wave_update_widget":  .confirm,
        "wave_delete_widget":  .confirm,
        "wave_set_ai_preset":  .confirm,
        "wave_set_theme":      .confirm,
        "wave_set_appearance": .confirm,

        // ── Tier A: read operations ────────────────────────────────────────
        "wave_helper_status":      .safe,
        "wave_list_workspaces":    .safe,
        "wave_list_blocks":        .safe,
        "wave_get_scrollback":     .safe,
        "wave_get_block_meta":     .safe,
        "wave_view_file":          .safe,

        // ── Tier B: write operations ─────────────────────────────────────────
        "wave_connect_helper":     .confirm,
        "wave_run_in_block":       .confirm,
        "wave_create_block":       .confirm,
        "wave_delete_block":       .confirm,
        "wave_set_block_meta":     .confirm,
        "wave_edit_file":          .confirm,

        // ── Tier C: secrets ───────
        "wave_secret_set":     .approve,
        "wave_secret_get":     .approve,
        "wave_secret_delete":  .approve,
    ]

    // MARK: Public API

    /// Classify a tool by risk tier.
    /// Falls back to pattern-matching for unknown names so future tools
    /// get a sensible default without requiring a tierMap update.
    static func classify(_ toolName: String) -> Tier {
        if let tier = tierMap[toolName] {
            return tier
        }

        // Pattern fallback
        if toolName.contains("secret") {
            return .approve
        }
        if toolName.hasPrefix("wave_get_") {
            return .safe
        }
        if toolName.hasPrefix("wave_set_")
            || toolName.hasPrefix("wave_create_")
            || toolName.hasPrefix("wave_update_")
            || toolName.hasPrefix("wave_delete_") {
            return .confirm
        }

        return .safe
    }

    // MARK: Confirmation check helpers

    /// For Tier B tools: returns true if `approved: true` is present in args.
    static func isApproved(_ arguments: [String: MCP.Value]?) -> Bool {
        guard let arguments = arguments,
              let approvedValue = arguments["approved"],
              case .bool(let approved) = approvedValue else {
            return false
        }
        return approved
    }

    /// Build a standardised confirmation-request message for Tier B tools.
    static func confirmationMessage(
        for toolName: String,
        action: String,
        targetFile: String
    ) -> String {
        return """
        ⚠️  This operation will modify \(targetFile).

        Action: \(action)
        Tool: \(toolName)

        To proceed, call this tool again with the parameter: approved=true
        """
    }

    /// Build a standardised strong-warning message for Tier C tools.
    static func approvalMessage(
        for toolName: String,
        action: String
    ) -> String {
        return """
        🛑  This operation requires explicit approval.

        Action: \(action)
        Tool: \(toolName)

        This operation handles sensitive data. To proceed, call again with:
          approved=true
          reason="<your reason>"
        """
    }
}
