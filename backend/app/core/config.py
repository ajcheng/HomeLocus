from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "development"

    # Database
    database_url: str = "postgresql+asyncpg://homelocus:homelocus@localhost:5432/homelocus"
    database_url_sync: str = "postgresql://homelocus:homelocus@localhost:5432/homelocus"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # MinIO
    minio_endpoint: str = "localhost:9000"
    minio_access_key: str = "minioadmin"
    minio_secret_key: str = "minioadmin"
    minio_bucket: str = "homelocus"
    minio_secure: bool = False

    # Qdrant
    qdrant_url: str = "http://localhost:6333"

    # Meilisearch
    meilisearch_url: str = "http://localhost:7700"
    meilisearch_api_key: str = "master-key"

    # DeepSeek AI
    deepseek_api_key: str = ""
    deepseek_base_url: str = "https://api.deepseek.com"

    # Storage
    storage_backend: str = "minio"
    upload_dir: str = "./uploads"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
