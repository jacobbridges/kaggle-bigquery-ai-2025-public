/**
 *
 * 01 - Proof-of-concept with real data files
 * ---
 *
 * This query will use the latest document and the first
 * ephemera uploaded after the document. These files are
 * pulled from GCS via Cloud Storage object tables in
 * BigQuery.
 *
 * - Documents: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/01-poc/documents/
 * - Ephemera: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/01-poc/ephemera/
 *
 */

WITH
  annotated_doc AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS content,
      (
        SELECT CAST(value AS INT64)
        FROM UNNEST(metadata)
        WHERE name = 'timestamp'
        LIMIT 1
      ) AS epoch
    FROM
      `tensile-reducer-471101-f0.public.01_poc_documents`
  ),
  annotated_ephemera AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS content,
      (
        SELECT CAST(value AS INT64)
        FROM UNNEST(metadata)
        WHERE name = 'timestamp'
        LIMIT 1
      ) AS epoch
    FROM
      `tensile-reducer-471101-f0.public.01_poc_ephemera`
  ),
  latest_document AS (
    SELECT
      content,
      epoch
    FROM annotated_doc
    ORDER BY epoch DESC
    LIMIT 1
  ),
  first_ephemera_since_latest_document AS (
    SELECT
      annotated_ephemera.content,
      annotated_ephemera.epoch
    FROM
      annotated_ephemera,
      latest_document
    WHERE
      annotated_ephemera.epoch > latest_document.epoch
    ORDER BY
      epoch ASC
    LIMIT 1
  ),
  prompt_construction AS (
    SELECT
      CONCAT(
        """You are an expert AI assistant tasked with updating technical project documentation.
You will be provided with a specification and a conversation transcript.
Create a new version of the specification that captures any decisions made in the conversation.
Return only the updated specification, with no commentary.

Original Specification:

```md
""",
        latest_document.content,
"""
```

Conversation:

```
""",
        first_ephemera_since_latest_document.content,
"""
```

Updated Specification:
"""
      ) AS prompt
      FROM latest_document, first_ephemera_since_latest_document
  )
SELECT
  AI.GENERATE(
    prompt,
    connection_id => 'us.test_connection',  -- Change this!
    endpoint => 'gemini-2.0-flash-lite',
    output_schema => 'result STRING',
    model_params => JSON '{"generation_config":{"seed": 12345}}'
  ).result

FROM prompt_construction;
