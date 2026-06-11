import Foundation

/// Deterministic force-directed layout: Hooke springs along edges, pairwise
/// repulsion, gravity toward the origin, semi-implicit Euler integration, and
/// seeded initial placement. Pure value type: no SwiftData, no SwiftUI.
public struct ForceLayoutEngine: Sendable {
    public struct Parameters: Sendable {
        public var springLength: Double = 110
        public var springStiffness: Double = 0.06
        public var repulsionStrength: Double = 9000
        public var gravityStrength: Double = 0.02
        public var damping: Double = 0.82
        public var timestep: Double = 1
        public var settleSpeed: Double = 0.08
        public var maxSteps: Int = 900

        public init() {}
    }

    public let nodeIDs: [GraphNodeID]
    public private(set) var positions: [SIMD2<Double>]
    public private(set) var stepCount = 0
    public private(set) var isSettled: Bool

    private var velocities: [SIMD2<Double>]
    private let edges: [(Int, Int)]
    private let parameters: Parameters

    public init(snapshot: GraphSnapshot, parameters: Parameters = Parameters(), seed: UInt64) {
        self.nodeIDs = snapshot.nodes.map(\.nodeID)
        self.parameters = parameters

        var rng = SplitMix64(seed: seed)
        let count = nodeIDs.count
        let radius = max(
            parameters.springLength,
            parameters.springLength * Double(count).squareRoot() / 2
        )
        self.positions = (0..<count).map { _ in
            let angle = rng.nextUnitDouble() * 2 * .pi
            let distance = radius * rng.nextUnitDouble().squareRoot()
            return SIMD2(distance * cos(angle), distance * sin(angle))
        }
        self.velocities = Array(repeating: SIMD2(0, 0), count: count)

        let indexByID = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, $0) })
        self.edges = snapshot.edges.compactMap { edge in
            guard let from = indexByID[edge.from], let to = indexByID[edge.to] else { return nil }
            return (from, to)
        }
        self.isSettled = count <= 1
    }

    @discardableResult
    public mutating func step() -> Bool {
        guard !isSettled else { return true }
        guard stepCount < parameters.maxSteps else {
            isSettled = true
            return true
        }

        var forces = [SIMD2<Double>](repeating: SIMD2(0, 0), count: positions.count)
        applyRepulsion(to: &forces)
        applySprings(to: &forces)
        applyGravity(to: &forces)

        let maxSpeed = integrate(forces: forces)
        stepCount += 1
        if maxSpeed < parameters.settleSpeed || stepCount >= parameters.maxSteps {
            isSettled = true
        }
        return isSettled
    }

    @discardableResult
    public mutating func run() -> Int {
        let start = stepCount
        while !isSettled {
            step()
        }
        return stepCount - start
    }

    mutating func setPosition(_ position: SIMD2<Double>, at index: Int) {
        positions[index] = position
        isSettled = positions.count <= 1
    }

    private mutating func applyRepulsion(to forces: inout [SIMD2<Double>]) {
        let count = positions.count
        guard count > 1 else { return }

        for first in 0..<(count - 1) {
            for second in (first + 1)..<count {
                var delta = positions[second] - positions[first]
                var distanceSquared = squaredLength(delta)
                if distanceSquared < 1e-6 {
                    let angle = Double(first * 73 + second * 37)
                    delta = SIMD2(cos(angle), sin(angle))
                    distanceSquared = 1
                }
                let distance = distanceSquared.squareRoot()
                let push = (delta / distance) * (parameters.repulsionStrength / distanceSquared)
                forces[first] -= push
                forces[second] += push
            }
        }
    }

    private mutating func applySprings(to forces: inout [SIMD2<Double>]) {
        for (from, to) in edges {
            let delta = positions[to] - positions[from]
            let distance = squaredLength(delta).squareRoot()
            let direction = distance < 1e-3 ? SIMD2(1.0, 0.0) : delta / distance
            let pull = direction * (parameters.springStiffness * (distance - parameters.springLength))
            forces[from] += pull
            forces[to] -= pull
        }
    }

    private mutating func applyGravity(to forces: inout [SIMD2<Double>]) {
        for index in positions.indices {
            forces[index] -= positions[index] * parameters.gravityStrength
        }
    }

    private mutating func integrate(forces: [SIMD2<Double>]) -> Double {
        var maxSpeed = 0.0
        for index in positions.indices {
            velocities[index] =
                (velocities[index] + forces[index] * parameters.timestep)
                * parameters.damping
            positions[index] += velocities[index] * parameters.timestep
            maxSpeed = max(maxSpeed, squaredLength(velocities[index]).squareRoot())
        }
        return maxSpeed
    }

    private func squaredLength(_ vector: SIMD2<Double>) -> Double {
        vector.x * vector.x + vector.y * vector.y
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
