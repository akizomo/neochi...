from __future__ import annotations

import argparse
import json
import logging
import os
import uuid
from pathlib import Path

import yaml

from . import feeds, genre, pipeline, versions, z_rank
from .store import JsonStore, open_store

ROOT = Path(__file__).resolve().parent.parent


def load_config() -> dict:
    return yaml.safe_load((ROOT / "config" / "scoring.yaml").read_text(encoding="utf-8"))


def load_z_config() -> dict:
    return yaml.safe_load((ROOT / "config" / "z_rank.yaml").read_text(encoding="utf-8"))


def _shard(shows, spec: str | None):
    """"i/n" を指定すると、番組ID(固定のUUID)で n 分割したうちの i 番目だけを返す。並列に回すときに使う。"""
    if not spec:
        return shows
    i, n = (int(x) for x in spec.split("/"))
    if n < 1 or not 0 <= i < n:
        raise SystemExit(f"--shard は i/n の形で、0 <= i < n にしてください: {spec}")
    return [s for s in shows if uuid.UUID(s.id).int % n == i]


def _too_short(ep, cfg: dict) -> bool:
    """入眠に必要な時間を確保できない短い回は解析しない。再生時間が分からない回は、判断できないので対象にする。"""
    m = (cfg.get("episode") or {}).get("min_minutes") or 0
    return bool(m and ep.duration_sec and ep.duration_sec < m * 60)


def below_standard_ids(store) -> set[str]:
    """評点がついたうえで、格付けの基準に届かなかった番組(載せない番組)のID。新着の解析の対象から外す。
    評点がまだない番組(判定済みの回がない)は含めない。解析しないと評点がつかないため。"""
    return {s["id"] for s in store.rows("show") if s.get("show_star") is not None and not s.get("z_rank")}


def cmd_run(a) -> int:
    cfg, store = load_config(), open_store(a.store)
    shows = _shard(feeds.load_shows(a.csv)[: a.limit], a.shard)  # 先に上限で絞ってから分割する
    if not a.include_unlisted:
        skip = below_standard_ids(store)
        for sh in shows:
            if sh.id in skip:
                logging.info("基準未満の番組のため解析しない: %s", sh.title)
        shows = [sh for sh in shows if sh.id not in skip]
    deps = pipeline.Deps(judge=None) if a.judge == "session" else pipeline.Deps()
    done = 0
    for show in shows:
        if a.max_new and done >= a.max_new:
            break
        eps = feeds.fetch_episodes(show)[: a.per_show]
        for ep in eps:
            if _too_short(ep, cfg):
                logging.info("短すぎるためスキップ(%.1f分): %s / %s", ep.duration_sec / 60, show.title, ep.title)
                continue
            if not a.force and store.get("analysis", ep.id):
                logging.info("解析済みのためスキップ: %s / %s", show.title, ep.title)
                continue
            if a.max_new and done >= a.max_new:
                break
            row = pipeline.analyze_episode(show, ep, cfg, store, deps)
            done += 1
            logging.info("%s / %s → final %s (%s)", show.title, ep.title, row["final_star"], row["input_depth"])
    _update_show_stars(store, [s.id for s in shows])
    update_ratings(store, [s.id for s in shows], load_z_config())
    store.save()
    logging.info("完了: %d 件を解析", done)
    return 0


def _update_show_stars(store, show_ids) -> None:
    for sid in show_ids:  # 番組の評点 = 起伏・興味を判定済みの回の総合評点の平均(機械的な集計。手では動かさない)
        stars = store.final_stars(sid)
        # 判定済みの回がなければ、評点を空にする(耳のゆるさだけの点を、番組の評点として出さない)
        store.update("show", sid, {"show_star": round(sum(stars) / len(stars), 1) if stars else None})


def update_ratings(store, show_ids, zcfg: dict) -> None:
    """番組の評点から寝落ち格付けを決める。基準未満は掲載しない(評点は残す)。

    格付けは、いつも評点だけで決める。評点が基準を下回ったら、すぐ下げる(格下げの保留はしない)。"""
    shows = {s["id"]: s for s in store.rows("show")}
    for sid in show_ids:
        s = shows.get(sid)
        if not s:
            continue
        rank = z_rank.z_rank(s.get("show_star"), zcfg)
        store.update("show", sid, {"z_rank": rank, "listing_status": "listed" if rank else "researching"})
        logging.info("%s → %s", s["title"], rank or "掲載しない")


