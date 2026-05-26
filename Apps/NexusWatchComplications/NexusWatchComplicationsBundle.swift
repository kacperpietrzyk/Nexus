import SwiftUI
import WidgetKit

@main
struct NexusWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        TodayCircularComplication()
        TodayRectangularComplication()
    }
}
