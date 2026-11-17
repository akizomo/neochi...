# NeochiPickzz ブランドアセット

ロゴ・記号・アプリアイコンの正式版。**ここにあるファイルを使い、作り直さない。** 形の定義は `neochi/brand.py`、書き出しは `python design/brand/build.py`(`librsvg` の `rsvg-convert` が要る)。色と濃さは `design/tokens.json`(`logo-bg` `logo-fg` `opacity-logo-1〜3`)。

## 何を使うか

| 場所 | ファイル | 備考 |
|---|---|---|
| ロゴ(基本) | `svg/wordmark-on-dark.svg` | 暗い地。紺 `#171C33` の上に置く |
| ロゴ(明るい地) | `svg/wordmark-on-light.svg` | |
| ロゴ(1色・濃淡なし) | `svg/wordmark-mono-on-light.svg` / `-on-dark.svg` | 刺繍、ハンコ、刻印など、薄れが出せないとき |
| 記号 N | `svg/symbol-*.svg` | ロゴの N だけ。背景なし |
| iOS アプリアイコン | `png/app-icon-1024.png` | 角丸なしの正方形。`ios/.../AppIcon.appiconset/icon-1024.png` にも同じものを入れてある |
| X・SNS のアイコン | `png/x-profile-400.png` | 丸く切り抜かれるので、N は中央 |
| Web アイコン | `png/app-icon-192.png` `app-icon-512.png` `app-icon-180.png`(apple-touch-icon) `svg/favicon.svg` `png/favicon-32.png` `favicon-16.png` | ファビコンは N を大きくしてある |
| 共有カード(OG) | `png/og-1200x630.png` | サイトの `og.png` と同じ |
| スライド・資料 | `png/wordmark-on-dark@2x.png` `-on-light@2x.png` `png/symbol-*@2x.png` | 透過 PNG |

## 形と色

- ワードマークは一語の **NeochiPickzz**。IBM Plex Sans Medium の字形を輪郭(path)にしてあり、書体がなくても同じ形で描ける。文字として打ち直さない。
- 頭の **N** は、3本の線が右へ薄れる(100% → 60% → 28%)。末尾の **zz** は、1つ目が 100%、2つ目が 28%。名前の両端が寝落ちになる。
- 色は 2 色だけ。地 `#171C33`(logo-bg)、文字と記号 `#D9DCEA`(logo-fg)。明るい地では、地と文字を入れ替える。画面の評点(琥珀)や結果(青灰)の色とは混ぜない。
- アイコンは、紺の地に N 一文字を中央に置く。N の高さは辺の 46%。

## 使い方の決まり

- 基本形のロゴは1つ。記号をワードマークの横に添えない。
- 周りに N の幅以上の余白を空ける。
- 最小サイズは、ワードマークで高さ 16px。それより小さい場所では記号だけにする。
- 薄れの順(左から右)を逆にしない。N と zz 以外の文字は薄くしない。
- スペースを入れて二語にしない。別の書体で組まない。
- 小文字・大文字は `NeochiPickzz`(N と P だけ大文字)。カタカナには直さない。

## 作り直すとき

```bash
python design/brand/build.py   # svg/ と png/ を作り直し、ios のアプリアイコンとサイトの og.png・apple-touch-icon.png も更新する
```

デザインの元の検討は、ロゴの板(claude.ai のデザインキャンバス「NeochiPickzz ロゴ」)の「ロゴ体系：NeochiPickzz」「ロゴの色」にある。形や色を変えるときは、そこで決めてから `neochi/brand.py` と `design/tokens.json` を直す。
