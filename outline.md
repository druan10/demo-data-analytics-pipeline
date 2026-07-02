pos-sales-analytics-platform/
├── .github/
│   └── workflows/          # CI/CD pipelines (e.g., auto-running dbt tests)
├── config/                 # Environment variables and local configs
├── data/                   # Git-ignored local data directory for DuckDB testing
│   ├── raw/             # Raw parquets, JSONs, and CSVs
│   └── sales_warehouse.db  # Your local DuckDB file (git-ignored)
├── dagster_pipelines/      # Your Dagster orchestration code
│   ├── __init__.py
│   ├── assets/
│   │   ├── raw/         # PYTHON-BASED INGESTION (Entry Point)
│   │   │   ├── __init__.py
│   │   │   └── ingestion.py # Renamed from generate_sample_pos_data.py
│   │   └── transformation.py # Assets that trigger dbt commands
│   └── repository.py
├── dbt_project/            # Your full dbt project directory
│   ├── dbt_project.yml     # Core dbt configuration configuration
│   ├── profiles.yml        # Warehouse target credentials (DuckDB info)
│   ├── models/
│   │   ├── staging/        # BRONZE TO SILVER: Cleaning, type casting, renaming
│   │   │   ├── stg_transactions.sql
│   │   │   ├── stg_items.sql
│   │   │   └── schema.yml  # Base data tests (not_null, unique)
│   │   └── marts/          # SILVER TO GOLD: Star schema & business logic
│   │       ├── dim_locations.sql
│   │       ├── dim_menu_items.sql
│   │       ├── fact_sales.sql
│   │       ├── mart_hourly_demand.sql
│   │       └── schema.yml  # Primary key & relationship tests
│   └── tests/              # Custom singular data tests
├── README.md               # The star of the show (explaining business metrics)
└── requirements.txt        # python dependencies (dagster, dbt-duckdb, pandas) - UV or something similar instead?