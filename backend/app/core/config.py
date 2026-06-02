from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "development"

    # Database
    database_url: str = "postgresql+asyncpg://homelocus:homelocus@localhost:5432/homelocus"
    database_url_sync: str = "postgresql://homelocus:homelocus@localhost:5432/homelocus"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # Storage — "local", "minio", or "s3"
    storage_backend: str = "local"
    storage_local_path: str = "/data/HomeLocus/uploads"
    # S3/MinIO settings (used when storage_backend is "minio" or "s3")
    storage_endpoint: str = "localhost:9000"
    storage_access_key: str = "minioadmin"
    storage_secret_key: str = "minioadmin"
    storage_bucket: str = "homelocus"
    storage_secure: bool = False

    # Qdrant
    qdrant_url: str = "http://localhost:6333"

    # Meilisearch
    meilisearch_url: str = "http://localhost:7700"
    meilisearch_api_key: str = "master-key"

    # AI Model (configurable: deepseek, openai, custom)
    ai_provider: str = "deepseek"  # "deepseek", "openai", or "custom"
    ai_api_key: str = ""
    ai_base_url: str = "https://api.deepseek.com"
    ai_model: str = "deepseek-chat"

    # Auth
    jwt_secret: str = "homelocus-dev-secret-change-in-production"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
