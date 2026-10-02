import Foundation

/// Levhanın vadeye göre durumu (öncelik çarpanı için).
public enum VadeDurumu: Equatable {
    case hicCalisilmamis, gecmis, bugun, gelecek

    public var carpan: Double {
        switch self {
        case .hicCalisilmamis, .gecmis: return 1.0
        case .bugun: return 0.9
        case .gelecek: return 0.3
        }
    }

    public static func hesapla(_ d: ZamanDurumu?, simdi: Date, takvim: Calendar) -> VadeDurumu {
        guard let sonraki = d?.sonrakiTarih else { return .hicCalisilmamis }
        let bugun = Zamanlayici.calismaGunu(simdi, takvim: takvim)
        if sonraki < bugun { return .gecmis }
        if sonraki == bugun { return .bugun }
        return .gelecek
    }
}

public enum Oncelik {
    /// Kazanımı olmayan levhanın sorulabilirliği.
    public static let varsayilanSorulabilirlik = 0.6

    /// Ders soru sayısı / 30, 0,3–1,0 arasına sıkıştırılır.
    public static func dersAgirligi(soruSayisi: Int) -> Double {
        min(1.0, max(0.3, Double(soruSayisi) / 30))
    }

    /// Levha kazanımlarının sorulabilirlik ortalaması / 5 (kazanım yoksa 0,6).
    public static func sorulabilirlik(_ puanlar: [Int]) -> Double {
        guard !puanlar.isEmpty else { return varsayilanSorulabilirlik }
        return Double(puanlar.reduce(0, +)) / Double(puanlar.count) / 5
    }

    /// öncelik = dersAğırlığı × sorulabilirlik × (1 − sağlamlık/100) × vadeÇarpanı
    public static func puan(dersSoruSayisi: Int, sorulabilirlikler: [Int], saglamlik: Double, vade: VadeDurumu) -> Double {
        dersAgirligi(soruSayisi: dersSoruSayisi)
            * sorulabilirlik(sorulabilirlikler)
            * (1 - min(100, max(0, saglamlik)) / 100)
            * vade.carpan
    }
}

/// Bir dersin tahmini neti.
public struct NetTahmini: Equatable {
    public var beklenen: Double
    public var alt: Double
    public var ust: Double
    /// Hesaba giren soru sayısı.
    public var n: Int
    public var yetersiz: Bool
}

public enum NetHesabi {
    /// Sınavdaki sorulabilirlik tabakası payları.
    public static let tabakaPaylari: [Int: Double] = [5: 0.35, 4: 0.30, 3: 0.20, 2: 0.10, 1: 0.05]
    public static let enAzSoru = 30

    /// `cevaplar`: (sorulabilirlik 1–5, doğru mu). `N`: sınavda bu dersin soru sayısı. `ceza`: yanlış başına net kaybı.
    /// Beklenen = N·Σ p_s·d_s − N·Σ p_s·(1−d_s)·ceza. Aralık: ±1 SS; doğruluk tahmininin binom
    /// standart hatası toplam veri sayısından hesaplanır.
    public static func tahmin(cevaplar: [(sorulabilirlik: Int, dogru: Bool)], N: Int, ceza: Double) -> NetTahmini {
        let n = cevaplar.count
        guard n > 0 else { return NetTahmini(beklenen: 0, alt: 0, ust: 0, n: 0, yetersiz: true) }
        var sayac: [Int: (dogru: Int, toplam: Int)] = [:]
        for c in cevaplar {
            let s = min(5, max(1, c.sorulabilirlik))
            let e = sayac[s] ?? (0, 0)
            sayac[s] = (e.dogru + (c.dogru ? 1 : 0), e.toplam + 1)
        }
        // Tabaka doğruluğu; verisi olmayan tabaka en yakın komşudan (eşitlikte üstteki) alınır.
        func dogruluk(_ s: Int) -> Double {
            for uzaklik in 0...4 {
                for aday in [s + uzaklik, s - uzaklik] where (1...5).contains(aday) {
                    if let e = sayac[aday], e.toplam > 0 { return Double(e.dogru) / Double(e.toplam) }
                }
            }
            return 0
        }
        var p = 0.0
        for (s, pay) in tabakaPaylari { p += pay * dogruluk(s) }
        let netOrani = p - (1 - p) * ceza
        let beklenen = Double(N) * netOrani
        let ss = Double(N) * (1 + ceza) * (p * (1 - p) / Double(n)).squareRoot()
        let enAz = -Double(N) * ceza
        return NetTahmini(beklenen: beklenen,
                          alt: max(enAz, beklenen - ss),
                          ust: min(Double(N), beklenen + ss),
                          n: n,
                          yetersiz: n < enAzSoru)
    }

    /// Tahmin etmenin beklenen değeri sıfır olan doğruluk: ceza / (1 + ceza).
    public static func tahminEsigi(ceza: Double) -> Double { ceza / (1 + ceza) }
}
