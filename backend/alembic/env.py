import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

# Alembic Config object
config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

from app.models import Base

target_metadata = Base.metadata

_db_url = os.environ.get("DATABASE_URL_SYNC")
if _db_url:
    config.set_main_option("sqlalchemy.url", _db_url)


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


run_migrations_online()
