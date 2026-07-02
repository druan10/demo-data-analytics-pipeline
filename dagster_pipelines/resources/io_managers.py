from dagster import ConfigurableResource
import duckdb

class DuckDBResource(ConfigurableResource):
    database_path: str

    def query(self, sql, params=None):
        with duckdb.connect(self.database_path) as conn:
            return conn.execute(sql, params)