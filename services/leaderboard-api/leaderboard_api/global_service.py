from typing import Any

from leaderboard_api.cache import get_redis
from leaderboard_api.db import fetch_all_leaderboard_scores, fetch_profiles_by_ids_as_user
from leaderboard_api.global_leaderboard import GLOBAL_ZSET_KEY, compute_leaderboard_score


async def zset_cardinality() -> int:
    client = await get_redis()
    return int(await client.zcard(GLOBAL_ZSET_KEY))


async def upsert_user_score(user_id: str, streak: int, badge_score: int) -> None:
    client = await get_redis()
    score = compute_leaderboard_score(streak, badge_score)
    await client.zadd(GLOBAL_ZSET_KEY, {user_id: score})


async def fetch_top_global(limit: int = 100) -> list[tuple[str, float]]:
    client = await get_redis()
    raw = await client.zrevrange(GLOBAL_ZSET_KEY, 0, limit - 1, withscores=True)
    return [(member, float(score)) for member, score in raw]


async def rebuild_from_postgres() -> int:
    rows = await fetch_all_leaderboard_scores()
    if not rows:
        return 0
    client = await get_redis()
    mapping = {
        user_id: compute_leaderboard_score(streak, badge_score)
        for user_id, streak, badge_score in rows
    }
    await client.zadd(GLOBAL_ZSET_KEY, mapping)
    return len(mapping)


async def build_global_entries(
    viewer_user_id: str,
    limit: int = 100,
) -> list[dict[str, Any]]:
    ranked = await fetch_top_global(limit=limit)
    if not ranked:
        return []

    profile_ids = [user_id for user_id, _ in ranked]
    profiles_by_id = await fetch_profiles_by_ids_as_user(viewer_user_id, profile_ids)

    entries: list[dict[str, Any]] = []
    for user_id, _score in ranked:
        profile = profiles_by_id.get(user_id)
        if profile is None:
            continue
        profile["is_me"] = user_id == viewer_user_id
        entries.append(profile)
    return entries
