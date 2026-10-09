-- ============================================================================
-- END-TO-END ANALYTICS PROJECT: SMART SHARING & RETAIL (2.5M ROWS)
-- DWH DATABASE ARCHITECTURE & OPTIMIZATION (POSTGRESQL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: DWH SCHEMA CREATION (SNOWFLAKE SCHEMA)
-- ----------------------------------------------------------------------------

-- Dimension 1: Categories
CREATE TABLE dim_categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL
);

-- Dimension 2: Models (Linked to Categories)
CREATE TABLE dim_models (
    model_id SERIAL PRIMARY KEY,
    category_id INT REFERENCES dim_categories(category_id),
    model_name VARCHAR(150) NOT NULL
);

-- Dimension 3: Devices (Linked to Models)
CREATE TABLE dim_devices (
    device_id SERIAL PRIMARY KEY,
    model_id INT REFERENCES dim_models(model_id),
    serial_number VARCHAR(100) UNIQUE NOT NULL
);

-- Dimension 4: Tariffs
CREATE TABLE dim_tariffs (
    tariff_id SERIAL PRIMARY KEY,
    tariff_name VARCHAR(50) NOT NULL,
    base_fare NUMERIC(10, 2) NOT NULL,
    price_per_day NUMERIC(10, 2) NOT NULL,
    per_minute_tariff NUMERIC(10, 2) NOT NULL
);

-- Dimension 5: Users
CREATE TABLE dim_users (
    user_id SERIAL PRIMARY KEY,
    registration_date DATE NOT NULL,
    user_segment VARCHAR(50)
);

-- ----------------------------------------------------------------------------
-- STEP 2: PARTITIONED FACT TABLE (By Year: 2024 - 2026)
-- ----------------------------------------------------------------------------
CREATE TABLE fact_rentals (
    rental_id INT NOT NULL,
    user_id INT REFERENCES dim_users(user_id),
    device_id INT REFERENCES dim_devices(device_id),
    tariff_id INT REFERENCES dim_tariffs(tariff_id),
    rental_start TIMESTAMP NOT NULL,
    rental_end TIMESTAMP NOT NULL,
    gross_revenue NUMERIC(12, 2) DEFAULT 0.00,
    discount_amount NUMERIC(12, 2) DEFAULT 0.00,
    net_revenue NUMERIC(12, 2) DEFAULT 0.00,
    maintenance_cost NUMERIC(12, 2) DEFAULT 0.00,
    PRIMARY KEY (rental_id, rental_end) -- Composite key required for partitioning
) PARTITION BY RANGE (rental_end);

-- Creating physical partitions for 2.5 million rows dataset
CREATE TABLE fact_rentals_2024 PARTITION OF fact_rentals
    FOR VALUES FROM ('2024-01-01 00:00:00') TO ('2025-01-01 00:00:00');

CREATE TABLE fact_rentals_2025 PARTITION OF fact_rentals
    FOR VALUES FROM ('2025-01-01 00:00:00') TO ('2026-01-01 00:00:00');

CREATE TABLE fact_rentals_2026 PARTITION OF fact_rentals
    FOR VALUES FROM ('2026-01-01 00:00:00') TO ('2027-01-01 00:00:00');

-- ----------------------------------------------------------------------------
-- STEP 3: PERFORMANCE OPTIMIZATION (B-TREE INDEXES)
-- ----------------------------------------------------------------------------
CREATE INDEX idx_rentals_device ON fact_rentals(device_id);
CREATE INDEX idx_rentals_tariff ON fact_rentals(tariff_id);
CREATE INDEX idx_rentals_dates ON fact_rentals(rental_end, rental_start);

-- ----------------------------------------------------------------------------
-- STEP 4: DATA POST-PROCESSING (UPDATE WITH JOIN FOR REVENUE LAYER)
-- ----------------------------------------------------------------------------
-- Calculating net revenue based on actual tariff parameters and discount rules
UPDATE fact_rentals f
SET net_revenue = (f.gross_revenue - f.discount_amount)
FROM dim_tariffs t
WHERE f.tariff_id = t.tariff_id;

-- ----------------------------------------------------------------------------
-- STEP 5: ADVANCED ANALYTICS (EXECUTIVE REPORTING QUERY WITH CTE & WINDOW FUNCTIONS)
-- ----------------------------------------------------------------------------
-- This query aggregates data for BI import and isolates the "June marketing anomaly"
WITH monthly_metrics AS (
    SELECT 
        EXTRACT(MONTH FROM f.rental_end) AS rental_month,
        t.tariff_name,
        COUNT(f.rental_id) AS total_rentals,
        SUM(f.gross_revenue) AS raw_revenue,
        SUM(f.net_revenue) AS clean_revenue,
        AVG(f.net_revenue) AS average_check,
        SUM(f.maintenance_cost) AS total_repair_costs
    FROM fact_rentals f
    JOIN dim_tariffs t ON f.tariff_id = t.tariff_id
    GROUP BY EXTRACT(MONTH FROM f.rental_end), t.tariff_name
),
rolling_analytics AS (
    SELECT 
        rental_month,
        tariff_name,
        total_rentals,
        clean_revenue,
        average_check,
        -- Window function to calculate cumulative revenue growth MoM
        SUM(clean_revenue) OVER (PARTITION BY tariff_name ORDER BY rental_month) AS cumulative_revenue
    FROM monthly_metrics
)
SELECT 
    rental_month,
    tariff_name,
    total_rentals,
    clean_revenue,
    average_check,
    cumulative_revenue,
    -- Labeling the June anomaly for executive reporting
    CASE 
        WHEN rental_month = 6 AND clean_revenue = 0 THEN 'Marketing Campaign / Zero Revenue Anomaly'
        ELSE 'Normal Operations'
    END AS operational_status
FROM rolling_analytics
ORDER BY rental_month, clean_revenue DESC;
