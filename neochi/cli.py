from __future__ import annotations

import argparse
import logging
from pathlib import Path

import yaml

from . import feeds, pipeline, z_rank
from .store import open_store

ROOT = Path(__file__).resolve().parent.parent


def load_config() -> dict:
    return yaml.safe_load((ROOT / "config" / "scoring.yaml").read_text(encoding="utf-8"))


def load_z_config() -> dict:
    return yaml.safe_load((ROOT / "config" / "z_rank.yaml").read_text(encoding="utf-8"))


def cmd_run(a) -> int:
    cfg, store = load_config(), open_store(a.store)
    shows = feeds.load_shows(a.csv)[: a.limit]
    done = 0
    for show in shows:
        eps = feeds.fetch_episodes(show)[: a.per_show]
        for ep in eps:
            if not a.force and store.get("analysis", ep.id):
                logging.info("解析済みのためスキップ: %s / %s", show.title, ep.title)
                continue
            row = pipeline.analyze_episode(show, ep, cfg, store)
            done += 1
            logging.info("%s / %s → final %s (%s)", show.title, ep.title, row["final_star"], row["input_depth"])
    for show in shows:  # 番組の★ = 解析済みの回の最終★の平均(機械的な集計。手では動かさない)
        stars = store.final_stars(show.id)
        if stars:
            store.upsert("show", {"id": show.id, "show_star": round(sum(stars) / len(stars), 1)})
    store.save()
    logging.info("完了: %d 件を解析", done)
    return 0


def cmd_z_rank(a) -> int:
    zcfg, store = load_z_config(), open_store(a.store)
    shows = store.rows("show")
    for s in shows:
        rank = z_rank.z_rank(store.watch_latencies(s["id"]), zcfg)
        store.upsert("show", {"id": s["id"], "z_rank": rank,
                              "listing_status": "listed" if rank else "researching"})
        logging.info("%s → %s", s["title"], rank or "調査中")
    store.save()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="neochi")
    p.add_argument("--store", default="out/store.json", help="Supabase 未設定時の保存先")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="候補CSVの番組を解析する")
    r.add_argument("--csv", default="data/shows.csv")
    r.add_argument("--limit", type=int, default=10, help="番組数の上限")
    r.add_argument("--per-show", type=int, default=1, help="番組あたり最新何回を見るか")
    r.add_argument("--force", action="store_true", help="解析済みの回も再解析する")
    r.set_defaults(fn=cmd_run)
    z = sub.add_parser("z-rank", help="sleep_log の実測から Z ランクを更新する")
    z.set_defaults(fn=cmd_z_rank)
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    return a.fn(a)
