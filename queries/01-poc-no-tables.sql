/**
 *
 * Very simple proof-of-concept.
 *
 * 1. One document: a project specification.
 * 2. One ephemera: a conversation where a decision was made.
 *
 */

SELECT
  AI.GENERATE(
-- Avoid polluting prompt with indentation
"""
You are an expert AI assistant tasked with updating technical project documentation.
You will be provided with a specification and a conversation transcript.
Create a new version of the specification that captures any decisions made in the conversation.
Return only the updated specification, with no commentary.

Original Specification:

```md
A basic web-based todo application that allows users to create, edit, and track personal tasks.
```

Conversation:

```
[11:15 AM] Jacob
Hey Illya! What fields should we track for each task?

[11:18 AM] Illya
Hmm... maybe title, description, due date, priority?

[11:19 AM] Jacob
Sounds good. Let's also track deleted status, for soft deletes.
```

Updated Specification:
""",
    connection_id => 'us.test_connection',  -- Change this!
    endpoint => 'gemini-2.0-flash-lite',
    output_schema => 'result STRING',
    model_params => JSON '{"generation_config":{"seed": 12345}}'
  ).result