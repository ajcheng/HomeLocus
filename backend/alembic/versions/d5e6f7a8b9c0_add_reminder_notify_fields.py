"""add_reminder_notify_fields

Revision ID: d5e6f7a8b9c0
Revises: c4d5e6f7a8b9
Create Date: 2026-06-04 20:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "d5e6f7a8b9c0"
down_revision: Union[str, None] = "c4d5e6f7a8b9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("reminders", sa.Column("last_notified_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("reminders", sa.Column("notify_count", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("reminders", "notify_count")
    op.drop_column("reminders", "last_notified_at")
