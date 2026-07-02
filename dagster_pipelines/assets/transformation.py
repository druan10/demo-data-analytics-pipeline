# assets/transformations.py
import os
from pathlib import Path
from typing import Any, Mapping
from dagster import AssetExecutionContext, AssetKey
from dagster_dbt import DbtCliResource, dbt_assets, DbtProject, DagsterDbtTranslator

# 1. Resolve the path to the dbt project directory
DBT_PROJECT_DIR = Path(__file__).parent.parent.parent.joinpath("dbt_project").resolve()

# 2. Initialize the DbtProject helper
dbt_project = DbtProject(
    project_dir=DBT_PROJECT_DIR,
    packaged_project_dir=Path(__file__).parent.parent.joinpath("dbt-project").resolve(),
)

# 3. Prepare the manifest
if os.getenv("DAGSTER_DBT_PARSE_PROJECT_ON_LOAD") != "0":
    dbt_project.prepare_if_dev()


# 4. Define the robust layout translator that handles nested folder boundaries
class FutureProofVerticalTranslator(DagsterDbtTranslator):
    def get_group_name(self, dbt_resource_props: Mapping[str, Any]) -> str:
        model_name = dbt_resource_props.get("name", "")
        
        # 1. Dynamically find the master pipeline vertical name based on filename keywords
        if "az" in model_name or "amazon" in model_name:
            vertical = "amazon_ecommerce"
        # Other sample pipeliens (wip)
        elif "vg" in model_name or "gaming" in model_name:
            vertical = "gaming_intelligence"
        elif "la" in model_name or "city" in model_name:
            vertical = "la_analytics"
        else:
            vertical = "other_pipelines"

        # 2. Determine the internal lifecycle stage box layer based on filename prefixes
        if model_name.startswith("stg_"):
            layer = "staging"
        elif model_name.startswith("dim_") or model_name.startswith("fct_"):
            layer = "marts"
        else:
            layer = "marts"

        return f"{vertical}/{layer}"

    def get_asset_key(self, dbt_resource_props: Mapping[str, Any]) -> AssetKey:
        model_name = dbt_resource_props.get("name", "")
        # Keep underlying asset keys flat [model_name] so dbt ref() links can map smoothly
        return AssetKey([model_name])


dagster_dbt_translator = FutureProofVerticalTranslator()


# 5. Define the monolithic asset function matching our custom translator
@dbt_assets(
    manifest=dbt_project.manifest_path,
    dagster_dbt_translator=dagster_dbt_translator
)
def my_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    """
    Builds all dbt models while parsing them into explicit nested layer blocks.
    """
    yield from dbt.cli(["build"], context=context).stream()