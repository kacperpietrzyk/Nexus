import SwiftUI

struct DetectionNotificationView: View {
    let appName: String
    let meetingTitle: String
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Meeting detected")
                    .font(.headline)
                Spacer()
            }
            Text("\(appName): \"\(meetingTitle)\"")
                .font(.body)
                .lineLimit(2)
            HStack {
                Button(action: onStart) {
                    Text("Start Recording").bold()
                }
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
