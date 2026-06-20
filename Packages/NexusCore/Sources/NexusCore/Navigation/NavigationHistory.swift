// Navigation history: pure value-type back/forward stack for shell-owned navigation.

public struct NavLocation: Equatable, Codable, Sendable {
    public var destinationToken: String
    public var detailToken: String?

    public init(destinationToken: String, detailToken: String?) {
        self.destinationToken = destinationToken
        self.detailToken = detailToken
    }
}

public struct NavigationHistory: Equatable, Sendable {
    public private(set) var current: NavLocation
    private var backStack: [NavLocation] = []
    private var forwardStack: [NavLocation] = []

    public init(current: NavLocation) {
        self.current = current
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Pushes the current location onto the back stack, clears the forward stack,
    /// and sets `location` as current. No-op if `location == current`.
    public mutating func visit(_ location: NavLocation) {
        guard location != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = location
    }

    /// Moves back one step. Returns the new current, or `nil` if back stack is empty.
    @discardableResult
    public mutating func goBack() -> NavLocation? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    /// Moves forward one step. Returns the new current, or `nil` if forward stack is empty.
    @discardableResult
    public mutating func goForward() -> NavLocation? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }
}
