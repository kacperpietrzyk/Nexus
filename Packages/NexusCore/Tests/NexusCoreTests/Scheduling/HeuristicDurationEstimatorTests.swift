import Foundation
import Testing

@testable import NexusCore

@Suite("HeuristicDurationEstimator")
struct HeuristicDurationEstimatorTests {
    private func completed(
        title: String = "done task",
        projectID: UUID? = nil,
        tags: [String] = [],
        seconds: Int
    ) -> TaskItem {
        TaskItem(
            title: title,
            status: .done,
            tags: tags,
            projectID: projectID,
            estimatedDurationSeconds: seconds,
            durationSource: .explicit
        )
    }

    // MARK: - Explicit

    @Test("explicit duration wins at confidence 1.0")
    func explicitWins() {
        let estimator = HeuristicDurationEstimator()
        let task = TaskItem(
            title: "anything",
            estimatedDurationSeconds: 5400,
            durationSource: .explicit
        )
        let estimate = estimator.estimate(for: task, history: [])
        #expect(estimate.seconds == 5400)
        #expect(estimate.confidence == 1.0)
    }

    @Test("estimated-source duration is NOT treated as explicit")
    func estimatedSourceFallsThrough() {
        let estimator = HeuristicDurationEstimator()
        // durationSource == .estimated must not short-circuit; falls to fallback.
        let task = TaskItem(
            title: "untitled blob",
            estimatedDurationSeconds: 9999,
            durationSource: .estimated
        )
        let estimate = estimator.estimate(for: task, history: [])
        #expect(estimate.seconds == 30 * 60)
        #expect(estimate.confidence < 0.5)
    }

    // MARK: - History tiers

    @Test("project tier: median over completed explicit tasks in same project")
    func projectTierMedian() {
        let estimator = HeuristicDurationEstimator()
        let project = UUID()
        let history = [
            completed(projectID: project, seconds: 600),
            completed(projectID: project, seconds: 1200),
            completed(projectID: project, seconds: 1800),
        ]
        let task = TaskItem(title: "new", projectID: project)
        let estimate = estimator.estimate(for: task, history: history)
        #expect(estimate.seconds == 1200)
        #expect(estimate.confidence > 0.1)
        #expect(estimate.confidence < 1.0)
    }

    @Test("min samples not met → fall through to next tier / fallback")
    func minSamplesNotMet() {
        let estimator = HeuristicDurationEstimator(minimumSamples: 3)
        let project = UUID()
        // Only 2 in-project → below threshold; no tag/title overlap → fallback.
        let history = [
            completed(projectID: project, seconds: 600),
            completed(projectID: project, seconds: 1200),
        ]
        let task = TaskItem(title: "zzz unrelated", projectID: project)
        let estimate = estimator.estimate(for: task, history: history)
        #expect(estimate.seconds == 30 * 60)
    }

    @Test("tag tier used when project tier insufficient")
    func tagTier() {
        let estimator = HeuristicDurationEstimator()
        let history = [
            completed(tags: ["email"], seconds: 300),
            completed(tags: ["email"], seconds: 300),
            completed(tags: ["email"], seconds: 900),
        ]
        let task = TaskItem(title: "reply", tags: ["email"])
        let estimate = estimator.estimate(for: task, history: history)
        #expect(estimate.seconds == 300)
    }

    @Test("title-token tier used when project and tag tiers insufficient")
    func titleTokenTier() {
        let estimator = HeuristicDurationEstimator()
        let history = [
            completed(title: "standup meeting", seconds: 900),
            completed(title: "standup notes", seconds: 900),
            completed(title: "standup prep", seconds: 1800),
        ]
        let task = TaskItem(title: "standup tomorrow")
        let estimate = estimator.estimate(for: task, history: history)
        #expect(estimate.seconds == 900)
    }

    @Test("confidence grows with sample count")
    func confidenceGrows() {
        let estimator = HeuristicDurationEstimator()
        let project = UUID()
        let three = (0..<3).map { _ in completed(projectID: project, seconds: 600) }
        let twenty = (0..<20).map { _ in completed(projectID: project, seconds: 600) }
        let task = TaskItem(title: "x", projectID: project)
        let low = estimator.estimate(for: task, history: three).confidence
        let high = estimator.estimate(for: task, history: twenty).confidence
        #expect(high > low)
        #expect(high < 1.0)
    }

    // MARK: - Corpus hygiene

    @Test("non-explicit and open tasks are excluded from the corpus")
    func corpusExcludesNonExplicitAndOpen() {
        let estimator = HeuristicDurationEstimator()
        let project = UUID()
        let history = [
            // open → excluded
            TaskItem(title: "a", status: .open, projectID: project, estimatedDurationSeconds: 600, durationSource: .explicit),
            // estimated source → excluded
            TaskItem(title: "b", status: .done, projectID: project, estimatedDurationSeconds: 600, durationSource: .estimated),
            // nil duration → excluded
            TaskItem(title: "c", status: .done, projectID: project, durationSource: .explicit),
        ]
        let task = TaskItem(title: "zzz", projectID: project)
        // None usable → fallback default.
        let estimate = estimator.estimate(for: task, history: history)
        #expect(estimate.seconds == 30 * 60)
    }

    // MARK: - Fallback keywords

    @Test("fallback keyword heuristic: call/review/write")
    func fallbackKeywords() {
        let estimator = HeuristicDurationEstimator()
        #expect(estimator.estimate(for: TaskItem(title: "Call Alice"), history: []).seconds == 30 * 60)
        #expect(estimator.estimate(for: TaskItem(title: "Review PR"), history: []).seconds == 45 * 60)
        #expect(estimator.estimate(for: TaskItem(title: "Write blog draft"), history: []).seconds == 60 * 60)
        #expect(estimator.estimate(for: TaskItem(title: "Buy milk"), history: []).seconds == 30 * 60)
    }

    @Test("explicit override feeds the corpus for the next estimate")
    func overrideFeedsCorpus() {
        let estimator = HeuristicDurationEstimator()
        let project = UUID()
        // User overrode three sibling tasks to 25m; they become corpus.
        let corpus = (0..<3).map { i in
            TaskItem(
                title: "sibling \(i)",
                status: .done,
                projectID: project,
                estimatedDurationSeconds: 1500,
                durationSource: .explicit
            )
        }
        let task = TaskItem(title: "new sibling", projectID: project)
        let estimate = estimator.estimate(for: task, history: corpus)
        #expect(estimate.seconds == 1500)
    }
}
