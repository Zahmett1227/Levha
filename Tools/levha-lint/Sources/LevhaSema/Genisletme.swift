import Foundation

/// "Bu levhayı genişlet" taslaklarının şema denetimi. Yalnız ızgara tipleri (algoritma, yolak, ağaç) genişler.
public enum LevhaGenisletme {
    public static let dugumAraligi = 2...5

    /// Izgaradaki boş konumlar ([sütun, satır]); 2'den az boş yer varsa ızgaraya bir satır eklenmiş gibi
    /// alt satırın konumları da verilir.
    public static func bosKonumlar(izgara: [Int], dolu: [[Int]]) -> [[Int]] {
        guard izgara.count == 2 else { return [] }
        let dolular = Set(dolu.filter { $0.count == 2 }.map { "\($0[0]),\($0[1])" })
        var bos: [[Int]] = []
        for r in 0..<izgara[1] {
            for c in 0..<izgara[0] where !dolular.contains("\(c),\(r)") { bos.append([c, r]) }
        }
        if bos.count < dugumAraligi.lowerBound {
            bos += (0..<izgara[0]).map { [$0, izgara[1]] }
        }
        return bos
    }

    /// Taslağı levhaya ekler, ızgarayı gerekirse büyütür ve lint kurallarından geçirir.
    /// Dönen `hatalar` boşsa taslak geçerlidir.
    public static func dogrula(_ levha: LevhaJSON, ek: GenisletmeJSON, bosKonumlar: [[Int]]) -> (birlesik: LevhaJSON, hatalar: [String]) {
        var h: [String] = []
        guard levha.tip.izgaraTabanli else { return (levha, ["\(levha.tip.ad) levhası genişletilemez"]) }
        if !dugumAraligi.contains(ek.dugumler.count) {
            h.append("\(dugumAraligi.lowerBound)–\(dugumAraligi.upperBound) düğüm bekleniyor (\(ek.dugumler.count) var)")
        }
        let mevcut = Set(LevhaLint.dugumKimlikleri(levha))
        let bos = Set(bosKonumlar.map { "\($0.first ?? -1),\($0.last ?? -1)" })
        var yeniIdler = Set<String>()
        for d in ek.dugumler {
            if mevcut.contains(d.id) || !yeniIdler.insert(d.id).inserted { h.append("\(d.id): id zaten var") }
            if LevhaLint.bos(d.etiket) { h.append("\(d.id): etiket boş") }
            if d.etiket.count > LevhaLint.etiketSiniri { h.append("\(d.id): etiket \(d.etiket.count) karakter (en fazla \(LevhaLint.etiketSiniri))") }
            guard let k = d.konum, k.count == 2 else {
                h.append("\(d.id): konum [sütun, satır] zorunlu")
                continue
            }
            if !bos.contains("\(k[0]),\(k[1])") { h.append("\(d.id): [\(k[0]), \(k[1])] boş konum listesinde değil") }
        }
        let tum = mevcut.union(yeniIdler)
        for (i, b) in (ek.baglantilar ?? []).enumerated() {
            if !tum.contains(b.from) || !tum.contains(b.to) { h.append("baglantilar[\(i)]: bilinmeyen düğüm (\(b.from) → \(b.to))") }
            if !yeniIdler.contains(b.from) && !yeniIdler.contains(b.to) { h.append("baglantilar[\(i)]: yeni bir düğüme bağlanmalı") }
        }

        var birlesik = levha
        birlesik.dugumler = (levha.dugumler ?? []) + ek.dugumler
        birlesik.baglantilar = (levha.baglantilar ?? []) + (ek.baglantilar ?? [])
        if var izgara = levha.duzen?.izgara, izgara.count == 2 {
            for d in ek.dugumler {
                guard let k = d.konum, k.count == 2 else { continue }
                izgara[0] = max(izgara[0], k[0] + 1)
                izgara[1] = max(izgara[1], k[1] + 1)
            }
            birlesik.duzen = DuzenJSON(izgara: izgara, sabit: levha.duzen?.sabit)
        }
        // Birleşik levhadaki engelleyici bulgular (çakışma, bilinmeyen bağlantı ucu...) taslağı geçersiz kılar.
        for bulgu in LevhaLint.levhaDenetle(birlesik, yer: "levha", surum: 4) where bulgu.engelleyici {
            h.append(bulgu.description)
        }
        return (birlesik, h)
    }
}
