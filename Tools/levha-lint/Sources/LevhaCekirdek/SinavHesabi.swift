import Foundation

/// Mini sınav: net ve tahmin politikası.
public enum TahminPolitikasi {
    /// Şans düzeyi (5 şık).
    public static let sans = 0.2
    /// Az veride doğruluk şansa doğru büzülür: (d + k·0,2) / (n + k).
    public static let onselAgirlik = 5.0

    public static func net(dogru: Int, yanlis: Int, ceza: Double) -> Double {
        Double(dogru) - Double(yanlis) * ceza
    }

    /// "Tahmin" işaretli cevapların büzülmüş doğruluğu.
    public static func dogruluk(dogru: Int, toplam: Int) -> Double {
        (Double(dogru) + onselAgirlik * sans) / (Double(max(0, toplam)) + onselAgirlik)
    }

    /// Boş bırakılan N soruda tahmin edilseydi net değişimi: beklenen N·(p − (1−p)·ceza);
    /// soru başına sonuç +1 ya da −ceza olduğundan SS = (1 + ceza)·√(N·p·(1−p)).
    public static func bosBeklenenDegisim(bosSayisi: Int, dogruluk p: Double, ceza: Double) -> (beklenen: Double, ss: Double) {
        let n = Double(max(0, bosSayisi))
        let q = min(1, max(0, p))
        return (n * (q - (1 - q) * ceza), (1 + ceza) * (n * q * (1 - q)).squareRoot())
    }
}

/// A/B deneyi: iki oranın farkı ve iki yönlü z-testi.
public struct OranKarsilastirmasi: Equatable {
    public var p1: Double
    public var p2: Double
    public var fark: Double
    public var z: Double
    public var pDegeri: Double
    /// İki gruptan biri `ABTesti.enAzOrneklem`'in altında.
    public var yetersiz: Bool
}

public enum ABTesti {
    public static let enAzOrneklem = 30

    /// z = (p1 − p2) / √(p̂(1−p̂)(1/n1 + 1/n2)), p̂ birleşik oran; p = erfc(|z|/√2). Örneklem 0 ise nil.
    public static func ikiOran(d1: Int, n1: Int, d2: Int, n2: Int) -> OranKarsilastirmasi? {
        guard n1 > 0, n2 > 0 else { return nil }
        let p1 = Double(d1) / Double(n1), p2 = Double(d2) / Double(n2)
        let birlesik = Double(d1 + d2) / Double(n1 + n2)
        let se = (birlesik * (1 - birlesik) * (1 / Double(n1) + 1 / Double(n2))).squareRoot()
        let z = se > 0 ? (p1 - p2) / se : 0
        return OranKarsilastirmasi(p1: p1, p2: p2, fark: p1 - p2, z: z, pDegeri: erfc(abs(z) / 2.0.squareRoot()),
                                   yetersiz: n1 < enAzOrneklem || n2 < enAzOrneklem)
    }
}
