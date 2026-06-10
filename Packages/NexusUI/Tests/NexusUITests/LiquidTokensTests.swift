import Testing

@testable import NexusUI

@Test func liquidTokens_sizeValues() {
    #expect(DS.Size.sidebarWidth == 224)
    #expect(DS.Size.rightInspectorWidth == 304)
    #expect(DS.Size.toolbarHeight == 58)
    #expect(DS.Size.navItemHeight == 34)
    #expect(DS.Size.cardMinHeight == 120)
    #expect(DS.Size.contentMinWidth == 760)
    #expect(DS.Size.windowMinWidth == 1180)
    #expect(DS.Size.windowIdealWidth == 1448)
    #expect(DS.Size.windowIdealHeight == 1086)
}

@Test func liquidTokens_radiusValues() {
    #expect(DS.Radius.xs == 6)
    #expect(DS.Radius.s == 8)
    #expect(DS.Radius.m == 12)
    #expect(DS.Radius.l == 16)
    #expect(DS.Radius.xl == 20)
    #expect(DS.Radius.window == 22)
    #expect(DS.Radius.pill == 999)
}

@Test func liquidTokens_spaceValues() {
    #expect(DS.Space.xxs == 4)
    #expect(DS.Space.xs == 6)
    #expect(DS.Space.s == 8)
    #expect(DS.Space.m == 12)
    #expect(DS.Space.l == 16)
    #expect(DS.Space.xl == 20)
    #expect(DS.Space.xxl == 24)
    #expect(DS.Space.xxxl == 32)
}
