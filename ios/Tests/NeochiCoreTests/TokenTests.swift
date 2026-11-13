import XCTest
@testable import NeochiCore

/// デザイン規則(design/tokens.json、contrast.md)を、値の側から守る。
final class TokenTests: XCTestCase {
    func ratio(_ fg: NCColor, _ bg: NCColor, _ t: NCTheme) -> Double { NCContrast.ratio(fg, on: bg, t) }

    // 通常の文字は 4.5:1 以上。ダークは3つの面、ライトは bg-base と surface の上で測る
    func testTextContrastMeetsAA() {
        for (theme, grounds) in [(NCTheme.dark, [NCColor.bgNight, .bgBase, .surface]), (.light, [.bgBase, .surface])] {
            for fg in [NCColor.textMain, .textSub, .accentFactor, .accentResult] {
                for bg in grounds {
                    XCTAssertGreaterThanOrEqual(ratio(fg, bg, theme), 4.5, "\(fg) on \(bg) (\(theme))")
                }
            }
        }
    }

    // 操作の輪郭は 3:1 以上(bg-base と surface の上)
    func testControlBorderMeets3to1() {
        for theme in NCTheme.allCases {
            for bg in [NCColor.bgBase, .surface] {
                XCTAssertGreaterThanOrEqual(ratio(.borderControl, bg, theme), 3.0, "\(bg) (\(theme))")
            }
        }
    }

    // 選択状態の面(tint)の上でも、accent の文字は 4.5:1 以上
    func testAccentOnTintMeetsAA() {
        for theme in NCTheme.allCases {
            let pairs: [(NCColor, NCColor)] = [(.accentFactor, .factorTint), (.accentResult, .resultTint)]
            for (fg, tint) in pairs {
                for ground in [NCColor.bgBase, .surface] {
                    let bg = NCContrast.over(tint.rgba(theme), ground.rgba(theme))
                    let r = NCContrast.ratio(fg.rgba(theme), bg)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(fg) on \(tint) over \(ground) (\(theme))")
                }
            }
        }
    }

    // accent の塗りの上の文字(on-accent)も 4.5:1 以上
    func testOnAccentMeetsAA() {
        for theme in NCTheme.allCases {
            for accent in [NCColor.accentFactor, .accentResult] {
                XCTAssertGreaterThanOrEqual(NCContrast.ratio(NCColor.onAccent.rgba(theme), accent.rgba(theme)), 4.5, "\(accent) (\(theme))")
            }
        }
    }

    // 純白と純黒は使わない
    func testNoPureWhiteOrBlackText() {
        for theme in NCTheme.allCases {
            for c in [NCColor.textMain, .textSub, .surface, .bgBase] {
                let x = c.rgba(theme)
                XCTAssertFalse(x.r == 1 && x.g == 1 && x.b == 1, "\(c) (\(theme)) が純白")
                XCTAssertFalse(x.r == 0 && x.g == 0 && x.b == 0, "\(c) (\(theme)) が純黒")
            }
        }
    }

    // 夜の背景は、ライトでもダークと同じ値(夜の画面はダーク固定)
    func testNightBackgroundIsTheSameInBothThemes() {
        XCTAssertEqual(NCColor.bgNight.rgba(.dark), NCColor.bgNight.rgba(.light))
    }

    // 別名(on-accent、focus-ring)が、テーマごとに解決されている
    func testAliasesResolvePerTheme() {
        XCTAssertEqual(NCColor.focusRing.rgba(.dark), NCColor.accentResult.rgba(.dark))
        XCTAssertEqual(NCColor.focusRing.rgba(.light), NCColor.accentResult.rgba(.light))
        XCTAssertEqual(NCColor.onAccent.rgba(.dark), NCColor.bgNight.rgba(.dark))
        XCTAssertEqual(NCColor.onAccent.rgba(.light), NCColor.surface.rgba(.light))
    }

    // タップ領域は 44pt 以上、夜の動きは 400ms 以上
    func testSizesAndMotion() {
        XCTAssertGreaterThanOrEqual(NCSize.tapMin, 44)
        XCTAssertGreaterThanOrEqual(NCSize.stockD, 44)
        XCTAssertGreaterThanOrEqual(NCDuration.fadeNight, 0.4)
        XCTAssertEqual(NCDuration.fadeNight, 0.6, accuracy: 1e-9)
        XCTAssertEqual(NCSpace.s4, 16)
    }

    // 文字の最小は 11pt
    func testMinimumFontSize() {
        let styles: [NCTextStyle] = [NCText.title, NCText.headline, NCText.body, NCText.footnote, NCText.caption, NCText.numHero, NCText.numLg, NCText.numMd, NCText.numSm, NCText.numXs]
        for s in styles {
            XCTAssertGreaterThanOrEqual(s.size, 11)
        }
    }
}
