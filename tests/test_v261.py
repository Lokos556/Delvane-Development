from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def test_v261_luna_local_setup_surface():
    root=Path(__file__).resolve().parents[1]
    assert rosa.OPENAI_MODEL == "gpt-5.6-luna"
    assert rosa.OPENAI_REASONING_EFFORT == "none"
    assert (root/"SETUP_ROSA_AI.bat").exists()
    assert (root/"DISABLE_ROSA_AI.bat").exists()
    assert (root/"setup_rosa_ai.py").exists()
    assert (root/"AI_SETUP.md").exists()
    assert not (root/".env.local").exists()
    ignore=(root/".gitignore").read_text(encoding="utf-8")
    assert ".env.local" in ignore
    source=(root/"app.py").read_text(encoding="utf-8")
    assert 'https://api.openai.com/v1/responses' in source
    assert '"reasoning":{"effort":OPENAI_REASONING_EFFORT}' in source
