"""add_item_is_confirmed

Revision ID: f1a2b3c4d5e6
Revises: e6f7a8b9c0d1
Create Date: 2026-06-04 20:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "f1a2b3c4d5e6"
down_revision: Union[str, None] = "e6f7a8b9c0d1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "items",
        sa.Column("is_confirmed", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    # 新列默认 true 保留历史数据；之后应用层对 AI 识别新建为 false


def downgrade() -> None:
    op.drop_column("items", "is_confirmed")
