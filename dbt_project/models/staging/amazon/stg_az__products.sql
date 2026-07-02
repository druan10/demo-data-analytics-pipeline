{{ config(materialized='view') }}
-- Silver Layer: Staging models clean and cast raw data.
-- Using the dbt source function instead of hardcoded paths allows dbt 
-- and Dagster to manage dependencies and file locations dynamically.
-- models/silver/stg_az__products.sql
-- This ends up as silver

-- to compile directly docker compose run dagster_platform dbt run --select stg_az__products --project-dir dbt_project --profiles-dir dbt_project

WITH source AS (
    SELECT * FROM {{ source('amazon_ecommerce', 'raw_az_data') }}
),

cleaned AS (
    SELECT
        product_id,
        product_name,

        -- 1. Split category string into a DuckDB array: ['Computers&Accessories', 'Accessories&Peripherals', ...]
        string_to_array(category, '|') AS category_array,

        -- DuckDB specific clean: strip out exactly '₹' and ',' then cast safely
        TRY_CAST(REGEXP_REPLACE(actual_price, '[₹,]', '', 'g') AS DECIMAL(10,2)) AS actual_price,
        TRY_CAST(REGEXP_REPLACE(discounted_price, '[₹,]', '', 'g') AS DECIMAL(10,2)) AS discounted_price,
        
        -- Remove % sign and divide by 100 to convert to decimal value
        TRY_CAST(REGEXP_REPLACE(discount_percentage, '%', '', 'g') AS DECIMAL(5,2)) / 100.0 AS discount_percentage,
        
        -- Set rating to 0 if missing
        COALESCE(TRY_CAST(rating AS DECIMAL(10,2)), 0) AS rating,
        
        -- Remove commas and set to 0 if ratings is null
        COALESCE(TRY_CAST(REGEXP_REPLACE(rating_count, ',', '', 'g') AS INTEGER), 0) AS rating_count,
        
    -- Use a window function to deduplicate by product_id, keeping the version of the product with the highest number of ratings
    FROM source
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY rating_count DESC) = 1
)

SELECT 
    product_id,
    product_name,
    COALESCE(category_array[1], 'Uncategorized') AS primary_category,
    COALESCE(category_array[2], 'None') AS sub_category,
    actual_price as actual_price_inr,
    (actual_price * .01) as actual_price_usd,
    discounted_price as discounted_price_inr,
    (discounted_price * .01) as discounted_price_usd,
    discount_percentage,
    rating,
    rating_count,
FROM cleaned
