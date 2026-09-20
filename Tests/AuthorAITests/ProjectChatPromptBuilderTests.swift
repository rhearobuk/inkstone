import AuthorAI
import Testing

@Test func conversationTranscriptPreservesPriorTurnsForContextExtraction() {
    let messages = [
        ProjectChatMessage(role: .user, content: "Why did Mara leave the council?"),
        ProjectChatMessage(role: .assistant, content: "She discovered the council concealed the treaty."),
        ProjectChatMessage(role: .user, content: "How does that affect her motivation?")
    ]

    let recentMessages = ProjectChatPromptBuilder.recentMessages(messages, maximumBytes: 2_000)
    let transcript = ProjectChatPromptBuilder.conversationTranscript(recentMessages)

    #expect(transcript.contains("USER:\nWhy did Mara leave the council?"))
    #expect(transcript.contains("ASSISTANT:\nShe discovered the council concealed the treaty."))
    #expect(transcript.contains("USER:\nHow does that affect her motivation?"))
}

@Test func conversationTranscriptHonorsRecentMessageByteLimit() {
    let messages = [
        ProjectChatMessage(role: .user, content: String(repeating: "A", count: 20)),
        ProjectChatMessage(role: .assistant, content: String(repeating: "B", count: 20)),
        ProjectChatMessage(role: .user, content: "Follow up")
    ]

    let recentMessages = ProjectChatPromptBuilder.recentMessages(messages, maximumBytes: 30)

    #expect(recentMessages.map(\.content) == [String(repeating: "B", count: 20), "Follow up"])
}
