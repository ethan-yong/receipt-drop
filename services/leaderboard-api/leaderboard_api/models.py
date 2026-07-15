from typing import Any

from pydantic import BaseModel


class AchievementBadgeSummary(BaseModel):
    badge_id: str
    tier: int  # 1=Bronze, 2=Silver, 3=Gold


class LeaderboardEntry(BaseModel):
    user_id: str
    display_name: str | None = None
    avatar_config: dict[str, Any] | None = None
    current_mood: str | None = None
    badge_score: int = 0
    current_streak: int = 0
    top_badges: list[AchievementBadgeSummary] = []
    is_me: bool = False


class LeaderboardResponse(BaseModel):
    entries: list[LeaderboardEntry]
    cached: bool = False
