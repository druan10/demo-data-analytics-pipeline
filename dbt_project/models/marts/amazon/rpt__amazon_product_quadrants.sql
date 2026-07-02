{{ config(materialized='table') }}

-- Main Data & Averages
WITH metrics AS (
    SELECT
        f.product_id,
        d.product_name,
        d.primary_category,
        d.sub_category,
        f.rating,
        f.rating_count,
        f.actual_price_usd AS actual_price,
        f.discounted_price_usd AS discounted_price,
        
        -- Window functions to calculate category-level benchmarks
        AVG(f.rating) OVER(PARTITION BY d.primary_category) AS avg_rating,
        AVG(f.rating_count) OVER(PARTITION BY d.primary_category) AS avg_rating_count,
        AVG(f.actual_price_usd) OVER(PARTITION BY d.primary_category) AS avg_price,
        AVG(f.discounted_price_usd) OVER(PARTITION BY d.primary_category) AS avg_discounted_price
    FROM {{ ref('fct__amazon_product_metrics') }} f
    JOIN {{ ref('dim__amazon_products') }} d ON f.product_id = d.product_id
),

-- Product Price and 
segmented AS (
    SELECT
        *,
        -- 1. Quadrant allocation (Rating vs Volume)
        CASE 
            WHEN rating >= avg_rating AND rating_count >= avg_rating_count THEN 'High R / High Qty'
            WHEN rating >= avg_rating AND rating_count < avg_rating_count THEN 'High R / Low Qty'
            WHEN rating < avg_rating AND rating_count >= avg_rating_count THEN 'Low R / High Qty'
            ELSE 'Low R / Low Qty'
        END AS category_product_segment,

        -- 2. New Pricing Strategy Segment (Utilizing your pricing variables)
        -- Determines if a product is premium, baseline market value, or heavily discounted
        CASE 
            -- Discounted price is above average of regular price
            WHEN discounted_price > avg_price THEN 'Premium Price Product'
            -- Discounted price is below the average discount_price
            WHEN discounted_price <= avg_discounted_price THEN 'Deep Discount Product'
            ELSE 'Average Market Value'
        END AS pricing_segment
    FROM metrics
)

SELECT
    product_id,
    product_name,
    primary_category,
    sub_category,
    rating,
    rating_count,
    actual_price,
    discounted_price,
    avg_rating,
    avg_rating_count,
    avg_price,
    avg_discounted_price,
    category_product_segment,
    pricing_segment,
    
    -- 3. Advanced Risk & Opportunity Flagging (Combines all variables)
    CASE 
        -- High volume, bad ratings, but listed at a premium price point
        WHEN discounted_price > avg_price 
             AND rating < avg_rating 
             AND rating_count > avg_rating_count 
        THEN 'High-Churn Trap'
        
        -- Great ratings, high volume, but currently priced below the normal category discount floor
        WHEN discounted_price <= avg_discounted_price 
             AND rating >= avg_rating 
             AND rating_count >= avg_rating_count 
        THEN 'Prime Arbitrage Snipe'
        
        -- Low reviews and deep price cuts usually mean dead stock
        WHEN discounted_price <= avg_discounted_price 
             AND rating_count < avg_rating_count 
        THEN 'Liquidating / Low Demand'
        
        ELSE 'Healthy Baseline'
    END AS business_action_flag,
    
    -- 4. Expanded Delta Metrics for BI Tooltips/Dashboards
    ROUND(rating - avg_rating, 2) AS rating_delta,
    ROUND(((rating_count - avg_rating_count) / NULLIF(avg_rating_count, 0)) * 100, 1) AS volume_pct_delta,
    
    -- Captures individual item discount percentage vs. the category standard discount
    ROUND(((actual_price - discounted_price) / NULLIF(actual_price, 0)) * 100, 1) AS item_discount_pct,
    ROUND(((avg_price - avg_discounted_price) / NULLIF(avg_price, 0)) * 100, 1) AS category_avg_discount_pct
FROM segmented