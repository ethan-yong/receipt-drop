import json
import os
from typing import Any

import redis.asyncio as redis

CACHE_TTL_SECONDS = 10
CACHE_KEY_PREFIX = "cache:friends:"

_redis: redis.Redis | None = None


def _redis_url() -> str:
    return os.environ.get("REDIS_URL", "redis://localhost:6379/0").strip()


async def get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(_redis_url(), decode_responses=True)
    return _redis


def cache_key(user_id: str) -> str:
    return f"{CACHE_KEY_PREFIX}{user_id}"


async def get_cached_leaderboard(user_id: str) -> list[dict[str, Any]] | None:
    client = await get_redis()
    raw = await client.get(cache_key(user_id))
    if raw is None:
        return None
    data = json.loads(raw)
    if not isinstance(data, list):
        return None
    return data


async def set_cached_leaderboard(user_id: str, entries: list[dict[str, Any]]) -> None:
    client = await get_redis()
    await client.setex(
        cache_key(user_id),
        CACHE_TTL_SECONDS,
        json.dumps(entries),
    )


async def close_redis() -> None:
    global _redis
    if _redis is not None:
        await _redis.aclose()
        _redis = None
