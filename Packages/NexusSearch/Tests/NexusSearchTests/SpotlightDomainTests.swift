import Foundation
import NexusCore
import Testing

@testable import NexusSearch

@Test func spotlightDomain_root_isStableBundleID() {
    #expect(SpotlightDomain.root == "com.kacperpietrzyk.Nexus")
}

@Test func spotlightDomain_subdomain_perKind_isUnique() {
    let kinds = ItemKind.allCases.map { SpotlightDomain.subdomain(for: $0) }
    #expect(Set(kinds).count == kinds.count)
}

@Test func spotlightDomain_subdomain_isPrefixedByRoot() {
    for kind in ItemKind.allCases {
        let sub = SpotlightDomain.subdomain(for: kind)
        #expect(sub.hasPrefix(SpotlightDomain.root + "."))
    }
}

@Test func spotlightDomain_uniqueIdentifier_combinesKindAndID() {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let identifier = SpotlightDomain.uniqueIdentifier(kind: .debug, id: id)
    #expect(identifier == "com.kacperpietrzyk.Nexus.debug:11111111-2222-3333-4444-555555555555")
}
