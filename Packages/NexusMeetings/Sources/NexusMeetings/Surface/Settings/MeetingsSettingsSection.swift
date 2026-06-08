import NexusUI
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
        NexusSettingsDetailContainer(title: "Meetings") {
            VStack(alignment: .leading, spacing: NexusSpacing.s7) {
                if let helperContent {
                    helperContent
                }
                #if os(macOS)
                MeetingsDetectionSettingsView(composition: composition)
                #endif
                MeetingsRetentionSettingsView(composition: composition)
                MeetingsProviderSettingsView(composition: composition)
                MeetingsPromptSettingsView(composition: composition)
                #if os(macOS)
                MeetingsVocabularySettingsView()
                MeetingsScreenOCRSettingsView()
                #endif
                MeetingsImportSettingsView(composition: composition)
                #if os(iOS)
                if horizontalSizeClass != .regular {
                    browseGroup
                }
                #endif
            }
        }
    }

    #if os(iOS)
    private var browseGroup: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Browse")
            NexusSettingsCard {
                NavigationLink {
                    IOSMeetingsListContentView(composition: composition)
                } label: {
                    NexusSettingsRow("Browse meetings") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NexusColor.Text.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    #endif
}
