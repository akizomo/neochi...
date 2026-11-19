#!/usr/bin/env bash
# v2 確かめの結果の回収。判定セッションが push したブランチから、判定(JSONL)を取り出して、run ごとに連結する。
# 使い方: tools/collect_trial.sh <ラウンド番号> [分担の数(既定 3)]   例: tools/collect_trial.sh 3 2
# 出力: data/trial_v2/round<N>/run1.jsonl, run2.jsonl(分担 s0/s1/s2 を連結)。そろっていない分担は、その旨を表示する。
set -euo pipefail
R="${1:?ラウンド番号}"; NS="${2:-3}"; P="trial-v2-r${R}"
OUT="data/trial_v2/round${R}"; mkdir -p "$OUT"; git fetch -q origin
for run in 1 2; do
  : > "$OUT/run${run}.jsonl"
  for s in $(seq 0 $((NS-1))); do
    b="origin/${P}-run${run}-s${s}"
    if git rev-parse -q --verify "$b" >/dev/null; then
      git show "$b:work/v2_run${run}_s${s}.jsonl" >> "$OUT/run${run}.jsonl"
    else
      echo "まだない: ${P}-run${run}-s${s}" >&2
    fi
  done
  echo "run${run}: $(grep -c . "$OUT/run${run}.jsonl") 行"
done
