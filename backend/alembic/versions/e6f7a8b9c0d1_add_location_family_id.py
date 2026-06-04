"""add_location_family_id

Revision ID: e6f7a8b9c0d1
Revises: d5e6f7a8b9c0
Create Date: 2026-06-03 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "e6f7a8b9c0d1"
down_revision: Union[str, None] = "d5e6f7a8b9c0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "locations",
        sa.Column("family_id", sa.String(50), sa.ForeignKey("families.id", ondelete="SET NULL"), nullable=True),
    )
    op.create_index("ix_locations_family_id", "locations", ["family_id"])
    # Link existing family homes by matching name (best-effort for legacy data)
    op.execute(
        """
        UPDATE locations l
        SET family_id = f.id
        FROM families f
        WHERE l.family_id IS NULL AND l.name = f.name
        """
    )


def downgrade() -> None:
    op.drop_index("ix_locations_family_id", table_name="locations")
    op.drop_column("locations", "family_id")
