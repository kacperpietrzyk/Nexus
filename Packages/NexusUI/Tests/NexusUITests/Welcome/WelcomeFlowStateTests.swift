import Testing

@testable import NexusUI

@Suite("WelcomeFlowState")
@MainActor
struct WelcomeFlowStateTests {
    @Test("Initial state is screen 0 and not finished")
    func initialState() {
        let state = WelcomeFlowState()
        #expect(state.currentScreen == 0)
        #expect(state.isFinished == false)
    }

    @Test("advance from screen 0 to 1")
    func advanceFromZero() {
        let state = WelcomeFlowState()
        state.advance()
        #expect(state.currentScreen == 1)
        #expect(state.isFinished == false)
    }

    @Test("advance from last screen marks finished")
    func advanceFromLastFinishes() {
        let state = WelcomeFlowState()
        state.advance()
        state.advance()
        #expect(state.isFinished == true)
    }

    @Test("skip from any screen marks finished")
    func skipFinishes() {
        let s0 = WelcomeFlowState()
        s0.skip()
        #expect(s0.isFinished == true)

        let s1 = WelcomeFlowState()
        s1.advance()
        s1.skip()
        #expect(s1.isFinished == true)
    }

    @Test("totalScreens is 2")
    func totalScreens() {
        #expect(WelcomeFlowState.totalScreens == 2)
    }

    @Test("extra screen count extends flow without changing default total")
    func extraScreenCount() {
        let state = WelcomeFlowState(extraScreenCount: 1)
        #expect(WelcomeFlowState.totalScreens == 2)
        #expect(state.totalScreenCount == 3)

        state.advance()
        #expect(state.currentScreen == 1)
        #expect(state.isLastScreen == false)

        state.advance()
        #expect(state.currentScreen == 2)
        #expect(state.isLastScreen == true)

        state.advance()
        #expect(state.isFinished == true)
    }

    @Test("totalScreenCount is 2 + extraScreenCount for n in 0,1,2")
    func totalScreenCountMath() {
        for extra in 0...2 {
            let state = WelcomeFlowState(extraScreenCount: extra)
            #expect(state.totalScreenCount == 2 + extra)
        }
    }

    @Test("isLastScreen true only on last screen")
    func isLastScreen() {
        let state = WelcomeFlowState()
        #expect(state.isLastScreen == false)
        state.advance()
        #expect(state.isLastScreen == true)
    }
}