def cmd_repending(a) -> int:
    """保存した文字起こしから、判定待ちのファイルを作り直す。音声の取得と文字起こしはしない。
    採点基準(config/rubric.md)を変えたあと、古い基準で判定した回(--stale)や、指定した回だけを判定し直すときに使う。
    そのあとは、いつもどおり、セッションが work/pending を判定し、`python -m neochi apply` で取り込む。"""
    cfg, store = load_config(), open_store(a.store)
    eps = {e["id"]: e for e in store.rows("episode")}
    shows = {s["id"]: s for s in store.rows("show")}
    trs = {t["episode_id"]: t for t in store.rows("transcript")}
    want = set(a.episodes.split(",")) if a.episodes else None
    n = missing = 0
    for row in store.rows("analysis"):
        eid = row["episode_id"]
        if want is not None and eid not in want:
            continue
        if a.stale and not versions.stale((row.get("reasons") or {}).get("versions"), ("rubric",), cfg):
            continue
        if not want and not a.stale:
            continue
        ep = eps.get(eid)
        if ep is None:
            continue
        tr = trs.get(eid)
        if tr is None:
            missing += 1
            continue
        if a.limit and n >= a.limit:
            break
        spans = [(x, y, t) for x, y, t in tr["spans"]]
        pipeline.write_pending(a.pending, eid, (shows.get(ep["show_id"]) or {}).get("title", ""), ep.get("title") or "", spans)
        n += 1
    print(f"判定待ちを {n} 件書き出しました({a.pending})。文字起こしが保存されていない回: {missing} 件(音声から取り直す必要があります)")
    return 0


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
    ids = {e["show_id"] for e in store.rows("episode")}
    _update_show_stars(store, ids)
    update_ratings(store, ids, load_z_config())
    store.save()
    logging.info("完了: %d 件を取り込み", ok)
    return 0


def cmd_remeasure(a) -> int:
    """解析済みの回の、音響の特徴だけを測り直す(測る範囲や基準を変えたとき)。🌊🎯と話す速さは触らない。

    終わったら、番組の評点と格付けも、引き継がずに全番組を計算し直す。
    """
    cfg, zcfg, store = load_config(), load_z_config(), open_store(a.store)
    episodes = {e["id"]: e for e in store.rows("episode")}
    shows = {s["id"]: s for s in store.rows("show")}
    done = 0
    for row in store.rows("analysis"):
        if row.get("input_depth") not in ("audio", "transcript"):
            continue  # 音声を解析していない回(説明文だけ)は、測り直す音がない
        if a.max_new and done >= a.max_new:
            break
        e = episodes.get(row["episode_id"])
        if not e or not e.get("audio_url"):
            continue
        lang = (shows.get(e["show_id"]) or {}).get("lang") or "ja"
        try:
            new = pipeline.remeasure_acoustics(row, e["audio_url"], lang, cfg, store)
        except Exception as ex:  # noqa: BLE001 - 1件の失敗で全体を止めない
            logging.warning("測り直せませんでした: %s (%s)", e.get("title"), ex)
            continue
        done += 1
        logging.info("%s → 🎧 %s / 総合評点 %s", e.get("title"), new["ear_star"], new["final_star"])
    ids = [s["id"] for s in store.rows("show")]
    _update_show_stars(store, ids)
    update_ratings(store, ids, zcfg)
    store.save()
    logging.info("測り直し: %d 件", done)
    return 0


