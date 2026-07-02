from pathlib import Path
import duckdb
from dagster import asset, MetadataValue, AssetKey
from ...resources.io_managers import DuckDBResource
import pandas as pd
import random
from datetime import datetime, timedelta
import os

@asset(
    key=AssetKey(["raw_az_data"]),
    # Matches the vertical/layer syntax format
    group_name="amazon_ecommerce/raw"
)
def raw_amazon_data(duckdb_warehouse: DuckDBResource):
    """
    Raw Layer
    Reads raw Amazon Data that into raw table that can be ingested by DBT in Silver and Gold layers.
    """

    # read sample amazon data from Kaggle https://www.kaggle.com/datasets/karkavelrajaj/amazon-sales-dataset
    # Amazon Dataset with review scores
    # Uses indian rupees as currency

    csv_fname = "/app/data/amazon/raw/amazon.csv"
    
    # 1. Dynamically capture environment suffix (defaults to 'dev')
    env = os.getenv("DAGSTER_ENV", "dev").lower()
    schema_name = f"{env}_raw" # Yields 'dev_raw' or 'prod_raw'

    # 2. Query execution with dynamic schema
    duckdb_warehouse.query(f"CREATE SCHEMA IF NOT EXISTS {schema_name}")
    duckdb_warehouse.query(
        f"CREATE OR REPLACE TABLE {schema_name}.raw_az_data AS SELECT * FROM read_csv_auto('{csv_fname}')"
    )

    # 2. Open a direct connection specifically to fetch the metadata count
    # This bypasses any custom resource lifecycle issues
    with duckdb.connect(duckdb_warehouse.database_path) as conn:
        row_count = conn.execute(f"SELECT COUNT(*) FROM {schema_name}.raw_az_data").fetchone()[0]

    return {
        "row_count": row_count,
        "database_path": MetadataValue.path(duckdb_warehouse.database_path),
        "table": f"{schema_name}.raw_az_data"
    }

