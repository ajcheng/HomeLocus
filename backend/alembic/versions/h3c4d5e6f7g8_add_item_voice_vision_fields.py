"""add item color purpose raw_recognition

Revision ID: h3c4d5e6f7g8
Revises: g2b3c4d5e6f7
Create Date: 2026-06-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "h3c4d5e6f7g8"
down_revision: Union[str, None] = "g2b3c4d5e6f7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("items", sa.Column("color", sa.String(length=50), nullable=True))
    op.add_column("items", sa.Column("purpose", sa.String(length=200), nullable=True))
    op.add_column("items", sa.Column("raw_recognition", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("items", "raw_recognition")
    op.drop_column("items", "purpose")
    op.drop_column("items", "color")
