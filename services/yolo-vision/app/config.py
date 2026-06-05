from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    models_dir: str = "/models"
    default_model: str = "yolo11"  # yolo11 | worldv2 | both
    default_device: str = "intel:cpu"  # intel:gpu | intel:cpu | cpu
    default_conf: float = 0.25
    api_key: str = ""
    host: str = "0.0.0.0"
    port: int = 8765
    max_upload_mb: int = 32

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
