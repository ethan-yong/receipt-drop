import json
import os
from typing import Any
from uuid import UUID

import asyncpg

_pool: asyncpg.Pool | None = None


def _database_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError("DATABASE_URL is not set")
    return url


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(_database_url(), min_size=1, max_size=10)
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def _row_to_entry(row: asyncpg.Record) -> dict[str, Any]:
    avatar_config = row["avatar_config"]
    if isinstance(avatar_config, str):
        avatar_config = json.loads(avatar_config)
    return {
        "user_id": str(row["user_id"]),
        "display_name": row["display_name"],
        "avatar_config": avatar_config,
        "current_mood": row["current_mood"],
        "badge_count": int(row["badge_count"]),
        "current_streak": int(row["current_streak"]),
        "is_me": bool(row["is_me"]),
    }


async def fetch_leaderboard_as_user(user_id: str) -> list[dict[str, Any]]:
    """Run get_friend_leaderboard() under an authenticated JWT-scoped session."""
    UUID(user_id)  # validate format before hitting the database
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute("set local role authenticated")
            await conn.execute(
                "select set_config('request.jwt.claim.sub', $1, true)",
                user_id,
            )
            await conn.execute(
                "select set_config('request.jwt.claim.role', $1, true)",
                "authenticated",
            )
            rows = await conn.fetch("select * from public.get_friend_leaderboard()")
    return [_row_to_entry(row) for row in rows]
