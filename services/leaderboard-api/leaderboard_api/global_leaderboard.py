GLOBAL_ZSET_KEY = "leaderboard:global"

# score = (streak × 100) + badge_score
# Rationale: streak dominates (100 pts/day consistency reward);
# badge_score breaks ties within the same streak tier.
# Max badge_score = 6 badges × 3 (Gold) = 18, always < 100 → clean integer decode.
_STREAK_WEIGHT = 100


def compute_leaderboard_score(streak: int, badge_score: int) -> int:
    return streak * _STREAK_WEIGHT + badge_score


def decode_leaderboard_score(score: float) -> tuple[int, int]:
    total = int(score)
    streak = total // _STREAK_WEIGHT
    badge_score = total % _STREAK_WEIGHT
    return streak, badge_score
