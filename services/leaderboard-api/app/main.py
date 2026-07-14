from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials

from app.auth import bearer_scheme, verify_bearer
from app.cache import close_redis, get_cached_leaderboard, set_cached_leaderboard
from app.db import close_pool, fetch_caller_profile_scores, fetch_leaderboard_as_user
from app.global_service import (
    build_global_entries,
    rebuild_from_postgres,
    upsert_user_score,
    zset_cardinality,
)
from app.models import LeaderboardEntry, LeaderboardResponse


@asynccontextmanager
async def lifespan(_app: FastAPI):
    try:
        if await zset_cardinality() == 0:
            await rebuild_from_postgres()
    except Exception:
        # Best-effort cold start when Redis/Postgres are unavailable (e.g. unit tests).
        pass
    yield
    await close_redis()
    await close_pool()


app = FastAPI(title="Receipt Drop Leaderboard API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/friends-leaderboard", response_model=LeaderboardResponse)
async def friends_leaderboard(
    fresh: bool = Query(default=False),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme()),
) -> LeaderboardResponse:
    user = verify_bearer(credentials)

    if not fresh:
        cached = await get_cached_leaderboard(user.user_id)
        if cached is not None:
            return LeaderboardResponse(
                entries=[LeaderboardEntry.model_validate(e) for e in cached],
                cached=True,
            )

    entries = await fetch_leaderboard_as_user(user.user_id)
    await set_cached_leaderboard(user.user_id, entries)
    return LeaderboardResponse(
        entries=[LeaderboardEntry.model_validate(e) for e in entries],
        cached=False,
    )


@app.get("/leaderboard/global", response_model=LeaderboardResponse)
async def global_leaderboard(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme()),
) -> LeaderboardResponse:
    user = verify_bearer(credentials)
    entries = await build_global_entries(user.user_id)
    return LeaderboardResponse(
        entries=[LeaderboardEntry.model_validate(e) for e in entries],
        cached=False,
    )


@app.post("/leaderboard/score")
async def sync_leaderboard_score(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme()),
) -> dict[str, str]:
    user = verify_bearer(credentials)
    scores = await fetch_caller_profile_scores(user.user_id)
    if scores is None:
        return {"status": "no_profile"}
    streak, badge_score = scores
    await upsert_user_score(user.user_id, streak, badge_score)
    return {"status": "ok"}
