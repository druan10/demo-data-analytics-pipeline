{{ config(materialized='table') }}

WITH products AS (
    SELECT * FROM {{ ref('stg_az__products') }}
)

SELECT
    -- Link back to your dimension (Foreign Key)
    product_id,

    -- Quantitative attributes
    rating,
    rating_count,
    actual_price_inr,
    actual_price_usd,
    discounted_price_inr,
    discounted_price_usd,
    discount_percentage
FROM products