"""items slot_id nullable for space delete archive

Revision ID: i4d5e6f7g8h9
Revises: h3c4d5e6f7g8
Create Date: 2026-06-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "i4d5e6f7g8h9"
down_revision: Union[str, None] = "h3c4d5e6f7g8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column("items", "slot_id", existing_type=sa.String(length=50), nullable=True)


def downgrade() -> None:
    op.alter_column("items", "slot_id", existing_type=sa.String(length=50), nullable=False)
