from dagster import Definitions, ConfigurableResource
import duckdb
from dagster_dbt import DbtCliResource
import os

from .assets import all_assets
from .assets.transformation import dbt_project
from .resources.io_managers import DuckDBResource

# The Definitions object is the top-level entry point for Dagster.
# It bundles assets, resources, and configurations into a single 
# loadable unit for the Dagster webserver.

# Dagster environmental variable to allow for dev and prod db locations
dagster_env = os.getenv("DAGSTER_ENV", "dev")

# via the volume mount defined in docker-compose.yaml.
duck_db_path = "/app/data/db/prod_data_warehouse.db" if dagster_env == "prod" else "/app/data/db/dev_data_warehouse.db"

defs = Definitions(
    assets=all_assets,
    resources={
        "dbt": DbtCliResource(project_dir=dbt_project),
        "duckdb_warehouse": DuckDBResource(database_path=duck_db_path)
    },
)