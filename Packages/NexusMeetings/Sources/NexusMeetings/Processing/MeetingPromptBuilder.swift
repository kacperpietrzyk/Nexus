import Foundation

public enum MeetingPromptBuilder {
    public static func summaryPrompt(
        transcript: String,
        title: String,
        durationSec: Int,
        customTemplate: String?,
        screenContext: String? = nil
    ) -> String {
        if let customTemplate, customTemplate.isEmpty == false {
            return
                customTemplate
                .replacingOccurrences(of: "{{title}}", with: title)
                .replacingOccurrences(of: "{{durationMinutes}}", with: "\(durationSec / 60)")
                .replacingOccurrences(of: "{{transcript}}", with: transcript)
                .replacingOccurrences(of: "{{screenContext}}", with: screenContext ?? "")
        }

        return """
            You are an assistant summarizing a meeting transcript.

            Meeting title: \(title)
            Duration: \(durationSec / 60) minutes

            Produce a structured Markdown summary with these sections:

            ## TL;DR
            2-3 sentence summary of the meeting.

            ## Key topics
            - bullet per topic discussed

            ## Decisions made
            - bullet per concrete decision

            Do NOT include an "Action items" section -- those are extracted separately.
            \(screenContextBlock(screenContext))Transcript:
            \(transcript)
            """
    }

    public static func actionItemsPrompt(
        transcript: String,
        summary: String,
        screenContext: String? = nil
    ) -> String {
        """
        Extract action items from this meeting transcript and summary. Return ONLY a JSON array
        of objects with this schema:
        [
          {
            "text": "<concrete action>",
            "assigneeHint": "Me" | "<speaker label or freeform name>" | null,
            "dueHint": "<natural language due, e.g. 'next Friday'>" | null,
            "confidence": 0.0-1.0
          }
        ]
        Skip statements that are not concrete action items (e.g. "we'll discuss later").
        \(screenContextBlock(screenContext))
        Summary:
        \(summary)

        Transcript:
        \(transcript)
        """
    }

    /// Renders an optional on-screen-context block for prompt enrichment. Returns
    /// an empty string when there is no screen context, so a prompt built without
    /// screen OCR is byte-identical to the pre-feature output.
    private static func screenContextBlock(_ screenContext: String?) -> String {
        guard let screenContext, screenContext.isEmpty == false else { return "" }
        return """

            On-screen context captured during the meeting (OCR of shared windows; may be noisy):
            \(screenContext)

            """
    }
}
