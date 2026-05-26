import SwiftUI
import Testing

@testable import NexusUI

@Test func nexusCountBuilds() {
    _ = NexusCount(value: 12, font: NexusType.meta)
    _ = NexusCount(value: 0, font: NexusType.meta, color: NexusColor.Text.disabled)
}
