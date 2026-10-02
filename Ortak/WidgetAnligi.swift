import SwiftUI

// Uygulama ile widget arasında paylaşılan küçük veri. Uygulama her Örtme/Soru/Sabotaj/İnşa olayından
// sonra App Group'a `widget-snapshot.json` yazar; widget yalnız bunu okur (SwiftData'ya dokunmaz).

struct WidgetAnligi: Codable {
    var olusturma: Date
    var tamamlananDakika: Int
    var planlananDakika: Int
    var vadeliSayisi: Int
    /// Önceliğe göre sıralı, vadesi gelmiş levhalar (saatlik timeline sırayla dolaşır).
    var levhalar: [WidgetLevhasi]

    static let ornek = WidgetAnligi(
        olusturma: .now, tamamlananDakika: 35, planlananDakika: 60, vadeliSayisi: 4,
        levhalar: [WidgetLevhasi(id: "ornek", baslik: "Yenidoğan sarılığına yaklaşım", altKonu: "Yenidoğan sarılığı",
                                 oran: 1.7, maskeli: "b",
                                 kutular: [
                                    WidgetKutusu(id: "a", x: 0.36, y: 0.04, w: 0.28, h: 0.18, renk: "mavi", kose: 0.15),
                                    WidgetKutusu(id: "b", x: 0.04, y: 0.30, w: 0.28, h: 0.18, renk: "kirmizi", kose: 0.15),
                                    WidgetKutusu(id: "c", x: 0.36, y: 0.30, w: 0.28, h: 0.18, renk: "mavi", kose: 0.15),
                                    WidgetKutusu(id: "d", x: 0.68, y: 0.30, w: 0.28, h: 0.18, renk: "sari", kose: 0.15),
                                    WidgetKutusu(id: "e", x: 0.36, y: 0.56, w: 0.28, h: 0.18, renk: "yesil", kose: 0.5),
                                    WidgetKutusu(id: "f", x: 0.68, y: 0.56, w: 0.28, h: 0.18, renk: "mavi", kose: 0.15),
                                 ])])
}

struct WidgetLevhasi: Codable, Identifiable {
    var id: String
    var baslik: String
    var altKonu: String
    /// Çizim alanının en/boy oranı.
    var oran: Double
    var maskeli: String?
    var kutular: [WidgetKutusu]
}

/// 0–1 aralığına normalize edilmiş düğüm kutusu. `kose`: kısa kenara oranla köşe yarıçapı.
struct WidgetKutusu: Codable {
    var id: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var renk: String
    var kose: Double
}

enum WidgetDeposu {
    static let grup = "group.tr.kisisel.levha"
    static let dosyaAdi = "widget-snapshot.json"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup)?.appending(path: dosyaAdi)
    }

    static func oku() -> WidgetAnligi? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetAnligi.self, from: veri)
    }

    @discardableResult
    static func yaz(_ a: WidgetAnligi) -> Bool {
        guard let url else { return false }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let veri = try? e.encode(a) else { return false }
        return (try? veri.write(to: url, options: .atomic)) != nil
    }
}

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

/// Anlam taşıyan sabit palet: (kenar, zemin, yazı).
enum RenkPaleti {
    static func hex(_ ad: String) -> (kenar: UInt32, zemin: UInt32, yazi: UInt32) {
        switch ad {
        case "kirmizi": return (0xC8372D, 0xFBEAE8, 0xA12A22)
        case "mavi": return (0x2F6FB3, 0xE8F0FA, 0x24578F)
        case "yesil": return (0x2E8B57, 0xE6F4EC, 0x1E6B42)
        case "sari": return (0xC98F0A, 0xFCF3DC, 0x8A6106)
        default: return (0x9AA5B1, 0xF1F3F5, 0x4A5664)
        }
    }
}
