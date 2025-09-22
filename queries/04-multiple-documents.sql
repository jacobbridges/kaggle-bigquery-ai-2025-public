/**
 *
 * 04 - Showcase Multiple Document Types
 * ---
 *
 * The Cloud Storage object tables used in this script
 * are mirrored in these Github directories:
 *
 * - 04_documents: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/04-multiple-documents/documents/
 * - 04_ephemera: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/04-multiple-documents/ephemera/
 * - 04_prompts: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/04-multiple-documents/prompts/
 *
 * The documents now have a metadata key "document_type"
 * which describes the type of content in the file. Two
 * document types are available in the sample data:
 *
 * 1. project_spec  (project specification)
 * 2. documentation (single page of technical documentation)
 *
 * This script also pulls any ephemera which have a
 * timestamp after the chosen document, just like in
 * 03-multiple-ephemera-types.sql. However, now the
 * ephemera are filtered down to only those where a
 * prompt is available for the document_type +
 * ephemera_type combo.
 *
 * Each ephemera has a metadata key "ephemera_type"
 * which describes the type of content in the file.
 * Four ephemera types are used in this example:
 *
 * 1. slack_json     (Slack conversation history)
 * 2. zoom_vtt       (Zoom meeting transcript)
 * 3. change_request (system change contract)
 * 4. pr_summary     (Github pr summary)
 *
 * This example focuses on generating a new version
 * of `documentation`. In production, this query
 * would be parameterized.
 *
 */

-- Define variables for the script
DECLARE final_document STRUCT<content STRING, epoch INT64, document_type STRING>;
DECLARE current_ephemera STRING;
DECLARE chosen_document_type STRING DEFAULT 'documentation';

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
      ) AS epoch,
      (
        SELECT value
        FROM UNNEST(metadata)
        WHERE name = 'document_type'
        LIMIT 1
      ) AS document_type
    FROM
      `tensile-reducer-471101-f0.public.04_documents`
  )
  SELECT
    STRUCT(content, epoch, document_type)
  FROM annotated_doc
  WHERE document_type = chosen_document_type
  ORDER BY epoch DESC
  LIMIT 1
);

-- Loop through ephemera in chronological order, finding
-- the correct prompt template for the ephemera type and
-- rendering the prompt.
FOR ephemera IN (
  WITH annotated_ephemera AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS content,
      (
        SELECT CAST(value AS INT64)
        FROM UNNEST(metadata)
        WHERE name = 'timestamp'
        LIMIT 1
      ) AS epoch,
      (
        SELECT value
        FROM UNNEST(metadata)
        WHERE name = 'ephemera_type'
        LIMIT 1
      ) AS ephemera_type
    FROM
      `tensile-reducer-471101-f0.public.04_ephemera`
  ),
  annotated_prompts AS (
    SELECT
      SAFE_CONVERT_BYTES_TO_STRING(data) AS template,
      (
        SELECT value
        FROM UNNEST(metadata)
        WHERE name = 'document_type'
        LIMIT 1
      ) AS document_type,
      (
        SELECT value
        FROM UNNEST(metadata)
        WHERE name = 'ephemera_type'
        LIMIT 1
      ) AS ephemera_type
    FROM
      `tensile-reducer-471101-f0.public.04_prompts`
  )
  SELECT DISTINCT
    annotated_ephemera.content,
    annotated_ephemera.epoch,
    annotated_ephemera.ephemera_type,
    annotated_prompts.template AS prompt_template
  FROM
    annotated_ephemera
  LEFT JOIN
    annotated_prompts ON (
      annotated_prompts.document_type = final_document.document_type
      AND annotated_prompts.ephemera_type = annotated_ephemera.ephemera_type
    )
  WHERE
    annotated_ephemera.epoch > final_document.epoch
    AND annotated_prompts.template IS NOT NULL
  ORDER BY
    annotated_ephemera.epoch ASC
)
DO
  SELECT ephemera;
  SET current_ephemera = ephemera.content;
  SET final_document = (
    SELECT
      STRUCT(
        AI.GENERATE(
          REPLACE(
            REPLACE(ephemera.prompt_template, "{EPHEMERA}", current_ephemera),
            "{DOCUMENT}",
            final_document.content
          ),
          connection_id => "us.test_connection",  -- Change this!
          endpoint => 'gemini-2.0-flash-lite',
          output_schema => 'output STRING',
          model_params => JSON '{"generation_config":{"seed": 12345}}'
        ).output AS content,
        ephemera.epoch AS epoch,
        final_document.document_type AS document_type
      )
  );
END FOR;

SELECT final_document.content;
