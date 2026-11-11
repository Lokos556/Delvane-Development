import inspect
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

def test_reservation_channex_delivery_does_not_require_connected_status():
    src=inspect.getsource(rosa.reservation_channex_availability_delivery)
    assert "status=\'connected\'" not in src
    assert "adapter" in src and "channex_channel_manager" in src

def test_reservation_channex_retry_uses_mapping_readiness_not_connected_status():
    src=inspect.getsource(rosa.retry_reservation_channex_availability)
    assert "status=\'connected\'" not in src
    assert 'provider_property_id' in src
    assert 'channex_room_type_id' in src


def test_explicit_reservation_retry_clears_stale_local_rate_limit_pause():
    src=inspect.getsource(rosa.retry_reservation_channex_availability)
    assert 'channex_rate_limit_until=NULL' in src
    assert 'ignore_throttle=True' in src
