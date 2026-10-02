import Foundation

/// İpucu avı puanı. Ağırlıklar kartların gösterim (kök) sırasındadır; `acilan` açılmış kart sayısıdır.
public enum IpucuPuani {
    public static let yanlisPuani = -25
    public static let yanilticiOdulu = 10

    /// Doğruysa açılmamış kartların ağırlık toplamı / toplam ağırlık × 100 (erken bilen yüksek alır);
    /// yanlışsa −25. Tüm ağırlıklar 0 ise ağırlık yerine kart sayısı kullanılır.
    public static func temel(agirliklar: [Int], acilan: Int, dogru: Bool) -> Int {
        guard dogru else { return yanlisPuani }
        guard !agirliklar.isEmpty else { return 0 }
        let a = min(max(acilan, 0), agirliklar.count)
        let w = agirliklar.map { max(0, $0) }
        let toplam = w.reduce(0, +)
        let oran = toplam > 0
            ? Double(w[a...].reduce(0, +)) / Double(toplam)
            : Double(agirliklar.count - a) / Double(agirliklar.count)
        return Int((oran * 100).rounded())
    }

    /// Uzun basışla "yanıltıcı" işaretlenen her kart: gerçekten yanıltıcıysa +10, değilse −10.
    public static func yanilticiPuani(isaretlenen: Set<Int>, yanilticilar: Set<Int>) -> Int {
        isaretlenen.reduce(0) { $0 + (yanilticilar.contains($1) ? yanilticiOdulu : -yanilticiOdulu) }
    }

    public static func toplam(agirliklar: [Int], acilan: Int, dogru: Bool, isaretlenen: Set<Int>, yanilticilar: Set<Int>) -> Int {
        temel(agirliklar: agirliklar, acilan: acilan, dogru: dogru)
            + yanilticiPuani(isaretlenen: isaretlenen, yanilticilar: yanilticilar)
    }

    /// Kartların gösterim sırası: ipucu metninin kökte ilk geçtiği yere göre (bulunamayan sona).
    public static func kokSirasi(kok: String, metinler: [String]) -> [Int] {
        let konumlar = metinler.map { m -> Int in
            guard !m.isEmpty, let r = kok.range(of: m) else { return Int.max }
            return kok.distance(from: kok.startIndex, to: r.lowerBound)
        }
        return metinler.indices.sorted { (konumlar[$0], $0) < (konumlar[$1], $1) }
    }

    /// Kökün son cümlesi (soru cümlesi): son ". " / "? " sonrası.
    public static func soruCumlesi(_ kok: String) -> String {
        let metin = kok.trimmingCharacters(in: .whitespacesAndNewlines)
        let govde = metin.hasSuffix("?") ? String(metin.dropLast()) : metin
        guard let r = govde.range(of: ". ", options: .backwards) else { return metin }
        return String(metin[r.upperBound...])
    }
}

/// Soru kırma: kalıp + ipucu tahmininden yanlışın türü.
public enum KirmaSinifi: String, CaseIterable {
    /// Kalıbı doğru okudu, cevabı yine bilemedi.
    case bilgiEksigi
    /// Kalıbı yanlış okudu (ya da süre doldu) ve yanlış cevapladı.
    case okumaEksigi

    public var ad: String {
        switch self {
        case .bilgiEksigi: return "Bilgi eksiği"
        case .okumaEksigi: return "Okuma eksiği"
        }
    }

    /// Doğru cevapta sınıf yok. Kalıp seçilmeden süre dolduysa (`kalipTahmini == nil`) okuma eksiği sayılır.
    public static func sinifla(kalipTahmini: String?, gercekKalip: String?, cevapDogru: Bool) -> KirmaSinifi? {
        guard !cevapDogru else { return nil }
        return kalipTahmini != nil && kalipTahmini == gercekKalip ? .bilgiEksigi : .okumaEksigi
    }

    /// Kırılım: kökteki ipucu metni yenisiyle değişir; dönen aralık yeni metnin yeri.
    public static func kirilimKoku(kok: String, eski: String, yeni: String) -> (metin: String, aralik: Range<String.Index>)? {
        guard let r = kok.range(of: eski) else { return nil }
        let metin = kok.replacingCharacters(in: r, with: yeni)
        let bas = metin.index(metin.startIndex, offsetBy: kok.distance(from: kok.startIndex, to: r.lowerBound))
        let son = metin.index(bas, offsetBy: yeni.count)
        return (metin, bas..<son)
    }
}