def cmd_z_rank(a) -> int:
    """実測・みんなの評価が増えたあとに、総合評点・番組の評点・格付けを計算し直す。"""
    cfg, zcfg, store = load_config(), load_z_config(), open_store(a.store)
    before = {s["id"]: s.get("z_rank") for s in store.rows("show")}
    if a.dry_run:  # 本番の行を手元のメモリに写して計算する。何も書き込まない
        mem = JsonStore("/nonexistent/dry-run.json")
        for t in JsonStore.TABLES:
            for r in store.rows(t):
                mem.data[t][mem._key(t, r)] = r
        store = mem
    episodes = {e["id"]: e for e in store.rows("episode")}
    shows = {s["id"]: s for s in store.rows("show")}
    for row in store.rows("analysis"):
        if a.rules_changed:  # 採点ルールが変わったときは、🌊(項目の点)と🎧(特徴)も、保存済みの値から計算し直す
            lang = (shows.get((episodes.get(row["episode_id"]) or {}).get("show_id")) or {}).get("lang") or "ja"
            row = pipeline.recalm(pipeline.reear(row, lang, cfg), cfg)
            fields = {k: row.get(k) for k in ("features", "ear_star", "calm_star")}
            store.update("analysis", row["episode_id"], {**fields, "total_star": pipeline.restar_ai(row, cfg)})
        final, reason = pipeline.restar(row, cfg, store)
        store.update("analysis", row["episode_id"], {"final_star": final, "final_reason": reason})
    ids = [s["id"] for s in store.rows("show")]
    _update_show_stars(store, ids)
    update_ratings(store, ids, zcfg)
    if a.dry_run:
        _print_rank_shares(before, store.rows("show"))
        print("ドライランです。何も保存していません。")
        return 0
    store.save()
    return 0


def _print_rank_shares(before: dict, shows: list[dict]) -> None:
    """格付けの割合(変更前 → 変更後)。"""
    from collections import Counter

    after = {s["id"]: s.get("z_rank") for s in shows}
    n = len(after) or 1
    cb, ca = Counter(before.values()), Counter(after.values())
    print(f"番組 {len(after)} 件")
    for r in ("ZZZ", "ZZ", "Z", None):
        print(f"  {r or '載せない':6s} {cb[r]:3d} ({cb[r] * 100 // n:2d}%) → {ca[r]:3d} ({ca[r] * 100 // n:2d}%)")
    moved = sum(1 for k, v in after.items() if before.get(k) != v)
    print(f"  格付けが変わる番組 {moved} 件")


def cmd_sync_shows(a) -> int:
    """CSV の系統(genre)・集めた目的(cohort)・言語を、登録済みの番組に書き写す。解析はしない。
    まだ登録していない番組は、何もしない(解析のときに入る)。"""
    store = open_store(a.store)
    n = 0
    for s in feeds.load_shows(a.csv):
        store.update("show", s.id, {"genre": s.genre, "cohort": s.cohort, "apple_category": s.apple_category, "lang": s.lang})
        n += 1
    store.save()
    logging.info("完了: CSV の %d 番組ぶんを書き写し(未登録の番組は対象外)", n)
    return 0


