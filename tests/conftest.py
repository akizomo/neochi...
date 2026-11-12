import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


@pytest.fixture(scope="session")
def cfg():
    return yaml.safe_load((ROOT / "config" / "scoring.yaml").read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def zcfg():
    return yaml.safe_load((ROOT / "config" / "z_rank.yaml").read_text(encoding="utf-8"))
