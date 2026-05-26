import Testing

@testable import NexusSync

@Test func setMerge_unionsTwoSets() {
    let result = SetMerge.union(local: ["a", "b"], remote: ["b", "c"])
    #expect(result == ["a", "b", "c"])
}

@Test func setMerge_preservesOrderOfFirstAppearance() {
    let result = SetMerge.union(local: ["c", "a"], remote: ["b", "a", "d"])
    #expect(result == ["c", "a", "b", "d"])
}

@Test func setMerge_handlesEmptyInputs() {
    #expect(SetMerge.union(local: [], remote: ["a"]) == ["a"])
    #expect(SetMerge.union(local: ["a"], remote: []) == ["a"])
    #expect(SetMerge.union(local: [String](), remote: [String]()) == [])
}

@Test func setMerge_dedupesWithinSingleSide() {
    let result = SetMerge.union(local: ["a", "a", "b"], remote: ["b"])
    #expect(result == ["a", "b"])
}
