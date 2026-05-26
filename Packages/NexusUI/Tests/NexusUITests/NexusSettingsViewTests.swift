import SwiftUI
import Testing

@testable import NexusUI

#if !os(watchOS)

@MainActor
@Test func nexusSettingsView_init_doesNotCrash() {
    let view = NexusSettingsView(
        cloudKitEnabled: false,
        containerIdentifier: "iCloud.com.example.test",
        onExportRequested: {}
    )
    _ = view.body
}

@MainActor
@Test func exportFolderPicker_init_storesCallback() {
    var fired = false
    let picker = ExportFolderPicker(isPresented: .constant(true)) { _ in fired = true }
    _ = picker.body
    #expect(fired == false)  // body alone doesn't fire
}

/// Traverses the denied path so the retuned `deniedBanner` /
/// `calendarSettingsArea` warning icon / `calendarPermissionStatusLabel`
/// / `nexusSettingsSectionHeader` resolve along the section body. Guards
/// the MP-4.1 slice-1 accent burn-down against build/resolution
/// regressions.
@MainActor
@Test func nexusSettingsView_deniedNotificationsPath_resolvesBody() {
    let start = Date(timeIntervalSince1970: 0)
    let end = Date(timeIntervalSince1970: 3600)
    let view = NexusSettingsView(
        cloudKitEnabled: true,
        containerIdentifier: "iCloud.com.example.test",
        notificationsAuthorized: false,
        quietHoursStartTime: .constant(start),
        quietHoursEndTime: .constant(end),
        onExportRequested: {}
    )
    _ = view.body
}

/// The section-header helper resolves to a view. Pins the MP-4.1 slice-1
/// retune to the oracle group-eyebrow idiom (raw `GeistMono-SemiBold`
/// size 10 / tracking 1.8 / `Text.muted`) against accidental removal.
@MainActor
@Test func nexusSettingsSectionHeader_resolves() {
    _ = nexusSettingsSectionHeader("Zadania")
}

#endif
