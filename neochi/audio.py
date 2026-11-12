"""音声のDL。解析後は必ず削除する(再配布しない)。"""
from __future__ import annotations

import contextlib
import tempfile
from pathlib import Path
from typing import Iterator

import requests


@contextlib.contextmanager
def downloaded(url: str, timeout: int = 60) -> Iterator[str]:
    """一時ディレクトリに音声をDLし、with を抜けたらディレクトリごと消す。"""
    with tempfile.TemporaryDirectory(prefix="neochi-") as tmp:
        path = Path(tmp) / "episode.audio"
        with requests.get(url, stream=True, timeout=timeout, headers={"User-Agent": "neochi-bot/0.1"}) as r:
            r.raise_for_status()
            with open(path, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
        yield str(path)
