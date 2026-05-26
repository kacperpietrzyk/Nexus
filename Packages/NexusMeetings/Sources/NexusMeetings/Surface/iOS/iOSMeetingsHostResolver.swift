#if os(iOS)
import SwiftUI

public struct iOSMeetingsHostResolver: View {  // swiftlint:disable:this type_name
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let composition: MeetingsComposition

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        if sizeClass == .regular {
            iOSMeetingsListView(composition: composition)
        } else {
            EmptyView()
        }
    }
}
#endif
