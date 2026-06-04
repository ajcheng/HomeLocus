"""add_item_category

Revision ID: b3c4d5e6f7a8
Revises: 8e52727b8b8e
Create Date: 2026-06-04 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "b3c4d5e6f7a8"
down_revision: Union[str, None] = "8e52727b8b8e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("items", sa.Column("category", sa.String(length=50), nullable=True))


def downgrade() -> None:
    op.drop_column("items", "category")
