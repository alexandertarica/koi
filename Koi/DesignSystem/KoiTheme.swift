import SwiftUI

enum KoiTheme {
    static let onBase = Color(red: 0xF0 / 255, green: 0xE8 / 255, blue: 0xDB / 255)
    static let onBaseMuted = onBase.opacity(0.92)
    static let deepWater = Color(red: 0x2B / 255, green: 0x40 / 255, blue: 0x67 / 255)
    static let glassInk = Color(red: 0x21 / 255, green: 0x33 / 255, blue: 0x52 / 255)
    static let caution = Color(red: 0x99 / 255, green: 0x4D / 255, blue: 0x33 / 255)
    static let divider = onBase.opacity(0.3)

    static let title = Font.custom("RobotoMono-Light", size: 24, relativeTo: .title)
    static let body = Font.custom("RobotoMono-Regular", size: 15, relativeTo: .body)
    static let caption = Font.custom("RobotoMono-Regular", size: 12, relativeTo: .caption)
    static let section = Font.custom("RobotoMono-Regular", size: 12, relativeTo: .caption)
    static let hero = Font.custom("KOINumerals", size: 48, relativeTo: .largeTitle)

    struct Space {
        let s3: CGFloat = 3
        let s5: CGFloat = 5
        let s8: CGFloat = 8
        let s13: CGFloat = 13
        let s21: CGFloat = 21
        let s34: CGFloat = 34
        let s55: CGFloat = 55
        let s89: CGFloat = 89
    }
    static let space = Space()
}
