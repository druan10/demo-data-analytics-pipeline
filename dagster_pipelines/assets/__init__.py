from dagster import load_assets_from_modules

# Load all asset files
# Best Practice: Organize assets by layer or source system
from .raw import ingestion
from . import transformation 

# Actually load the assets
all_assets = load_assets_from_modules([ingestion, transformation])
