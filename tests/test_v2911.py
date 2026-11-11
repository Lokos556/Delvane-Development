from pathlib import Path


ROOT=Path(__file__).resolve().parents[1]


def test_reservation_calendar_supports_far_future_month_navigation():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    assert "let reservationCalendarMonth = null;" in js
    assert "type=\"month\"" in js
    assert 'id="calPrev"' in js
    assert 'id="calNext"' in js
    assert 'id="calToday"' in js
    assert 'Array.from({length:42}' in js
    assert 'reservationCalendarMonth=e.target.value' in js


def test_calendar_and_editor_explain_checkout_exclusive_nights():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    css=(ROOT/'static'/'styles.css').read_text(encoding='utf-8')
    assert 'function stayNights(arrival,departure)' in js
    assert 'Checkout: ${fmtDate(departure)}; that night remains available.' in js
    assert 'Departure / checkout' in js
    assert 'Total reservation value (HUF)' in js
    assert '.day-cell{width:76px;min-width:76px' in css
    assert '.booking-bar>i' in css

