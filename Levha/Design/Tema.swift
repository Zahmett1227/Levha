import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Sabit tasarım dili. Renk anlam taşır; tüm derslerde aynıdır.
enum Tema {
    static let arkaPlan = Color(hex: 0xF4F6F8)
    static let metin = Color(hex: 0x15202B)
    static let ikincil = Color(hex: 0x4A5664)
    static let kartKenar = Color(hex: 0xDCE2E9)
    static let cizgi = Color(hex: 0x9AA5B1)
    static let maskeZemin = Color(hex: 0xF1F3F5)
    static let kartKose: CGFloat = 16
}

struct RenkSeti {
    let kenar: Color
    let zemin: Color
    let yazi: Color

    static let kirmizi = RenkSeti(kenar: Color(hex: 0xC8372D), zemin: Color(hex: 0xFBEAE8), yazi: Color(hex: 0xA12A22))
    static let mavi = RenkSeti(kenar: Color(hex: 0x2F6FB3), zemin: Color(hex: 0xE8F0FA), yazi: Color(hex: 0x24578F))
    static let yesil = RenkSeti(kenar: Color(hex: 0x2E8B57), zemin: Color(hex: 0xE6F4EC), yazi: Color(hex: 0x1E6B42))
    static let sari = RenkSeti(kenar: Color(hex: 0xC98F0A), zemin: Color(hex: 0xFCF3DC), yazi: Color(hex: 0x8A6106))
    static let gri = RenkSeti(kenar: Color(hex: 0x9AA5B1), zemin: Color(hex: 0xF1F3F5), yazi: Color(hex: 0x4A5664))

    static func ad(_ ad: String) -> RenkSeti {
        switch RenkAdi(rawValue: ad) {
        case .kirmizi: return .kirmizi
        case .mavi: return .mavi
        case .yesil: return .yesil
        case .sari: return .sari
        case .gri, .none: return .gri
        }
    }
}

enum Bicim {
    static let tr = Locale(identifier: "tr_TR")

    static func sayi(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(tr))
    }

    static func tarih(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(tr))
    }
}

/// Levha kartı: beyaz, 1 px #DCE2E9 kenarlık, 16 px köşe.
struct KartArkaPlani: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white, in: RoundedRectangle(cornerRadius: Tema.kartKose, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.kartKose, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
    }
}

extension View {
    func levhaKarti() -> some View { modifier(KartArkaPlani()) }
}

/// Kelime ortasından bölünmeyi önler: en uzun kelime verilen genişliğe sığacak kadar puntoyu küçültür.
/// Ölçüm yalnız metne ve genişliğe bağlı olduğundan aynı levha her açılışta aynı görünür.
enum Sigdir {
    static func font(_ metin: String, temel: CGFloat, genislik: CGFloat, agirlik: UIFont.Weight, enAz: CGFloat = 8.5) -> Font {
        Font(UIFont.systemFont(ofSize: punto(metin, temel: temel, genislik: genislik, agirlik: agirlik, enAz: enAz), weight: agirlik))
    }

    static func punto(_ metin: String, temel: CGFloat, genislik: CGFloat, agirlik: UIFont.Weight, enAz: CGFloat = 8.5) -> CGFloat {
        let font = UIFont.systemFont(ofSize: temel, weight: agirlik)
        let enUzun = metin.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        guard genislik > 0, enUzun > genislik else { return temel }
        return max(enAz, (temel * genislik / enUzun * 10).rounded(.down) / 10)
    }
}
