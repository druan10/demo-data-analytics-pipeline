{{ config(materialized='table') }}

WITH products AS (
    SELECT * FROM {{ ref('stg_az__products') }}
)

SELECT
    -- Unique identifier
    product_id,
    product_name,
    primary_category,
    sub_category,
FROM products