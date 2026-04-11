import Foundation

/// Single source of truth for all magic strings and configuration values.
/// No other file may hardcode these values directly.
public enum AppConstants {

    // MARK: - App Group

    /// Shared App Group identifier — must match entitlements for both app + widget targets.
    public static let appGroupID = "group.com.shrirajpatil.voicedo"  // swiftlint:disable:this no_magic_strings_appgroup

    // MARK: - URL Scheme

    /// Deep-link URL scheme registered in Info.plist.
    public static let urlScheme = "voicedo"

    // MARK: - Keychain

    public static let keychainService = "com.shrirajpatil.voicedo.claudeapikey"
    public static let keychainAccount = "user_provided_key"

    // MARK: - Widget

    public static let widgetKind = "VoiceDoWidget"
    public static let widgetSnapshotKey = "widget_snapshot_v1"

    // MARK: - Claude API

    public static let claudeModel = "claude-sonnet-4-6"
    public static let claudeAPIEndpoint = "https://api.anthropic.com/v1/messages"
    public static let claudeTimeoutSeconds: Double = 8.0

    // MARK: - Parsing

    /// Minimum confidence from offline parser to skip Claude API call.
    public static let offlineConfidenceThreshold: Double = 0.8

    /// Maximum recording duration in seconds before auto-stop.
    public static let maxRecordingSeconds: Double = 60.0

    // MARK: - SwiftData

    /// SQLite filename stored inside the App Group container.
    public static let sqliteFilename = "VoiceDo.sqlite"

    // MARK: - Logging

    public static let logSubsystem = "com.shrirajpatil.voicedo"
}
