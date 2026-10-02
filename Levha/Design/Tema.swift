import SwiftUI

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

    // Hex değerleri Ortak/WidgetAnligi.swift'teki RenkPaleti'nde (widget da kullanır).
    static let kirmizi = RenkSeti(paletten: "kirmizi")
    static let mavi = RenkSeti(paletten: "mavi")
    static let yesil = RenkSeti(paletten: "yesil")
    static let sari = RenkSeti(paletten: "sari")
    static let gri = RenkSeti(paletten: "gri")

    init(kenar: Color, zemin: Color, yazi: Color) {
        self.kenar = kenar
        self.zemin = zemin
        self.yazi = yazi
    }

    private init(paletten ad: String) {
        let h = RenkPaleti.hex(ad)
        self.init(kenar: Color(hex: h.kenar), zemin: Color(hex: h.zemin), yazi: Color(hex: h.yazi))
    }

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

    private static let kilit = NSLock()
    nonisolated(unsafe) private static var onbellek: [String: CGFloat] = [:]

    /// Ölçüm sonucu metin+punto+genişlik+ağırlık için önbelleğe alınır (kaydırırken her sayfada yeniden ölçülmesin).
    static func punto(_ metin: String, temel: CGFloat, genislik: CGFloat, agirlik: UIFont.Weight, enAz: CGFloat = 8.5) -> CGFloat {
        let anahtar = "\(metin)|\(temel)|\((genislik * 2).rounded())|\(agirlik.rawValue)|\(enAz)"
        kilit.lock()
        if let v = onbellek[anahtar] { kilit.unlock(); return v }
        kilit.unlock()
        let v = olc(metin, temel: temel, genislik: genislik, agirlik: agirlik, enAz: enAz)
        kilit.lock()
        if onbellek.count > 20_000 { onbellek.removeAll() }
        onbellek[anahtar] = v
        kilit.unlock()
        return v
    }

    private static func olc(_ metin: String, temel: CGFloat, genislik: CGFloat, agirlik: UIFont.Weight, enAz: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: temel, weight: agirlik)
        let enUzun = metin.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // SwiftUI satır kırma ölçümü NSString'den biraz geniş; %8 pay bırak.
        let hedef = genislik * 0.92
        guard hedef > 0, enUzun > hedef else { return temel }
        return max(enAz, (temel * hedef / enUzun * 10).rounded(.down) / 10)
    }
}
