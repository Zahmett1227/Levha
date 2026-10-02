import Foundation

/// Ayarlar › Sınav dağılımı. Ders ağırlığı paketten değil buradan gelir.
enum SinavAyarlari {
    static let varsayilanDagilim: [String: Int] = [
        "Pediatri": 30, "Dahiliye": 30, "Genel Cerrahi": 20, "Kadın-Doğum": 20, "Küçük Stajlar": 20,
        "Anatomi": 14, "Fizyoloji": 13, "Biyokimya": 11, "Mikrobiyoloji": 15, "Patoloji": 20, "Farmakoloji": 20,
    ]
    /// Tabloda olmayan bir dersin varsayılan soru sayısı.
    static let bilinmeyenDers = 20
    static let varsayilanCeza = 0.25

    private static let dagilimAnahtari = "sinavDagilimi"
    private static let cezaAnahtari = "yanlisCeza"

    static var dagilim: [String: Int] {
        get {
            guard let veri = UserDefaults.standard.data(forKey: dagilimAnahtari),
                  let d = try? JSONDecoder().decode([String: Int].self, from: veri) else { return varsayilanDagilim }
            return d
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: dagilimAnahtari) }
    }

    static var ceza: Double {
        get { UserDefaults.standard.object(forKey: cezaAnahtari) as? Double ?? varsayilanCeza }
        set { UserDefaults.standard.set(newValue, forKey: cezaAnahtari) }
    }

    static func soruSayisi(_ ders: String) -> Int { dagilim[ders] ?? bilinmeyenDers }

    /// Tablonun gösterim sırası: varsayılan dersler sabit sırada, sonra pakette olup tabloda olmayanlar.
    static let sira = ["Pediatri", "Dahiliye", "Genel Cerrahi", "Kadın-Doğum", "Küçük Stajlar",
                       "Anatomi", "Fizyoloji", "Biyokimya", "Mikrobiyoloji", "Patoloji", "Farmakoloji"]
}
