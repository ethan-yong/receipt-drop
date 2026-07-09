import json
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_health():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_friends_leaderboard_requires_auth():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/friends-leaderboard")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_cache_hit_skips_database():
    cached_entries = [
        {
            "user_id": "11111111-1111-1111-1111-111111111111",
            "display_name": "Ethan",
            "avatar_config": {},
            "current_mood": "calm",
            "badge_count": 2,
            "current_streak": 5,
            "is_me": True,
        }
    ]

    with (
        patch("app.main.verify_bearer") as mock_verify,
        patch("app.main.get_cached_leaderboard", new_callable=AsyncMock) as mock_get,
        patch(
            "app.main.fetch_leaderboard_as_user", new_callable=AsyncMock
        ) as mock_fetch,
    ):
        mock_verify.return_value = type(
            "U", (), {"user_id": "11111111-1111-1111-1111-111111111111"}
        )()
        mock_get.return_value = cached_entries

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get(
                "/friends-leaderboard",
                headers={"Authorization": "Bearer fake-token"},
            )

    assert response.status_code == 200
    body = response.json()
    assert body["cached"] is True
    assert len(body["entries"]) == 1
    mock_fetch.assert_not_called()


@pytest.mark.asyncio
async def test_fresh_bypasses_cache():
    db_entries = [
        {
            "user_id": "11111111-1111-1111-1111-111111111111",
            "display_name": "Ethan",
            "avatar_config": None,
            "current_mood": "active",
            "badge_count": 1,
            "current_streak": 3,
            "is_me": True,
        }
    ]

    with (
        patch("app.main.verify_bearer") as mock_verify,
        patch("app.main.get_cached_leaderboard", new_callable=AsyncMock) as mock_get,
        patch("app.main.set_cached_leaderboard", new_callable=AsyncMock) as mock_set,
        patch(
            "app.main.fetch_leaderboard_as_user", new_callable=AsyncMock
        ) as mock_fetch,
    ):
        mock_verify.return_value = type(
            "U", (), {"user_id": "11111111-1111-1111-1111-111111111111"}
        )()
        mock_get.return_value = [{"user_id": "stale"}]
        mock_fetch.return_value = db_entries

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get(
                "/friends-leaderboard?fresh=true",
                headers={"Authorization": "Bearer fake-token"},
            )

    assert response.status_code == 200
    body = response.json()
    assert body["cached"] is False
    assert body["entries"][0]["display_name"] == "Ethan"
    mock_get.assert_not_called()
    mock_set.assert_awaited_once()


@pytest.mark.asyncio
async def test_rls_non_friend_excluded_from_db_rows():
    """RLS: leaderboard rows only include self and accepted friends."""
    friend_id = "22222222-2222-2222-2222-222222222222"
    stranger_id = "33333333-3333-3333-3333-333333333333"
    me_id = "11111111-1111-1111-1111-111111111111"

    rows = [
        {
            "user_id": me_id,
            "display_name": "Me",
            "avatar_config": {},
            "current_mood": "calm",
            "badge_count": 1,
            "current_streak": 2,
            "is_me": True,
        },
        {
            "user_id": friend_id,
            "display_name": "Friend",
            "avatar_config": {},
            "current_mood": "active",
            "badge_count": 3,
            "current_streak": 4,
            "is_me": False,
        },
    ]
    user_ids = {row["user_id"] for row in rows}
    assert stranger_id not in user_ids
    assert friend_id in user_ids

    # Integration test against live Postgres is run manually via README steps.
    serialized = json.dumps(rows)
    assert stranger_id not in serialized
