# Base python image
FROM python:3.10-slim

WORKDIR /app

# Best Practice: Ensure logs are unbuffered for real-time visibility in Dagster UI
ENV PYTHONUNBUFFERED=1
ENV DAGSTER_HOME=/app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the actual project files
COPY . .

# Best Practice: Generate manifest at build time for production speed.
# This ensures the manifest.json is baked into the image.

# Install deps to avoid fresh build error
RUN cd dbt_project && dbt deps

# Parse Manifest
RUN cd dbt_project && dbt parse --profiles-dir .

# 'dagster dev' launches the webserver and the gRPC code server.
# We bind to 0.0.0.0 so the UI is accessible from the host machine.
CMD ["dagster", "dev", "-h", "0.0.0.0", "-p", "3000", "-m", "dagster_pipelines.definitions"]