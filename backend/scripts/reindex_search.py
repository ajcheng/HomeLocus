"""Rebuild Meilisearch index from database. Run: python scripts/reindex_search.py"""
import asyncio

from app.core.database import async_session
from app.services.search_service import SearchService


async def main():
    async with async_session() as session:
        count = await SearchService(session).reindex_all_items()
    print(f"reindexed {count} items")


if __name__ == "__main__":
    asyncio.run(main())
