import asyncio, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

def test_ari_worker_does_not_skip_drain_when_maintenance_fails(monkeypatch):
    calls=[]
    monkeypatch.setattr(rosa, '_maintain_channex_base_rate_horizons', lambda: (_ for _ in ()).throw(RuntimeError('boom')))
    monkeypatch.setattr(rosa, '_drain_channex_ari_outbox', lambda **kwargs: calls.append(kwargs) or {})
    monkeypatch.setattr(rosa, 'CHANNEX_API_KEY', 'test-key')
    monkeypatch.setattr(rosa, 'CHANNEX_ARI_SEND_SECONDS', 6)
    async def run_once():
        task=asyncio.create_task(rosa._channex_ari_worker_loop())
        await asyncio.sleep(0.5)
        task.cancel()
        try: await task
        except asyncio.CancelledError: pass
    asyncio.run(run_once())
    assert calls
