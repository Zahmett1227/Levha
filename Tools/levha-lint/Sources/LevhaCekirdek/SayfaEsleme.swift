import Foundation

/// Eşlemeye giren levha özeti.
public struct EslemeAdayi: Equatable {
    public var id: String
    public var anahtarKelimeler: [String]
    public var baslik: String
    public var etiketler: [String]

    public init(id: String, anahtarKelimeler: [String], baslik: String, etiketler: [String]) {
        self.id = id
        self.anahtarKelimeler = anahtarKelimeler
        self.baslik = baslik
        self.etiketler = etiketler
    }
}

public struct EslemeSonucu: Equatable {
    public var id: String
    /// 0–1
    public var skor: Double
}

/// Kitap sayfası (OCR metni) → levha eşlemesi. Tamamen cihazda.
public enum SayfaEsleme {
    /// Bunun altındaki en iyi skor "eşleşme yok" sayılır.
    public static let esik = 0.15
    public static let agirliklar = (anahtar: 3, baslik: 2, etiket: 1)

    /// Sık geçen bağlaç/edat; her sayfada geçtikleri için eşlemeye katılmaz.
    static let durakKelimeler: Set<String> = ["ile", "icin", "veya", "gibi", "olan", "daha", "cok", "bir", "ama", "kadar", "sonra", "once", "her", "the", "and"]

    /// Küçük harf (Türkçe kurallı), diakritik katlama (ç→c, ı→i...), yalnız harflerden oluşan 3+ harfli kelimeler.
    /// Türkçe ek kırpması yapılmaz: "sarılığı" ile "sarılık" eşleşmez.
    public static func kelimeler(_ metin: String) -> [String] {
        let kucuk = metin.lowercased(with: Locale(identifier: "tr_TR"))
        let katli = String(kucuk.map { katla[$0] ?? $0 })
        return katli.split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 && !durakKelimeler.contains($0) }
    }

    private static let katla: [Character: Character] = [
        "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u",
    ]

    /// skor = (3·|anahtar ∩ sayfa| + 2·|başlık ∩ sayfa| + 1·|etiket ∩ sayfa|) / (3·|anahtar| + 2·|başlık| + |etiket|).
    /// Kümeler levhanın farklı kelimeleridir; payda levhanın ağırlıklı toplam kelime sayısıdır.
    public static func skor(_ aday: EslemeAdayi, sayfa: Set<String>) -> Double {
        let a = Set(aday.anahtarKelimeler.flatMap(kelimeler))
        let b = Set(kelimeler(aday.baslik))
        let e = Set(aday.etiketler.flatMap(kelimeler))
        let w = agirliklar
        let payda = w.anahtar * a.count + w.baslik * b.count + w.etiket * e.count
        guard payda > 0 else { return 0 }
        let pay = w.anahtar * a.intersection(sayfa).count + w.baslik * b.intersection(sayfa).count
            + w.etiket * e.intersection(sayfa).count
        return Double(pay) / Double(payda)
    }

    /// En iyi `ilk` levha, skora göre azalan; eşitlikte gelen sıra korunur. Skoru 0 olanlar elenir.
    public static func sirala(_ adaylar: [EslemeAdayi], ocr: String, ilk: Int = 5) -> [EslemeSonucu] {
        let sayfa = Set(kelimeler(ocr))
        return adaylar.enumerated()
            .map { (i: $0.offset, s: EslemeSonucu(id: $0.element.id, skor: skor($0.element, sayfa: sayfa))) }
            .filter { $0.s.skor > 0 }
            .sorted { ($0.s.skor, -$0.i) > ($1.s.skor, -$1.i) }
            .prefix(ilk)
            .map(\.s)
    }

    /// Hiçbir levha eşiği geçmiyorsa true.
    public static func eslesmeYok(_ sonuclar: [EslemeSonucu]) -> Bool {
        (sonuclar.first?.skor ?? 0) < esik
    }
}
