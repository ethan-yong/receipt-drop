from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.global_leaderboard import leaderboard_score
from app.main import app, lifespan


@pytest.mark.asyncio
async def test_global_leaderboard_requires_auth():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/leaderboard/global")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_global_leaderboard_zrevrange_order():
    me_id = "11111111-1111-1111-1111-111111111111"
    top_id = "22222222-2222-2222-2222-222222222222"

    hydrated = {
        top_id: {
            "user_id": top_id,
            "display_name": "Top",
            "avatar_config": {},
            "current_mood": "active",
            "badge_count": 5,
            "current_streak": 10,
            "is_me": False,
        },
        me_id: {
            "user_id": me_id,
            "display_name": "Me",
            "avatar_config": {},
            "current_mood": "calm",
            "badge_count": 1,
            "current_streak": 3,
            "is_me": False,
        },
    }

    with (
        patch("app.main.verify_bearer") as mock_verify,
        patch("app.main.build_global_entries", new_callable=AsyncMock) as mock_build,
    ):
        mock_verify.return_value = type("U", (), {"user_id": me_id})()
        mock_build.return_value = [
            {**hydrated[top_id], "is_me": False},
            {**hydrated[me_id], "is_me": True},
        ]

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get(
                "/leaderboard/global",
                headers={"Authorization": "Bearer fake-token"},
            )

    assert response.status_code == 200
    body = response.json()
    assert body["cached"] is False
    assert body["entries"][0]["user_id"] == top_id
    assert body["entries"][1]["is_me"] is True


@pytest.mark.asyncio
async def test_score_upsert_reads_postgres():
    me_id = "11111111-1111-1111-1111-111111111111"

    with (
        patch("app.main.verify_bearer") as mock_verify,
        patch(
            "app.main.fetch_caller_profile_scores", new_callable=AsyncMock
        ) as mock_scores,
        patch("app.main.upsert_user_score", new_callable=AsyncMock) as mock_upsert,
    ):
        mock_verify.return_value = type("U", (), {"user_id": me_id})()
        mock_scores.return_value = (7, 3)

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/leaderboard/score",
                headers={"Authorization": "Bearer fake-token"},
            )

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    mock_upsert.assert_awaited_once_with(me_id, 7, 3)
    assert leaderboard_score(7, 3) == 7_000_003.0


@pytest.mark.asyncio
async def test_rebuild_on_empty_zset():
    from fastapi import FastAPI

    with (
        patch("app.main.zset_cardinality", new_callable=AsyncMock, return_value=0),
        patch(
            "app.main.rebuild_from_postgres", new_callable=AsyncMock, return_value=2
        ) as mock_rebuild,
        patch("app.main.close_redis", new_callable=AsyncMock),
        patch("app.main.close_pool", new_callable=AsyncMock),
    ):
        async with lifespan(FastAPI()):
            pass

    mock_rebuild.assert_awaited_once()
