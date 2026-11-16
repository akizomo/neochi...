"""保存先。Supabase(Postgres)が本番、JSON ファイルはローカル実行とテスト用。

どちらも episode_id / show_id 単位の upsert なので、再実行しても行は増えない。
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import requests

from .scoring import is_judged


class JsonStore:
    TABLES = ("show", "episode", "analysis", "sleep_log")

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = {t: {} for t in self.TABLES}
        if self.path.exists():
            self.data.update(json.loads(self.path.read_text(encoding="utf-8")))

    def _key(self, table: str, row: dict) -> str:
        return row["episode_id"] if table == "analysis" else row["id"]

    def upsert(self, table: str, row: dict) -> None:
        k = self._key(table, row)
        self.data[table][k] = {**self.data[table].get(k, {}), **row}

    def update(self, table: str, key: str, fields: dict) -> None:
        """既存の行の一部の列だけを書き換える(行がなければ何もしない)。"""
        if key in self.data[table]:
            self.data[table][key].update(fields)

    def get(self, table: str, key: str) -> dict | None:
        return self.data[table].get(key)

    def rows(self, table: str) -> list[dict]:
        return list(self.data[table].values())

    def watch_latencies(self, sid: str) -> list[float]:
        eps = {e["id"] for e in self.rows("episode") if e["show_id"] == sid}
        return [r["latency_min"] for r in self.rows("sleep_log")
                if r.get("source") == "watch" and r["episode_id"] in eps and r.get("latency_min") is not None]

    def episode_watch_latencies(self, episode_id: str) -> list[float]:
        """その回の実測(source=watch)の分数。自己申告は入れない。"""
        return [r["latency_min"] for r in self.rows("sleep_log")
                if r.get("source") == "watch" and r["episode_id"] == episode_id and r.get("latency_min") is not None]

    def final_stars(self, sid: str) -> list[float]:
        """番組の評点に使う、回の総合評点。起伏と興味の両方を判定済みの回だけ(scoring.is_judged)。"""
        eps = {e["id"] for e in self.rows("episode") if e["show_id"] == sid}
        return [a["final_star"] for a in self.rows("analysis")
                if a["episode_id"] in eps and a.get("final_star") is not None and is_judged(a)]

    def votes(self, episode_id: str) -> tuple[list[int], list[int]]:
        """みんなの評価。(🌊 calm_vote 1〜5 の一覧, 🎯 interest_vote -1/0/1 の一覧)。"""
        rows = [r for r in self.rows("sleep_log") if r["episode_id"] == episode_id]
        return ([r["calm_vote"] for r in rows if r.get("calm_vote") is not None],
                [r["interest_vote"] for r in rows if r.get("interest_vote") is not None])

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, ensure_ascii=False, indent=1), encoding="utf-8")


class SupabaseStore:
    """PostgREST を直接叩く(依存を増やさない)。service key はサーバー側バッチ専用。"""

    CONFLICT = {"show": "id", "episode": "id", "analysis": "episode_id"}

    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/") + "/rest/v1"
        self.h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

    def upsert(self, table: str, row: dict) -> None:
        r = requests.post(f"{self.base}/{table}?on_conflict={self.CONFLICT[table]}",
                          headers={**self.h, "Prefer": "resolution=merge-duplicates"},
                          data=json.dumps(row, ensure_ascii=False).encode(), timeout=30)
        r.raise_for_status()

    def update(self, table: str, key: str, fields: dict) -> None:
        """一部の列だけの更新は PATCH で行う。upsert だと、省いた NOT NULL の列(title など)で拒否される。"""
        col = self.CONFLICT[table]
        r = requests.patch(f"{self.base}/{table}?{col}=eq.{key}", headers=self.h,
                           data=json.dumps(fields, ensure_ascii=False).encode(), timeout=30)
        r.raise_for_status()

    def get(self, table: str, key: str) -> dict | None:
        col = self.CONFLICT[table]
        r = requests.get(f"{self.base}/{table}?{col}=eq.{key}&select=*", headers=self.h, timeout=30)
        r.raise_for_status()
        rows = r.json()
        return rows[0] if rows else None

    def rows(self, table: str) -> list[dict]:
        r = requests.get(f"{self.base}/{table}?select=*", headers=self.h, timeout=30)
        r.raise_for_status()
        return r.json()

    def final_stars(self, sid: str) -> list[float]:
        r = requests.get(f"{self.base}/analysis?select=final_star,calm_star,interest_score,interest_level,episode!inner(show_id)"
                         f"&episode.show_id=eq.{sid}&final_star=not.is.null&calm_star=not.is.null", headers=self.h, timeout=30)
        r.raise_for_status()
        return [x["final_star"] for x in r.json() if is_judged(x)]

    def watch_latencies(self, sid: str) -> list[float]:
        r = requests.get(
            f"{self.base}/sleep_log?select=latency_min,episode!inner(show_id)"
            f"&source=eq.watch&episode.show_id=eq.{sid}&latency_min=not.is.null",
            headers=self.h, timeout=30)
        r.raise_for_status()
        return [x["latency_min"] for x in r.json()]

    def episode_watch_latencies(self, episode_id: str) -> list[float]:
        r = requests.get(f"{self.base}/sleep_log?select=latency_min&episode_id=eq.{episode_id}"
                         f"&source=eq.watch&latency_min=not.is.null", headers=self.h, timeout=30)
        r.raise_for_status()
        return [x["latency_min"] for x in r.json()]

    def votes(self, episode_id: str) -> tuple[list[int], list[int]]:
        r = requests.get(f"{self.base}/sleep_log?select=calm_vote,interest_vote&episode_id=eq.{episode_id}",
                         headers=self.h, timeout=30)
        r.raise_for_status()
        rows = r.json()
        return ([x["calm_vote"] for x in rows if x.get("calm_vote") is not None],
                [x["interest_vote"] for x in rows if x.get("interest_vote") is not None])

    def save(self) -> None:
        pass


def open_store(default_json: str = "data/store.json"):
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_KEY")
    if url and key:
        return SupabaseStore(url, key)
    return JsonStore(default_json)
