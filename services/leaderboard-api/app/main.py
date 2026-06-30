from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials

from app.auth import AuthUser, bearer_scheme, verify_bearer
from app.cache import close_redis, get_cached_leaderboard, set_cached_leaderboard
from app.db import close_pool, fetch_leaderboard_as_user
from app.models import LeaderboardEntry, LeaderboardResponse


@asynccontextmanager
async def lifespan(_app: FastAPI):
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
