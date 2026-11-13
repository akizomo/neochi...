from __future__ import annotations

import argparse
import json
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
    deps = pipeline.Deps(judge=None) if a.judge == "session" else pipeline.Deps()
    done = 0
    for show in shows:
        eps = feeds.fetch_episodes(show)[: a.per_show]
        for ep in eps:
            if not a.force and store.get("analysis", ep.id):
                logging.info("解析済みのためスキップ: %s / %s", show.title, ep.title)
                continue
            if a.max_new and done >= a.max_new:
                break
            row = pipeline.analyze_episode(show, ep, cfg, store, deps)
            done += 1
            logging.info("%s / %s → final %s (%s)", show.title, ep.title, row["final_star"], row["input_depth"])
    _update_show_stars(store, [s.id for s in shows])
    store.save()
    logging.info("完了: %d 件を解析", done)
    return 0


def _update_show_stars(store, show_ids) -> None:
    for sid in show_ids:  # 番組の★ = 解析済みの回の最終★の平均(機械的な集計。手では動かさない)
        stars = store.final_stars(sid)
        if stars:
            store.update("show", sid, {"show_star": round(sum(stars) / len(stars), 1)})


def cmd_apply(a) -> int:
    """work/judgements.jsonl(1行1件の🌊🎯)を取り込み、★を計算し直す。取り込んだ回の判定待ちファイルは消す。"""
    cfg, store = load_config(), open_store(a.store)
    ok = 0
    for line in Path(a.file).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        j = json.loads(line)
        try:
            row = pipeline.apply_judgement(j, cfg, store)
        except (KeyError, ValueError) as e:
            logging.warning("取り込めませんでした: %s", e)
            continue
        ok += 1
        (Path(a.pending) / f"{pipeline._safe(j['episode_id'])}.json").unlink(missing_ok=True)
        logging.info("%s → final %s", j["episode_id"], row["final_star"])
    _update_show_stars(store, {e["show_id"] for e in store.rows("episode")})
    store.save()
    logging.info("完了: %d 件を取り込み", ok)
    return 0


def cmd_z_rank(a) -> int:
    zcfg, store = load_z_config(), open_store(a.store)
    shows = store.rows("show")
    for s in shows:
        rank = z_rank.z_rank(store.watch_latencies(s["id"]), zcfg)
        store.update("show", s["id"], {"z_rank": rank,
                                       "listing_status": "listed" if rank else "researching"})
        logging.info("%s → %s", s["title"], rank or "調査中")
    store.save()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="neochi")
    p.add_argument("--store", default="data/store.json", help="Supabase 未設定時の保存先(リポジトリに入れて次回に引き継ぐ)")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="候補CSVの番組を解析する")
    r.add_argument("--csv", default="data/shows.csv")
    r.add_argument("--limit", type=int, default=10, help="番組数の上限")
    r.add_argument("--per-show", type=int, default=1, help="番組あたり最新何回を見るか")
    r.add_argument("--force", action="store_true", help="解析済みの回も再解析する")
    r.add_argument("--max-new", type=int, default=0, help="1回の実行で新しく解析する件数の上限(0 = 無制限)")
    r.add_argument("--judge", choices=["api", "session"], default="session",
                   help="🌊🎯の判定。session = APIを使わず work/pending に書き出し、Claude のセッションで判定する")
    r.set_defaults(fn=cmd_run)
    ap = sub.add_parser("apply", help="セッションで判定した🌊🎯(JSONL)を取り込む")
    ap.add_argument("--file", default="work/judgements.jsonl")
    ap.add_argument("--pending", default="work/pending")
    ap.set_defaults(fn=cmd_apply)
    z = sub.add_parser("z-rank", help="sleep_log の実測から Z ランクを更新する")
    z.set_defaults(fn=cmd_z_rank)
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    return a.fn(a)
