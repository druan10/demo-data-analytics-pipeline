# Amazon Product Opportunity Analysis

This dashboard categorizes products for review, to help make decisions for reselling on Amazon. Original source data includes asins, product name, price and discounted prices (converted from Indian Rupees to USD), as well as rating_count + average rating per asin. This dataset lacks actual sales numbers and individual sales lines so based assumptions on listing data themselves.

Products are categorized by Business Action Flags, which suggest a potential action based on available data.

Business Action Flags:
    - Prime Arbitrage Snipe - Products with higher than Average Ratings and Rating Count by category, higher than average volume by category, and currently priced below the average category discount floor
    - Potential Hidden Gem - Similar to Prime Arbitrage Snipe, only that it has less than average Rating Count by Category
    - High-Churn Trap - Products with higher price points, but lower ratings based on above average rating count. Items that high change of returns/refunds.
    - Liquidating / Low Demand - Products with low rating count and large discounts, pointing to items that sellers are trying to liquidate but aren't moving much.

```sql total_metrics
-- Overall Metrics
SELECT
    -- High volume, bad ratings, but listed at a premium price point
    SUM(CASE WHEN business_action_flag = 'High-Churn Trap' THEN 1 ELSE 0 END) AS total_risky_products,
    -- Great ratings, high volume, but currently priced below the normal category discount floor
    SUM(CASE WHEN business_action_flag = 'Prime Arbitrage Snipe' THEN 1 ELSE 0 END) AS arbitrage_snipes,
    -- Great ratings, low review volume 
    SUM(CASE WHEN business_action_flag = 'Potential Hidden Gem' THEN 1 ELSE 0 END) AS potential_gems,
    -- Low reviews and deep price cuts usually mean dead stock
    SUM(CASE WHEN business_action_flag = 'Liquidating / Low Demand' THEN 1 ELSE 0 END) AS liquidating_products

FROM data_warehouse.product_quadrants
```

---

# Global Product Overview

<BigValue
    data={total_metrics} 
    value=arbitrage_snipes 
    title="Prime Arbitrage Snipes"
    subtitle="High Demand + Deep Price Cut"
/>

<BigValue 
    data={total_metrics} 
    value=potential_gems 
    title="Hidden Gems"
    subtitle="High Rating / Lower Volume"
/>

<BigValue
    data={total_metrics} 
    value=total_risky_products 
    title="Risky products"
    subtitle="High Demand + Deep Price Cut"
/>

<BigValue 
    data={total_metrics} 
    value=liquidating_products 
    title="Liquidating/Low Volume Products"
    subtitle="High Discounts and below average rating"
/>

```sql action_flags_by_category

-- Static queue to show how products are doing by category
SELECT 
    primary_category,
    business_action_flag,
    COUNT(*) AS product_count,
    -- Window function to calculate total flags per category for perfect chart sorting
    SUM(COUNT(*)) OVER(PARTITION BY primary_category) AS total_category_products
FROM data_warehouse.product_quadrants
WHERE business_action_flag IS NOT NULL
-- Group by primary category, then action flag
GROUP BY 1, 2
ORDER BY total_category_products DESC, product_count DESC
```

<BarChart 
    data={action_flags_by_category}
    x=primary_category
    y=product_count
    series=business_action_flag
    swapXY=true
    stack=true
    title="Business Action Flags by Category"
    xlabel="Number of Products"
/>

---

## Product Review Queue
*Filter by Amazon products by Category, as well as Business Action Flags to get a list of products to review for reselling*

<!-- Get Unique values for categories and business_action_flags to filter the actionable queue and bar chart -->
```sql primary_categories
SELECT DISTINCT
    primary_category
FROM data_warehouse.product_quadrants
ORDER BY primary_category ASC
```

```sql business_action_flags
SELECT DISTINCT business_action_flag 
    FROM data_warehouse.product_quadrants 
WHERE business_action_flag IS NOT NULL 
ORDER BY business_action_flag ASC
```

```sql product_quadrants_filtered
-- Filtered dataset based on what the user wants to review
SELECT * FROM data_warehouse.product_quadrants
WHERE primary_category LIKE '${inputs.primary_category.value}'
  AND business_action_flag LIKE '${inputs.business_flag.value}'
```

<!-- Actual Filter Buttons -->
<Grid cols={2}>
    <Dropdown data={primary_categories} name=primary_category value=primary_category>
        <DropdownOption value="%" valueLabel="All Primary Categories"/>
    </Dropdown>

    <Dropdown data={business_action_flags} name=business_flag value=business_action_flag>
        <DropdownOption value="%" valueLabel="All Business Action Flags"/>
    </Dropdown>
</Grid>

### 🎯 Product Sourcing Queue
*This queue prioritizes high-margin arbitrage opportunities*

```sql actionable_sourcing_queue
-- List of Products to review, based on filters, with extra data on opporunities
SELECT 
    product_id AS ASIN,
    product_name AS "Product Name",
    primary_category AS "Category",
    business_action_flag AS "Sourcing Flag",
    rating AS "Rating",
    rating_count AS "Reviews Volume",
    actual_price AS "MSRP",
    discounted_price AS "Current Discounted Price",
    (actual_price - discounted_price) AS "Arbitrage Spread ($)",
    (item_discount_pct/100) AS "Discount Percentage"
FROM ${product_quadrants_filtered}
ORDER BY 
    -- Prioritize Arbitrage Snipes first, then Hidden Gems
    CASE 
        WHEN business_action_flag = 'Prime Arbitrage Snipe' THEN 1
        WHEN business_action_flag = 'Potential Hidden Gem' THEN 2 
        ELSE 3 
    END ASC,
    item_discount_pct DESC
```

```sql business_action_flag_share
SELECT 
    business_action_flag as name, 
    COUNT(*) AS value
FROM ${product_quadrants_filtered}
GROUP BY 1
ORDER BY value DESC
```

### Business Action Share
<ECharts config={ {
    tooltip: {
        trigger: 'item',
        formatter: '{b}: {c} ({d}%)'
    },
    legend: {
        orient: 'horizontal',
        bottom: '0%'
    },
    series: [
        {
            type: 'pie',
            radius: ['0%', '60%'],
            center: ['50%', '45%'],
            data: business_action_flag_share,
            avoidLabelOverlap: true,
            label: {
                show: true,
                position: 'outside',
                formatter: '{b}\n({d}%)'
            },
            labelLine: {
                show: true
            }
        }
    ]
} } />

<DataTable data={actionable_sourcing_queue} search=true rows=10 rowsPerPage=10 compact=true>
    <Column id="ASIN" width="110px"/>
    <Column id="Product Name" wrap=true maxLength=80/>
    <Column id="Sourcing Flag"/>
    <Column id="Rating" contentType="badge" align="center"/>
    <Column id="Reviews Volume" fmt="num" align="right"/>
    <Column id="MSRP" fmt="usd" align="right"/>
    <Column id="Current Discounted Price" fmt="usd" align="right"/>
    <Column id="Arbitrage Spread ($)" fmt="usd" align="right" contentType="delta"/>
    <Column id="Discount Percentage" fmt="pct" align="right"/>
</DataTable>