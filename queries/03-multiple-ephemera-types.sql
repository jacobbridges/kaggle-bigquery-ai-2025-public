/**
 *
 * 03 - Showcase Multiple Ephemera Types
 * ---
 *
 * The Cloud Storage object tables used in this script
 * are mirrored in these Github directories:
 *
 * - 03_documents: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/03-multiple-ephemera-types/documents/
 * - 03_ephemera: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/03-multiple-ephemera-types/ephemera/
 * - 03_prompts: https://github.com/jacobbridges/kaggle-bigquery-ai-2025-public/blob/main/data/03-multiple-ephemera-types/prompts/
 *
 * Each ephemera has a metadata key "ephemera_type"
 * which describes the type of content in the file.
 * Three ephemera types are used in this example:
 *
 * 1. slack_json     (Slack conversation history)
 * 2. zoom_vtt       (Zoom meeting transcript)
 * 3. change_request (system change contract)
 *
 * This script introduces a new table for storing prompts,
 * catered to each ephemera type. While generating an
 * updated version of the document, using the same loop
 * as in 02-multiple-ephemera.sql, the prompt is pulled
 * from the new table.
 *
 */

-- Define variables for the script
DECLARE final_document STRUCT<content STRING, epoch INT64>;
DECLARE current_ephemera STRING;
DECLARE prompt_template STRING;

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
      `tensile-reducer-471101-f0.public.03_documents`
  )
  SELECT
    STRUCT(content, epoch)
  FROM annotated_doc
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
      `tensile-reducer-471101-f0.public.03_ephemera`
  )
  SELECT
    content,
    epoch,
    ephemera_type
  FROM
    annotated_ephemera
  WHERE
    epoch > final_document.epoch
  ORDER BY
    epoch ASC
)
DO
  SELECT ephemera.ephemera_type;
  SET current_ephemera = ephemera.content;
  SET prompt_template = (
    WITH annotated_prompts AS (
      SELECT
        SAFE_CONVERT_BYTES_TO_STRING(data) AS template,
        (
          SELECT value
          FROM UNNEST(metadata)
          WHERE name = 'ephemera_type'
          LIMIT 1
        ) AS ephemera_type
      FROM
        `tensile-reducer-471101-f0.public.03_prompts`
    )
    SELECT annotated_prompts.template
    FROM annotated_prompts
    WHERE annotated_prompts.ephemera_type = ephemera.ephemera_type
    LIMIT 1
  );
  SET final_document = (
    SELECT
      STRUCT(
        AI.GENERATE(
          REPLACE(
            REPLACE(prompt_template, "{EPHEMERA}", current_ephemera),
            "{DOCUMENT}",
            final_document.content
          ),
          connection_id => "us.test_connection",  -- Change this!
          endpoint => 'gemini-2.0-flash-lite',
          output_schema => 'updated_project_specification STRING',
          model_params => JSON '{"generation_config":{"seed": 12345}}'
        ).updated_project_specification AS content,
        ephemera.epoch AS epoch
      )
  );
END FOR;

SELECT final_document.content;
