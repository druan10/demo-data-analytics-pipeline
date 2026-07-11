# demo-data-analytics-platform
Sample Production Data Analytics Pipeline 

# Problem/Goal
With this repo, I wanted to deliver a simplified data analytics and visualizations platform, for average companies who want to immediately dive into analytics without too much investment. While there are lots of Enterprise solutions that require no server maintenance, many companies might not yet be sure whether they want to invest in these tools, or simply don't have the scale of data required to justify the investment. Many companies can get by with a simple data stack like this to accomplish their business goals.

This repo is designed primarily as a lightweight, on-prem data analytics pipeline. Data is ingested via python (for now), transformed and staged in a local data warehouse using DBT and DuckDB, and visualized using Evidence. 

## Design Philosophy

- **Local-First Modern Data Stack:** Providing a high-performance analytics ecosystem running entirely on local infrastructure. Hoping to extend this to allow the use of Kubernetes to scale properly in the future.
- **Strict Decoupling:** Enforcing a clean separation of concerns between data ingestion, transformation layers, and business intelligence logic to simplify development and developer onboarding.

## Technologies Used

- **Docker:** Containerizes ecosystem services, ensuring immutable deployments and parity between local development and cloud replication.
- **Dagster:** Controls data orchestration. It provides a clean, unified control plane to manage asset dependencies, operational scheduling, job runs, and rich metadata visibility.
- **DuckDB:** Serves as the primary analytical database engine. Staging layer data is processed natively as in-memory views to eliminate temporary storage footprints, while raw and business-ready layers are written to highly optimized, file-based columnar storage.
- **dbt (dbt-core):** Drives data modeling, transformations, and testing within a unified Medallion architecture.
- **Evidence.dev:** Acts as the Business Intelligence (BI) application layer, enabling high-performance, responsive reporting applications built entirely using markdown and SQL as code.

# Quick Setup Guide

