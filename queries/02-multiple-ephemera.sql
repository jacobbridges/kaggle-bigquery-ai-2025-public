/**
 *
 * 02 - Showcase Multiple Ephemera
 * ---
 *
 * When updating a document from multiple ephemera, we
 * should consider the following:
 *
 * 1. Ephemera should be in chronological order. A team
 *    conversation from Jan 4th might clarify or nullify
 *    decisions which were made from a conversation on
 *    Jan 1st.
 * 2. The original document should be used in the prompt
 *    when processing the first ephemera (row 1).
 * 3. The document version generated from row 1 should be
 *    used in the prompt when processing row 2.
 * 4. Loop until the final document version is returned.
 *
 * This type of processing requires a loop. We use the
 * GoogleSQL procedural language's FOR...IN loop.
 *
 * Just like in 01-poc.sql, pull the latest document and
 * the latest ephemera uploaded after the document. The
 * object tables for this example are loaded with the
 * following data files:
 *
 * - Documents: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/02-multiple-ephemera/documents/
 * - Ephemera: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/02-multiple-ephemera/ephemera/
 *
 */

-- Set the prompt template here, makes the query a bit more readable.
DECLARE prompt_template STRING DEFAULT """You are an expert AI assistant tasked with updating technical project documentation.

Your goal is to update the provided **Project Specification Document** based on the decisions and new requirements identified in the **Slack Conversation Export**.

The updated document will be reviewed by a human. Think about the diffs as you are making changes.

Follow these instructions carefully:

1. **Analyze the Conversation:** Read through the Slack conversation to capture decisions, agreements, and new requirements. Capture technical specifications and functional requirements.
2. **Prioritize Capture:** Prioritize capturing decisions and requirements over complete consensus. Capture any future or deferred features and requirements.
3. **Locate the Relevant Section:** For each identified change to the spec, find the most appropriate place in the original project specification to add or modify it.
4. **Perform Surgical Edits:** Try to preserve the original wording, formatting, and structure. Reword if it makes things clearer.
5. **Output the Final Document:** Your final output should be the *complete*, updated project specification in Markdown format. Do not include any of your own commentary, summary, or explanation of your changes. Only output the raw Markdown document.

-----

### **INPUTS**

#### **1. Slack Conversation Export (JSON)**

```json
{EPHEMERA}
```

#### **2. Original Project Specification (Markdown)**

```markdown
{DOCUMENT}
```
-----

### **OUTPUT**

#### Updated Project Specification (Markdown)
""";

-- Define variables for the script
DECLARE final_document STRUCT<content STRING, epoch INT64>;
DECLARE current_ephemera STRING;

-- Starting value for document is the latest GCS file
SET final_document = (
  WITH annotated_doc AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS content,
      (
        SELECT CAST(value AS INT64)
        FROM UNNEST(metadata)
        WHERE name = 'timestamp'
        LIMIT 1
      ) AS epoch
    FROM
      `tensile-reducer-471101-f0.public.02_documents`
  )
  SELECT
    STRUCT(content, epoch)
  FROM annotated_doc
  ORDER BY epoch DESC
  LIMIT 1
);

-- Loop through ephemera in chronological order, running the prompt.
FOR ephemera IN (
  WITH annotated_ephemera AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS content,
      (
        SELECT CAST(value AS INT64)
        FROM UNNEST(metadata)
        WHERE name = 'timestamp'
        LIMIT 1
      ) AS epoch
    FROM
      `tensile-reducer-471101-f0.public.02_ephemera`
  )
  SELECT
    content,
    epoch
  FROM
    annotated_ephemera
  WHERE
    epoch > final_document.epoch
  ORDER BY
    epoch ASC
)
DO
  SET current_ephemera = ephemera.content;
  SET final_document = (
    SELECT
      STRUCT(
        AI.GENERATE(
          REPLACE(
            REPLACE(prompt_template, "{EPHEMERA}", current_ephemera),
            "{DOCUMENT}",
            final_document.content
          ),
          connection_id => 'us.test_connection',  -- Change this!
          endpoint => 'gemini-2.0-flash-lite',
          output_schema => 'updated_project_specification STRING',
          model_params => JSON '{"generation_config":{"seed": 12345}}'
        ).updated_project_specification AS content,
        ephemera.epoch AS epoch
      )
  );
END FOR;

SELECT final_document.content;
