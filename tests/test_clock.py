from datetime import date, datetime, timedelta
import pytest
import app


def test_application_and_fixture_calendar_agree():
    assert date.today().isoformat() == "2026-11-01"
    assert datetime.now().replace(microsecond=0).isoformat() == app.now_iso() == "2026-11-01T12:00:00"
    assert app.date.today() == date.today()
    first = app.datetime.now()
    second = datetime.now()
    assert second > first
    assert (second - first).microseconds == 1


def test_production_past_date_rule_is_preserved_under_test_clock():
    yesterday = str(date.today() - timedelta(days=1))
    with pytest.raises(app.HTTPException) as error:
        app._ari_date_range(yesterday, yesterday)
    assert error.value.status_code == 400
    tomorrow = date.today() + timedelta(days=1)
    assert app._ari_date_range(str(tomorrow), str(tomorrow)) == (tomorrow, tomorrow)
