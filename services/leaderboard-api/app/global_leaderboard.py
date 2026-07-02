GLOBAL_ZSET_KEY = "leaderboard:global"
SCORE_MULTIPLIER = 1_000_000


def leaderboard_score(streak: int, badge_count: int) -> float:
    return float(streak * SCORE_MULTIPLIER + badge_count)


def decode_leaderboard_score(score: float) -> tuple[int, int]:
    total = int(score)
    streak = total // SCORE_MULTIPLIER
    badge_count = total % SCORE_MULTIPLIER
    return streak, badge_count
