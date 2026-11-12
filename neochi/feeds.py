"""CSV の候補番組と RSS の読み取り。"""
from __future__ import annotations

import csv
import logging
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from email.utils import parsedate_to_datetime
from pathlib import Path

import requests

log = logging.getLogger("neochi.feeds")
NS = {"itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd"}
_NAMESPACE = uuid.UUID("6f1c0c8e-5f55-4a54-9c1e-6e0c0c0c0001")  # neochi… 固定


def show_id(rss_url: str) -> str:
    return str(uuid.uuid5(_NAMESPACE, rss_url.strip()))


def episode_id(sid: str, guid: str) -> str:
    return str(uuid.uuid5(_NAMESPACE, f"{sid}:{guid}"))


@dataclass
class Show:
    id: str
    title: str
    publisher: str
    rss_url: str
    genre: str
    lang: str = "ja"
    artwork_url: str | None = None  # RSS の itunes:image。複製せず URL だけ持つ
    link_url: str | None = None  # 配信元の番組のサイト(RSS の channel/link)


@dataclass
class Episode:
    id: str
    show_id: str
    title: str
    audio_url: str
    duration_sec: int | None
    published_at: str | None
    description: str = ""
    link_url: str | None = None  # 配信元の回のページ(RSS の item/link)


def load_shows(csv_path: str | Path) -> list[Show]:
    """列: title, publisher, rss_url, genre, lang(省略時 ja)。"""
    shows = []
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            url = (row.get("rss_url") or "").strip()
            if not url:
                continue
            shows.append(Show(
                id=show_id(url),
                title=(row.get("title") or "").strip(),
                publisher=(row.get("publisher") or "").strip(),
                rss_url=url,
                genre=(row.get("genre") or "").strip(),
                lang=(row.get("lang") or "ja").strip() or "ja",
            ))
    return shows


def _http(url: str | None) -> str | None:
    url = (url or "").strip()
    return url if url.startswith(("http://", "https://")) else None


def _duration(text: str | None) -> int | None:
    if not text:
        return None
    parts = text.strip().split(":")
    try:
        nums = [int(float(p)) for p in parts]
    except ValueError:
        return None
    sec = 0
    for n in nums:
        sec = sec * 60 + n
    return sec


def parse_feed(xml_bytes: bytes, sid: str) -> list[Episode]:
    """新しい順の Episode を返す。音声URLのない item は除く。"""
    root = ET.fromstring(xml_bytes)
    items = []
    for item in root.iterfind("./channel/item"):
        enc = item.find("enclosure")
        if enc is None or not enc.get("url"):
            continue
        guid = (item.findtext("guid") or enc.get("url")).strip()
        pub = None
        raw = item.findtext("pubDate")
        if raw:
            try:
                pub = parsedate_to_datetime(raw).isoformat()
            except (TypeError, ValueError):
                pub = None
        items.append(Episode(
            id=episode_id(sid, guid),
            show_id=sid,
            title=(item.findtext("title") or "").strip(),
            audio_url=enc.get("url").strip(),
            duration_sec=_duration(item.findtext("itunes:duration", namespaces=NS)),
            published_at=pub,
            description=(item.findtext("description") or "").strip(),
            link_url=_http(item.findtext("link")),
        ))
    items.sort(key=lambda e: datetime.fromisoformat(e.published_at) if e.published_at else datetime.min.astimezone(), reverse=True)
    return items


def parse_artwork(xml_bytes: bytes) -> str | None:
    """番組のカバー画像の URL(itunes:image、なければ channel/image/url)。"""
    root = ET.fromstring(xml_bytes)
    img = root.find("./channel/itunes:image", NS)
    if img is not None and (img.get("href") or "").strip():
        return img.get("href").strip()
    url = (root.findtext("./channel/image/url") or "").strip()
    return url or None


def parse_link(xml_bytes: bytes) -> str | None:
    """配信元の番組のサイト(channel/link)。http(s) 以外は捨てる。"""
    url = (ET.fromstring(xml_bytes).findtext("./channel/link") or "").strip()
    return url if url.startswith(("http://", "https://")) else None


def fetch_episodes(show: Show, timeout: int = 20) -> list[Episode]:
    """RSS を取得して回の一覧を返す。404 などは警告して空を返す(スキップ)。"""
    try:
        r = requests.get(show.rss_url, timeout=timeout, headers={"User-Agent": "neochi-bot/0.1"})
        if r.status_code != 200:
            log.warning("RSS 取得に失敗(%s): %s %s", r.status_code, show.title, show.rss_url)
            return []
        show.artwork_url = parse_artwork(r.content)
        show.link_url = parse_link(r.content)
        return parse_feed(r.content, show.id)
    except (requests.RequestException, ET.ParseError) as e:
        log.warning("RSS を読めません: %s %s (%s)", show.title, show.rss_url, e)
        return []
