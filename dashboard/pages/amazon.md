
# Amazon Product Opportunity Analysis

This dashboard identifies high-potential categories, profitable arbitrage targets, and high-risk products to optimize your reselling and sourcing strategy. Original source data includes asins, product name, price and discounted prices (converted from Indian Rupees to USD), as well as rating_count + average rating per asin. This dataset lacks actual sales numbers and individual sales lines so based assumptions on listing data themselves.

```sql total_metrics
SELECT
    -- High volume, bad ratings, but listed at a premium price point
    SUM(CASE WHEN business_action_flag = 'High-Churn Trap' THEN 1 ELSE 0 END) AS total_risky_products,
    -- Great ratings, high volume, but currently priced below the normal category discount floor
    SUM(CASE WHEN business_action_flag = 'Prime Arbitrage Snipe' THEN 1 ELSE 0 END) AS arbitrage_snipes,
    -- Great ratings, low review volume 
    SUM(CASE WHEN category_product_segment = 'High R / Low Qty' THEN 1 ELSE 0 END) AS potential_gems,
    -- Low reviews and deep price cuts usually mean dead stock
    SUM(CASE WHEN business_action_flag = 'Liquidating / Low Demand' THEN 1 ELSE 0 END) AS liquidating_products

FROM data_warehouse.product_quadrants
```
# Global Overview

<BigValue
    data={total_metrics} 
    value=total_risky_products 
    title="Risky products"
    subtitle="High Demand + Deep Price Cut"
/>

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
    value=liquidating_products 
    title="Liquidating/Low Volume Products"
    subtitle="High Discounts and below average rating"
/>

# Category Action Flag Breakdown (Unfiltered)


```sql action_flags_by_category
SELECT 
    primary_category,
    business_action_flag,
    COUNT(*) AS product_count,
    -- Window function to calculate total flags per category for perfect chart sorting
    SUM(COUNT(*)) OVER(PARTITION BY primary_category) AS total_category_products
FROM data_warehouse.product_quadrants
WHERE business_action_flag IS NOT NULL
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
    title="Action Flags Distribution per Category"
    xlabel="Number of Products"
/>

## Strategic Planning
*Use this matrix to identify your next product niche. Filter by category to see the competitive landscape.*

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

```sql category_product_segments
SELECT DISTINCT category_product_segment 
    FROM data_warehouse.product_quadrants 
WHERE category_product_segment IS NOT NULL 
ORDER BY category_product_segment ASC
```

```sql product_quadrants_filtered
SELECT * FROM data_warehouse.product_quadrants
WHERE primary_category LIKE '${inputs.primary_category.value}'
  AND business_action_flag LIKE '${inputs.business_flag.value}'
  AND category_product_segment LIKE '${inputs.product_segment.value}'
```

<Grid cols={3}>
    <Dropdown data={primary_categories} name=primary_category value=primary_category>
        <DropdownOption value="%" valueLabel="All Primary Categories"/>
    </Dropdown>

    <Dropdown data={business_action_flags} name=business_flag value=business_action_flag>
        <DropdownOption value="%" valueLabel="All Sourcing Flags"/>
    </Dropdown>

    <Dropdown data={category_product_segments} name=product_segment value=category_product_segment>
        <DropdownOption value="%" valueLabel="All Volume/Rating Segments"/>
    </Dropdown>
</Grid>

```sql business_action_flag_share
SELECT 
    business_action_flag as name, 
    COUNT(*) AS value
FROM ${product_quadrants_filtered}
GROUP BY 1
ORDER BY value DESC
```

```sql actionable_sourcing_queue
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
        WHEN business_action_flag = 'High R / Low Qty' THEN 2 
        ELSE 3 
    END ASC,
    item_discount_pct DESC
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

<ScatterPlot 
    data={actionable_sourcing_queue}
    x="Discount Percentage"            
    y="Arbitrage Spread ($)"              
    color="Sourcing Flag"
    size="Reviews Volume"              
    title="Arbitrage Efficiency: Discount % vs. Dollar Spread"
    
/>


### Relevant Products
### 🎯 High-Priority Sourcing & Liquidation Queue
*This queue prioritizes high-margin arbitrage opportunities and flags dead-stock clearing ranges dynamically based on your filters above.*

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