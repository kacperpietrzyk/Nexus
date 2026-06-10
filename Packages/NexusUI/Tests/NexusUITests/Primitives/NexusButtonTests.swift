import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusButton v4")
struct NexusButtonTests {
    private struct SizeExpectation {
        let size: NexusButtonSize
        let height: CGFloat
        let padding: CGFloat
        let radius: CGFloat
        let width: CGFloat?
    }

    private struct VariantExpectation {
        let variant: NexusButtonVariant
        let text: Color
    }

    @Test("Variant enum exposes coss cases")
    func variantCases() {
        #expect(NexusButtonVariant.allCases == [.default, .primary, .outline, .ghost])
    }

    @Test("Size enum exposes coss cases")
    func sizeCases() {
        #expect(NexusButtonSize.allCases == [.sm, .md, .lg, .icon, .iconSm])
    }

    @MainActor
    @Test("All variant and size combinations build")
    func allCombinationsBuild() {
        for variant in NexusButtonVariant.allCases {
            for size in NexusButtonSize.allCases {
                let button = NexusButton(
                    variant: variant, size: size, action: {},
                    label: {
                        Text("ok")
                    })

                _ = button.body
            }
        }
    }

    @MainActor
    @Test("Button size metrics match canvas scale")
    func sizeMetrics() {
        let expected: [SizeExpectation] = [
            .init(size: .sm, height: 26, padding: 10, radius: NexusRadius.r2, width: nil),
            .init(size: .md, height: 30, padding: 12, radius: NexusRadius.r2, width: nil),
            .init(size: .lg, height: 36, padding: 16, radius: NexusRadius.r3, width: nil),
            .init(size: .icon, height: 30, padding: 0, radius: NexusRadius.r2, width: 30),
            .init(size: .iconSm, height: 26, padding: 0, radius: NexusRadius.r2, width: 26),
        ]

        for expectation in expected {
            let button = NexusButton(
                size: expectation.size, action: {},
                label: {
                    Text("ok")
                })

            #expect(button.height == expectation.height)
            #expect(button.hPadding == expectation.padding)
            #expect(button.radius == expectation.radius)
            #expect(button.fixedWidth == expectation.width)
        }
    }

    @MainActor
    @Test("Button variants resolve foreground (primary=white ink on violet accent, others=read)")
    func variantColors() {
        let expected: [VariantExpectation] = [
            .init(variant: .default, text: NexusColor.Text.secondary),
            .init(variant: .primary, text: NexusColor.Accent.limeInk),
            .init(variant: .outline, text: NexusColor.Text.secondary),
            .init(variant: .ghost, text: NexusColor.Text.secondary),
        ]

        for expectation in expected {
            let button = NexusButton(
                variant: expectation.variant, action: {},
                label: {
                    Text("ok")
                })

            #expect(button.textColor.resolvedRGBA == expectation.text.resolvedRGBA)
        }
    }

    @MainActor
    @Test("Action remains invokable")
    func actionInvokes() {
        var invoked = false
        let button = NexusButton(
            variant: .primary, size: .lg, action: { invoked = true },
            label: {
                Text("ok")
            })

        button.action()

        #expect(invoked)
    }
}
