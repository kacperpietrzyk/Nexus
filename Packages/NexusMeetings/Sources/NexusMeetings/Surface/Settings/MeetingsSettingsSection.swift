import SwiftUI

#if !(os(macOS) && canImport(ServiceManagement))
public typealias MeetingsHelperSettingsViewModel = Never
#endif

public struct MeetingsSettingsSection: View {
    private let composition: MeetingsComposition
    private let helperContent: AnyView?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(
        composition: MeetingsComposition,
        helperViewModel: MeetingsHelperSettingsViewModel?
    ) {
        self.composition = composition
        #if os(macOS) && canImport(ServiceManagement)
        self.helperContent = helperViewModel.map {
            AnyView(MeetingsHelperSettingsView(viewModel: $0))
        }
        #else
        self.helperContent = nil
        #endif
    }

    public var body: some View {
        Form {
            if let helperContent {
                helperContent
            }
            #if os(macOS)
            MeetingsDetectionSettingsView(composition: composition)
            #endif
            MeetingsRetentionSettingsView(composition: composition)
            MeetingsProviderSettingsView(composition: composition)
            MeetingsPromptSettingsView(composition: composition)
            MeetingsImportSettingsView(composition: composition)
            #if os(iOS)
            if horizontalSizeClass != .regular {
                Section("Browse") {
                    NavigationLink {
                        IOSMeetingsListContentView(composition: composition)
                    } label: {
                        Label("Browse meetings", systemImage: "person.wave.2")
                    }
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Meetings")
    }
}
