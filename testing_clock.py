"""Deterministic wall calendar for the historical certification fixtures only."""
from datetime import date, datetime, timedelta, timezone
from itertools import count


# Existing certification migrations deliberately contain November 2026 scenarios.
# Keep that historical dataset in the future of the *test* clock, on every host.
TEST_NOW = datetime(2026, 11, 1, 12, 0, 0)
_ticks = count()


def reset_clock():
    global _ticks
    _ticks = count()


class FixedDate(date):
    @classmethod
    def today(cls):
        return cls(TEST_NOW.year, TEST_NOW.month, TEST_NOW.day)


class FixedDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        # Preserve high-resolution event order (chat deliberately uses microsecond
        # timestamps), while keeping calendar dates and second-based timers fixed.
        stamp = TEST_NOW + timedelta(microseconds=next(_ticks))
        result = cls(stamp.year, stamp.month, stamp.day,
                     stamp.hour, stamp.minute, stamp.second, stamp.microsecond)
        return result if tz is None else result.replace(tzinfo=timezone.utc).astimezone(tz)

    @classmethod
    def today(cls):
        return cls.now()

    @classmethod
    def utcnow(cls):
        return cls.now()