### Prerequisites
Ensure you have [Docker](https://www.docker.com/) and Docker Compose installed locally.

## 1. Start the Stack
Spin up the container network:

```bash
docker-compose up --build
```

Note, only Dagster will start successfully, as the required duckdb db's that Evidence needs won't exist yet.

```
[ ! ] Error connecting to datasource data_warehouse: IO Error: Cannot open database "/app/sources/data_warehouse/db/dev_data_warehouse.db" in read-only mode: database does not exist
```

### 2. Access Dagster
Once initialized, the Dagster ui will be available via your browser:
* **Dagster Orchestrator:** http://localhost:3000/

### 3. Materialize the Assets
Navigate to the Dagster UI asset graph and trigger a manual run to materialize all assets. This will run the data pipeline and create the db's evidence needs.

### 4. Restart Evidence
You'll need to restart the Evidence Container to have it load the newly created sources.

```bash
docker-compose restart evidence_dashboard
```

You should now be able to access the Evidence Dashboard here:

* **Evidence Analytics App:** http://localhost:3001/

---

In the future, you will only need to run the following to get development back up and running.

```bash
docker-compose up
```

# Amazon Analytics Use Case

The Amazon data pipeline takes a sample Amazon Dataset from Kaggle, does some simple cleaning and price conversions, and uses the available data to help suggest products for reselling. This data didn't include actual sales counts, so I used a combination of average review score, review count, MSRP, current discounted price, as well as breakdowns by category to suggest high value resell targets.
---

### Applied Analytical Frameworks

The pipeline transforms uncleaned catalog attributes into four highly descriptive sourcing segments mapped dynamically in the analytics frontend:

1. **Prime Arbitrage Snipes:** These are products with higher than average prices compared to others in their category, with high ratings, that are also currently selling for prices lower than normal. These have the highest potential profit margins which would be a primary target for dropshipping/reseller businesses.
2. **Hidden Gems:** Highly rated products that have lower than average ratings. Valuable to look at as these could potentially be good investments, but haven't gotten enough traction just yet.
3. **High-Churn Traps (Risky Products):** These are products that have high volume, but lower than average ratings. Could be products that are returned/refunded often, which would be good to avoid.
4. **Liquidating / Low Demand Stock:** These are products that are being heavily discounted with low rating counts, which could indicate low volume, or products that are selling very slowly. Good to avoid as a business could be stuck with dead stock.

---

### Key Application Features Included

- **Dynamic Filtering:** Support for filtering across Product Segments, Sourcing Flags, and Primary Categories.
- **High-Priority Sourcing Queue:** Provides a list of products to based on your filters. Automatically sorts based on the opportunity/margins.

---

## Data Architecture & Lineage

Data flows linearly from source files through progressive ingestion, staging, and modeling layers:

### 1. Raw Layer
- **Purpose:** Immutable landing zone for source data ingested directly from upstream environments.
- **Characteristics:** Schema-on-write constraints are minimal; files are stored exactly as received to preserve structural history.
- **Location:** Ingestion definitions are managed via standard Dagster assets under `dagster_pipelines/assets/raw/`. These assets are manually tagged into their appropriate groups/layers via their group_name in the asset definition.

### 2. Staging Layer
- **Purpose:** Conformed, enterprise-wide source of truth.
- **Characteristics:** Data is cast to explicit types, schema structures are normalized, null fields are structured, and keys are deduplicated (e.g., using `QUALIFY ROW_NUMBER()`). Staging tables are built primarily as fast database views.
- **Location:** Models are defined under `dbt_project/models/staging/` and backed by comprehensive schema freshness and data quality validation tests.

### 3. Marts Layer
- **Purpose:** Business-ready dimensional modeling layer.
- **Characteristics:** Optimized using dimensional frameworks (Star Schema Facts and Dimensions). It integrates complex business logic, performance aggregates, and analytical metrics ready for low-latency reporting queries.
- **Location:** Models are located under `dbt_project/models/marts/`.

## Orchestration Core Concepts: Naming, Keys, and Groups

To seamlessly bind dbt and Dagster together, the platform relies on a strict relationship between dbt model filenames, Dagster Asset Keys, and Asset Groups.

### 1. How Raw Assets are Named

Raw ingestion assets are managed directly via standard Dagster Python assets (located under dagster_pipelines/assets/raw/).

    The Rule: Python raw asset names match the naming conventions of the downstream dbt sources.

    Example: A raw ingestion asset that pulls CSV data for Amazon is named raw_az__sales. When it executes, it writes a physical table to DuckDB named raw_az__sales. This ensures that when dbt runs a source query, the underlying database objects match exactly what the orchestration layer produced.

### 2. Why We Need Asset Keys

An Asset Key is the unique identifier Dagster uses to track an object inside its internal state machine. It is the literal "node name" on your lineage graph.

    The Problem: By default, if a dbt model lives in a nested directory structure (like models/staging/amazon/stg_az__sales.sql), Dagster tries to generate a nested asset key like ["staging", "amazon", "stg_az__sales"]. However, inside dbt, cross-model relationships are defined as flat strings via {{ ref('stg_az__sales') }}. This mismatch completely breaks the visual lineage link between assets.

    The Solution: The custom get_asset_key method overrides this behavior by forcing a completely flat structure:
    Python

    return AssetKey([model_name])

    By keeping the asset key identical to the raw dbt model name (stg_az__sales), Dagster can read the dbt manifest.json, map the dependencies flawlessly, and track upstream-to-downstream telemetry without configuration conflicts.

### 3. Why We Need Asset Groups (and the Slash / Syntax)

An Asset Group is a logical boundary box used to organize a massive data warehouse canvas into distinct, digestible workspaces. Without groups, every single table and view in your warehouse would render into one giant, unreadable spiderweb of nodes.

Our architecture uses a dynamic translation strategy to split groups using a slash (vertical/layer) string syntax:

    The "Vertical" (Before the Slash): Represents the distinct domain or data pipeline pipeline (e.g., amazon_ecommerce, gaming_intelligence, etc). This creates top-level workspace separation in the Dagster UI sidebar, allowing engineers to filter down to only the project domain they care about.

    The "Layer" (After the Slash): Represents the structural lifecycle step (raw, staging or marts).

### Visual Impact on the UI

When you return a string formatted as vertical/layer (for example, amazon_ecommerce/staging), Dagster's UI engine performs two clean structural tricks:

    Sidebar Isolation: It groups the asset collection under the parent vertical (amazon_ecommerce) in your sidebar navigation.

    Canvas Containment: On the interactive global DAG graph, it draws a physical, distinct boundary box around assets in each layer.

This layout means you can look at the global orchestrator canvas and immediately see data traveling from the amazon_ecommerce/staging box directly into the amazon_ecommerce/marts box, visually proving your engineering principles are being enforced by the code execution engine.

---

## Technical & Design Considerations

### Automated Asset-to-Group Mapping
To streamline engineering workflows, this platform dynamically maps dbt models to their corresponding Dagster asset groups based entirely on filename keywords and prefixes. For instance, any model containing `az` or `amazon` is automatically routed to the **Amazon** data vertical, while prefixes like `stg_` isolate it down into the specific **Staging** execution layer box. 

This pattern makes it incredibly straightforward to scale out new parallel pipelines (e.g., *Gaming Intelligence*, *LA Analytics*) within the same repository without modifying complex python configuration arrays.

The logic is controlled via a custom `DagsterDbtTranslator` subclass inside `dagster_pipelines/assets/transformation.py`:

```python
from typing import Any, Mapping
from dagster import AssetKey
from dagster_dbt import DagsterDbtTranslator

class FutureProofVerticalTranslator(DagsterDbtTranslator):
    """
    Dynamically routes dbt models into logical Dagster asset groups
    based on naming conventions and project verticals.
    """
    def get_group_name(self, dbt_resource_props: Mapping[str, Any]) -> str:
        model_name = dbt_resource_props.get("name", "")
        
        # 1. Isolate the master operational vertical via keyword lookup
        if "az" in model_name or "amazon" in model_name:
            vertical = "amazon_ecommerce"
        # Other sample pipeliens (wip)
        elif "vg" in model_name or "gaming" in model_name:
            vertical = "gaming_intelligence"
        elif "la" in model_name or "city" in model_name:
            vertical = "la_analytics"
        else:
            vertical = "other_pipelines"

        # 2. Assign the internal lifecycle execution layer via model prefix
        if model_name.startswith("stg_"):
            layer = "staging"
        else:
            layer = "marts"  # Default mapping for dim_ and fct_ semantic structures

        # Returning 'vertical/layer' splits the asset catalog visually 
        # while drawing isolated physical boundary sub-boxes on the DAG canvas
        return f"{vertical}/{layer}"

    def get_asset_key(self, dbt_resource_props: Mapping[str, Any]) -> AssetKey:
        model_name = dbt_resource_props.get("name", "")
        # Keep underlying asset keys flat so dbt internal ref() resolution targets seamlessly
        return AssetKey([model_name])
```

### Docker Dev Optimization
The multi-container configuration is heavily optimized for localized feedback loops. Volume mounting is configured to handle seamless cross-container locks on the target DuckDB `.db` file, while hot-reloading is fully supported inside the Evidence container—meaning UI adjustments display immediately upon saving markdown files.

---

## Future Roadmap

The platform’s decoupled architecture is built to evolve. Future development is prioritized across three core technical tracks, advancing from infrastructure refinement to broader domain analytics and downstream predictive modeling.

### 1. Production-Grade Container Optimization
* **Multi-Stage Docker Builds:** Transition from the current local development setup to lean, multi-stage production Dockerfiles to minimize layer footprints, optimize build caching, and decrease image deployment sizes.
* **Granular Secret Management:** Replace plaintext local environment variables with secure handling (such as Docker Secrets or isolated, encrypted `.env` boundaries) to completely decouple operational infrastructure credentials from application code.
* **State Persistence Isolation:** Implement robust volume-mounting and connection-locking strategies to guarantee that the single-file DuckDB database state remains highly available and protected against corruption during concurrent container restarts.

### 2. Pipeline Expansion & Domain Diversification
* **LA City Logistics Pipeline:** Build a localized municipal data vertical parsing public city logistics and infrastructure feeds, testing the stack's ability to ingest and model spatial and temporal data frames natively within DuckDB.
* **Deadlock Gameplay Intelligence Engine:** Integrate a dedicated telemetry vertical parsing structured match logs and item data schemas from Valve's *Deadlock*. This pipeline moves beyond generic match tracking to deliver deeply personalized gameplay optimization frameworks:
    * **Graph-Based Item Dependencies:** Models multi-tier item scaling, stat-stacking behaviors, and soul-efficiency build pathways using relational dimension bridging.
    * **Spatio-Temporal Positioning Analytics:** Parses high-resolution time-series coordinate logs (`X, Y, Z` positional vectors) against match timelines to map optimal map positioning, team-fight positioning, and high-risk death zones correlated with overall win-rate metrics.
    * **Macro-Meta Trend Tracking:** Implements categorical investment tracking across Weapon, Vitality, and Spirit archetypes to dynamically surface emerging hero-specific build trends and broader systemic meta shifts.

* **POS Commercial Engine:** Deploy a Point-of-Sale (POS) data engine processing transactional retail payloads, serving as the foundational feature store for downstream retail optimization models.

### 3. Advanced Predictive Analytics & ML Integration
* **Automated Demand Forecasting:** Embed lightweight machine learning models (using `scikit-learn` or `Prophet` natively inside Python-based Dagster assets) to predict sales velocities and inventory consumption directly from POS metrics.
* **Arbitrage Propensity Scoring:** Develop an algorithmic scoring system that computes a dynamic probability matrix for listing churn, automatically flagging high-priority arbitrage targets that exhibit volatile supplier behavior.
* **Semantic Vector Search:** Explore the integration of the `duckdb_vss` extension to perform fast, localized semantic text embedding searches across uncleaned, messy marketplace catalog descriptions.