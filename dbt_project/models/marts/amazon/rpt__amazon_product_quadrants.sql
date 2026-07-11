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
        
        -- Window functions to calculate category-level benchmarks.
        AVG(f.rating) OVER(PARTITION BY d.primary_category) AS avg_rating_by_category,
        AVG(f.rating_count) OVER(PARTITION BY d.primary_category) AS avg_rating_count_by_category,
        AVG(f.actual_price_usd) OVER(PARTITION BY d.primary_category) AS avg_price_by_category,
        AVG(f.discounted_price_usd) OVER(PARTITION BY d.primary_category) AS avg_discounted_price_by_category
    FROM {{ ref('fct__amazon_product_metrics') }} f
    JOIN {{ ref('dim__amazon_products') }} d ON f.product_id = d.product_id
),

-- Product Price and Ratings Categorization
segmented AS (
    SELECT
        *,
        -- 1. Compare products within a category, based on its ratings/rating count vs average by category
        -- Since we used window functions by category to generate the averages, we are comparing based on it's own category
        CASE 
            WHEN rating >= avg_rating_by_category AND rating_count >= avg_rating_count_by_category THEN 'High R / High Qty'
            WHEN rating >= avg_rating_by_category AND rating_count < avg_rating_count_by_category THEN 'High R / Low Qty'
            WHEN rating < avg_rating_by_category AND rating_count >= avg_rating_count_by_category THEN 'Low R / High Qty'
            ELSE 'Low R / Low Qty'
        END AS category_product_segment,

        -- 2. Flag Products as High Priced items, or deeply discounted products, compared to category
        CASE 
            -- Discounted price is above average of regular price
            WHEN discounted_price > avg_price_by_category THEN 'Premium Price Product'
            -- Discounted price is below the average discount_price
            WHEN discounted_price <= avg_discounted_price_by_category THEN 'Deep Discount Product'
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
    avg_rating_by_category,
    avg_rating_count_by_category,
    avg_price_by_category,
    avg_discounted_price_by_category,
    category_product_segment,
    pricing_segment,
    
    -- 3. Advanced Risk & Opportunity Flagging (Combines all variables)
    CASE 
        -- Great ratings, high volume, and currently priced below the normal category discount floor
        WHEN discounted_price <= avg_discounted_price_by_category 
             AND rating >= avg_rating_by_category 
             AND rating_count >= avg_rating_count_by_category 
        THEN 'Prime Arbitrage Snipe'

        -- Similar to Prime Arbitrage Snipes, just low volume. Good to review, as they may have potential, but not yet received traction.
        WHEN discounted_price <= avg_discounted_price_by_category 
             AND rating >= avg_rating_by_category 
             AND rating_count < avg_rating_count_by_category 
        THEN 'Potential Hidden Gem'

        -- High volume, bad ratings, but listed at a premium price point
        WHEN discounted_price > avg_price_by_category 
             AND rating < avg_rating_by_category 
             AND rating_count > avg_rating_count_by_category 
        THEN 'High-Churn Trap'
        
        -- Low reviews and deep price cuts usually mean dead stock
        WHEN discounted_price <= avg_discounted_price_by_category 
             AND rating_count < avg_rating_count_by_category 
        THEN 'Liquidating / Low Demand'
        
        ELSE 'Average Product'
    END AS business_action_flag,
    
    -- 4. Expanded Delta Metrics for BI Tooltips/Dashboards
    ROUND(rating - avg_rating_by_category, 2) AS rating_delta,
    ROUND(((rating_count - avg_rating_count_by_category) / NULLIF(avg_rating_count_by_category, 0)) * 100, 1) AS volume_pct_delta,
    
    -- Captures individual item discount percentage vs. the category standard discount
    ROUND(((actual_price - discounted_price) / NULLIF(actual_price, 0)) * 100, 1) AS item_discount_pct,
    ROUND(((avg_price_by_category - avg_discounted_price_by_category) / NULLIF(avg_price_by_category, 0)) * 100, 1) AS category_avg_discount_pct
FROM segmented