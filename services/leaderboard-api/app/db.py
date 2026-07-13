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


def _parse_top_badges(raw: Any) -> list:
    if raw is None:
        return []
    if isinstance(raw, str):
        raw = json.loads(raw)
    return raw if isinstance(raw, list) else []


def _row_to_entry(row: Any) -> dict[str, Any]:
    avatar_config = row["avatar_config"]
    if isinstance(avatar_config, str):
        avatar_config = json.loads(avatar_config)
    return {
        "user_id": str(row["user_id"]),
        "display_name": row["display_name"],
        "avatar_config": avatar_config,
        "current_mood": row["current_mood"],
        "badge_score": int(row["badge_score"]),
        "current_streak": int(row["current_streak"]),
        "top_badges": _parse_top_badges(row["top_badges"]),
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
    entries = []
    for row in rows:
        entry = _row_to_entry(row)
        entry["is_me"] = bool(row["is_me"])
        entries.append(entry)
    return entries


async def _apply_jwt_session(conn: asyncpg.Connection, user_id: str) -> None:
    await conn.execute("set local role authenticated")
    await conn.execute(
        "select set_config('request.jwt.claim.sub', $1, true)",
        user_id,
    )
    await conn.execute(
        "select set_config('request.jwt.claim.role', $1, true)",
        "authenticated",
    )


async def fetch_caller_profile_scores(user_id: str) -> tuple[int, int] | None:
    """Read the caller's streak/badge_score from profiles under JWT scope."""
    UUID(user_id)
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _apply_jwt_session(conn, user_id)
            row = await conn.fetchrow(
                """
                select current_streak, badge_score
                from public.profiles
                where id = $1
                """,
                UUID(user_id),
            )
    if row is None:
        return None
    return int(row["current_streak"]), int(row["badge_score"])


async def fetch_profiles_by_ids_as_user(
    user_id: str,
    profile_ids: list[str],
) -> dict[str, dict[str, Any]]:
    """Hydrate leaderboard metadata via get_leaderboard_profiles_by_ids."""
    if not profile_ids:
        return {}
    UUID(user_id)
    uuids = [UUID(pid) for pid in profile_ids]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _apply_jwt_session(conn, user_id)
            rows = await conn.fetch(
                "select * from public.get_leaderboard_profiles_by_ids($1::uuid[])",
                uuids,
            )
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        entry = _row_to_entry(row)
        entry["is_me"] = False
        result[entry["user_id"]] = entry
    return result


async def fetch_all_leaderboard_scores() -> list[tuple[str, int, int]]:
    """Read all scorable profiles for Redis ZSET cold-start rebuild."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("select * from public.list_leaderboard_scores()")
    return [
        (str(row["user_id"]), int(row["current_streak"]), int(row["badge_score"]))
        for row in rows
    ]
