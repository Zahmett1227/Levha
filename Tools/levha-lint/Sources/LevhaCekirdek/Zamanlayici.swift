import Foundation

/// Bir levhanın tekrar durumu (değer tipi). SwiftData'daki `LevhaDurumu` bunun kalıcı karşılığıdır.
public struct ZamanDurumu: Equatable {
    public var levhaId: String
    /// 0...4; aralık = `Zamanlayici.araliklar[kutu]` gün.
    public var kutu: Int
    /// Vadenin geldiği çalışma gününün başlangıcı.
    public var sonrakiTarih: Date?
    /// 0...100
    public var saglamlik: Double
    public var sonGorulme: Date?

    public init(levhaId: String, kutu: Int = 0, sonrakiTarih: Date? = nil, saglamlik: Double = 0, sonGorulme: Date? = nil) {
        self.levhaId = levhaId
        self.kutu = kutu
        self.sonrakiTarih = sonrakiTarih
        self.saglamlik = saglamlik
        self.sonGorulme = sonGorulme
    }
}

/// Leitner benzeri kutu sistemi. Saf fonksiyonlar; zaman ve takvim dışarıdan verilir.
public enum Zamanlayici {
    public static let araliklar = [1, 3, 7, 14, 30]
    public static let basariEsigi = 0.8
    /// Gün 04:00'te döner: gece çalışması bir önceki güne sayılır.
    public static let gunDonumuSaati = 4

    public static func calismaGunu(_ tarih: Date, takvim: Calendar) -> Date {
        let kaydirilmis = takvim.date(byAdding: .hour, value: -gunDonumuSaati, to: tarih) ?? tarih
        return takvim.startOfDay(for: kaydirilmis)
    }

    /// "yyyy-MM-dd" — tohumlar ve günlük tur kaydı için.
    public static func gunAnahtari(_ tarih: Date, takvim: Calendar) -> String {
        let c = takvim.dateComponents([.year, .month, .day], from: calismaGunu(tarih, takvim: takvim))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Örtme sonucu: açılanların ≥%80'i bilindiyse kutu +1, değilse −1 (0–4 arasında kalır).
    public static func ortmeSonucu(_ d: ZamanDurumu, bildim: Int, toplam: Int, simdi: Date, takvim: Calendar) -> ZamanDurumu {
        guard toplam > 0 else { return d }
        var y = d
        let oran = Double(bildim) / Double(toplam)
        y.kutu = oran >= basariEsigi ? min(d.kutu + 1, araliklar.count - 1) : max(d.kutu - 1, 0)
        y.sonrakiTarih = takvim.date(byAdding: .day, value: araliklar[y.kutu], to: calismaGunu(simdi, takvim: takvim))
        y.sonGorulme = simdi
        return y
    }

    /// Vadesi gelmiş: sonraki tarih bugün ya da geçmişte, veya levha hiç çalışılmamış.
    public static func vadeliMi(_ d: ZamanDurumu?, simdi: Date, takvim: Calendar) -> Bool {
        guard let sonraki = d?.sonrakiTarih else { return true }
        return sonraki <= calismaGunu(simdi, takvim: takvim)
    }

    /// Sağlamlık = 0,45·Örtme (son 3 oturum) + 0,3·Soru (son 10) + 0,15·Sabotaj bulma (son 10) + 0,1·İnşa (son 3).
    /// Verisi olmayan bileşenin ağırlığı diğerlerine dağıtılır; hiç veri yoksa 0.
    /// Oranlar 0–1; dizilerde en yeni öğe sondadır.
    public static func saglamlik(ortmeOranlari: [Double], soruSonuclari: [Bool], sabotajSonuclari: [Bool],
                                 insaOranlari: [Double] = []) -> Double {
        var bilesenler: [(agirlik: Double, deger: Double)] = []
        let ortme = ortmeOranlari.suffix(3)
        if !ortme.isEmpty { bilesenler.append((0.45, ortme.reduce(0, +) / Double(ortme.count) * 100)) }
        let soru = soruSonuclari.suffix(10)
        if !soru.isEmpty { bilesenler.append((0.3, Double(soru.filter { $0 }.count) / Double(soru.count) * 100)) }
        let sabotaj = sabotajSonuclari.suffix(10)
        if !sabotaj.isEmpty { bilesenler.append((0.15, Double(sabotaj.filter { $0 }.count) / Double(sabotaj.count) * 100)) }
        let insa = insaOranlari.suffix(3)
        if !insa.isEmpty { bilesenler.append((0.1, insa.reduce(0, +) / Double(insa.count) * 100)) }
        let toplamAgirlik = bilesenler.reduce(0) { $0 + $1.agirlik }
        guard toplamAgirlik > 0 else { return 0 }
        let deger = bilesenler.reduce(0) { $0 + $1.agirlik * $1.deger } / toplamAgirlik
        return min(100, max(0, (deger * 10).rounded() / 10))
    }
}

/// Tekrar üretilebilir rastgelelik: aynı tohum → aynı dizi (SplitMix64).
public struct TohumluUretec: RandomNumberGenerator {
    private var durum: UInt64

    public init(tohum: String) {
        // FNV-1a ile metni 64 bite indir.
        var h: UInt64 = 0xcbf29ce484222325
        for bayt in tohum.utf8 {
            h ^= UInt64(bayt)
            h = h &* 0x100000001b3
        }
        durum = h
    }

    public mutating func next() -> UInt64 {
        durum &+= 0x9E3779B97F4A7C15
        var z = durum
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0..<1
    public mutating func oran() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
