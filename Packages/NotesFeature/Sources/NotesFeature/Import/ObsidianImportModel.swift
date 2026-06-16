import Foundation
import NexusCore
import Observation

/// Owns the Obsidian import run and its presentation state OUTSIDE the SwiftUI
/// view tree, so a store-change rebuild of the Settings host can't tear down the
/// sheet or cancel the run mid-flight. The work executes on a `Task` held by the
/// model (not the view's `.task`), and a shared instance survives view-identity
/// churn — the sheet observes it and re-binds to the same state on rebuild.
@MainActor
@Observable
public final class ObsidianImportModel {
    public enum Phase: Sendable, Equatable {
        case idle, scanning, previewed, importing, done, failed
    }

    public private(set) var phase: Phase = .idle
    public private(set) var toCreate = 0
    public private(set) var toSkip = 0
    public private(set) var created = 0
    public private(set) var skipped = 0
    public private(set) var failed = 0
    public private(set) var progress: Double = 0
    public private(set) var errorText: String?
    public private(set) var errors: [String] = []

    /// Drives sheet presentation from the churn-resistant model rather than
    /// transient view `@State` — set to a folder to present, nil to dismiss.
    public var activeVault: VaultRoot?

    private var plan: ObsidianImportPlan?
    private var runTask: Task<Void, Never>?

    /// Shared instance: stable across Settings-host rebuilds.
    public static let shared = ObsidianImportModel()
    public init() {}

    public struct VaultRoot: Identifiable, Equatable, Sendable {
        public let url: URL
        public init(url: URL) { self.url = url }
        public var id: String { url.path }
    }

    // MARK: - View entry points (model owns the Task → view teardown can't cancel it)

    public func present(vaultRoot: URL) {
        activeVault = VaultRoot(url: vaultRoot)
    }

    public func dismiss() {
        activeVault = nil
        if phase != .importing { reset() }
    }

    public func scan(vaultRoot: URL, repository: NoteRepository) {
        runTask?.cancel()
        runTask = Task { await performScan(vaultRoot: vaultRoot, repository: repository) }
    }

    public func startImport(vaultRoot: URL, repository: NoteRepository) {
        runTask = Task { await performImport(vaultRoot: vaultRoot, repository: repository) }
    }

    // MARK: - Work (async, directly unit-testable)

    func performScan(vaultRoot: URL, repository: NoteRepository) async {
        phase = .scanning
        errorText = nil
        errors = []
        created = 0
        skipped = 0
        failed = 0
        progress = 0
        plan = nil
        do {
            let discovered = try ObsidianVaultImporter.discover(vaultRoot: vaultRoot)
            let existing = try ObsidianVaultImporter.existingKeys(in: repository)
            let computed = ObsidianVaultImporter().plan(discovered: discovered, existing: existing)
            plan = computed
            toCreate = computed.toCreate.count
            toSkip = computed.toSkip.count
            phase = .previewed
        } catch {
            errorText = error.localizedDescription
            phase = .failed
        }
    }

    func performImport(vaultRoot: URL, repository: NoteRepository) async {
        guard let plan, phase == .previewed else { return }
        phase = .importing
        progress = 0
        do {
            let result = try await ObsidianVaultImporter().execute(
                plan: plan,
                repo: repository,
                vaultRoot: vaultRoot,
                progress: { [weak self] value in self?.progress = value }
            )
            created = result.created
            skipped = result.skipped
            failed = result.failed
            errors = result.errors
            phase = .done
        } catch {
            errorText = error.localizedDescription
            phase = .failed
        }
    }

    private func reset() {
        phase = .idle
        toCreate = 0
        toSkip = 0
        created = 0
        skipped = 0
        failed = 0
        progress = 0
        errorText = nil
        errors = []
        plan = nil
    }
}