def cmd_categorize(a) -> int:
    """CSV の番組の RSS を読み、Apple Podcasts のカテゴリを apple_category 列に書く。
    genre が空の行は、そのカテゴリから系統の初期値を入れる。番組を足したあとに流す。"""
    import csv

    with open(a.csv, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    filled = 0
    for r in rows:
        if r.get("apple_category") and not a.refresh:
            continue
        try:
            res = feeds.requests.get(r["rss_url"], timeout=20, headers={"User-Agent": "neochi-bot/0.1"})
            cat = feeds.parse_category(res.content) if res.status_code == 200 else None
        except Exception as e:  # noqa: BLE001
            logging.warning("RSS を読めません: %s (%s)", r.get("title"), e)
            continue
        r["apple_category"] = cat or ""
        if not (r.get("genre") or "").strip():
            r["genre"] = genre.from_apple(cat)
            logging.info("系統を入れた: %s → %s(%s)", r.get("title"), r["genre"], cat)
        filled += 1
    cols = ["title", "publisher", "rss_url", "genre", "apple_category", "cohort", "lang"]
    with open(a.csv, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    logging.info("完了: %d 番組のカテゴリを読んだ。系統は CSV で確かめて、寝落ち用・朗読・環境音は手で直す", filled)
    return 0


def cmd_site(a) -> int:
    from . import site

    args = ["--out", a.out, "--base-url", a.base_url] + (["--from-json", a.from_json] if a.from_json else [])
    return site.main(args)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="neochi")
    p.add_argument("--store", default="data/store.json", help="Supabase 未設定時の保存先(リポジトリに入れて次回に引き継ぐ)")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="候補CSVの番組を解析する")
    r.add_argument("--csv", default="data/shows.csv")
    r.add_argument("--limit", type=int, default=10, help="番組数の上限")
    r.add_argument("--per-show", type=int, default=1, help="番組あたり最新何回を見るか")
    r.add_argument("--shard", default=None, help="並列実行用。例: 0/3 は番組を3分割した最初の1つ")
    r.add_argument("--force", action="store_true", help="解析済みの回も再解析する")
    r.add_argument("--include-unlisted", action="store_true", help="基準未満(載せない)の番組も解析する。ふだんは外す")
    r.add_argument("--max-new", type=int, default=0, help="1回の実行で新しく解析する件数の上限(0 = 無制限)")
    r.add_argument("--judge", choices=["api", "session"], default="session",
                   help="🌊🎯の判定。session = APIを使わず work/pending に書き出し、Claude のセッションで判定する")
    r.set_defaults(fn=cmd_run)
    ap = sub.add_parser("apply", help="セッションで判定した🌊🎯(JSONL)を取り込む")
    ap.add_argument("--file", default="work/judgements.jsonl")
    ap.add_argument("--pending", default="work/pending")
    ap.set_defaults(fn=cmd_apply)
    rp = sub.add_parser("repending", help="保存した文字起こしから、判定待ちを作り直す(採点基準を変えたあとの判定し直し。音声は使わない)")
    rp.add_argument("--stale", action="store_true", help="古い基準(config/rubric.md の版が違う、または記録がない)で判定した回")
    rp.add_argument("--episodes", default="", help="回のIDをカンマ区切りで指定(確かめ用の回など)")
    rp.add_argument("--limit", type=int, default=0, help="書き出す件数の上限(0 = 無制限)")
    rp.add_argument("--pending", default="work/pending")
    rp.set_defaults(fn=cmd_repending)
    m = sub.add_parser("remeasure", help="解析済みの回の音響(音量・突発音)だけを測り直す。測る範囲や基準を変えたあとに使う")
    m.add_argument("--max-new", type=int, default=0, help="1回の実行で測り直す件数の上限(0 = 無制限)")
    m.set_defaults(fn=cmd_remeasure)
    z = sub.add_parser("z-rank", help="実測・みんなの評価から、総合評点と寝落ち格付けを計算し直す")
    z.add_argument("--rules-changed", action="store_true",
                   help="採点ルールや格付けの線を変えたとき。付いている格付けを引き継がず、全番組を計算し直す")
    z.add_argument("--dry-run", action="store_true", help="何も保存せず、格付けの割合(変更前 → 変更後)だけを表示する")
    z.set_defaults(fn=cmd_z_rank)
    ss = sub.add_parser("sync-shows", help="CSV の系統・集めた目的・言語を、登録済みの番組に書き写す(解析はしない)")
    ss.add_argument("--csv", default="data/shows.csv")
    ss.set_defaults(fn=cmd_sync_shows)
    ca = sub.add_parser("categorize", help="RSS から Apple Podcasts のカテゴリを読み、CSV の空の系統に初期値を入れる")
    ca.add_argument("--csv", default="data/shows.csv")
    ca.add_argument("--refresh", action="store_true", help="読み済みの番組も読み直す")
    ca.set_defaults(fn=cmd_categorize)
    st = sub.add_parser("site", help="紹介サイト(静的HTML)を書き出す。公開キー(SUPABASE_URL か SUPABASE_HOST と SUPABASE_ANON_KEY)で読む")
    st.add_argument("--out", default="out/site")
    st.add_argument("--base-url", default=os.environ.get("SITE_URL", ""), help="公開先の URL。OGP と共有のリンクに使う")
    st.add_argument("--from-json", default=None, help="Supabase ではなく、この store.json から読む")
    st.set_defaults(fn=cmd_site)
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    return a.fn(a)
