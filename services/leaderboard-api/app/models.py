from typing import Any

from pydantic import BaseModel


class LeaderboardEntry(BaseModel):
    user_id: str
    display_name: str | None = None
    avatar_config: dict[str, Any] | None = None
    current_mood: str | None = None
    badge_count: int
    current_streak: int
    is_me: bool


class LeaderboardResponse(BaseModel):
    entries: list[LeaderboardEntry]
    cached: bool = False
