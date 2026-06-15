#if os(iOS)
import SwiftUI

public struct iOSMeetingsHostResolver: View {  // swiftlint:disable:this type_name
    private let composition: MeetingsComposition

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        iOSMeetingsListView(composition: composition)
    }
}
#endif
