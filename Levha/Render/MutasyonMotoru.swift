import Foundation

/// Levhanın hatalı hâli ve hatanın ne olduğu.
struct SabotajSenaryosu: Equatable {
    let tip: SabotajTipi
    /// Doğru dokunuş sayılan düğümler.
    let hedef: [String]
    let dogrusu: String
    let yazilmis: Bool
    let cizim: LevhaCizim
}

/// Sabotaj üretimi: LLM yok, tip bazlı kurallar. Tohum = levhaId + gün + deneme → aynı gün aynı sabotaj.
enum MutasyonMotoru {
    static func sec(_ c: LevhaCizim, yazilmis: [SabotajJSON], tohum: String) -> SabotajSenaryosu? {
        var rng = TohumluUretec(tohum: tohum)
        let hazir = yazilmis.compactMap { uygula($0, c) }
        let yazilmisSec = !hazir.isEmpty && rng.oran() < 0.5
        if yazilmisSec { return hazir[Int(rng.next() % UInt64(hazir.count))] }
        return uret(c, rng: &rng) ?? hazir.first
    }

    // MARK: - Yazılmış sabotaj

    static func uygula(_ s: SabotajJSON, _ c: LevhaCizim) -> SabotajSenaryosu? {
        guard let tip = s.sabotajTipi, let levhaTipi = c.tip, tip.uygun(levhaTipi) else { return nil }
        let h = s.hedef ?? []
        guard h.count == tip.hedefSayisi, h.allSatisfy({ c.dugum($0) != nil }) else { return nil }
        var y = c
        let otomatik: String?
        switch tip {
        case .etiket_takas:
            otomatik = takasEt(&y, h[0], h[1], butun: false)
        case .hucre_takas:
            otomatik = takasEt(&y, h[0], h[1], butun: true)
        case .deger_kaydir:
            guard let v = s.yanlis_deger else { return nil }
            otomatik = degerKaydir(&y, h[0], v)
        case .renk_degistir:
            guard let r = s.yanlis_renk, RenkAdi(rawValue: r) != nil else { return nil }
            otomatik = renkDegistir(&y, h[0], r)
        case .baglanti_ters:
            otomatik = baglantiTersle(&y, h[0], h[1])
        case .sira_boz:
            otomatik = siraBoz(&y, h[0], h[1])
        case .bolge_kaydir:
            guard let b = s.yanlis_bolge.flatMap(VucutBolgesi.init(rawValue:)) else { return nil }
            otomatik = bolgeKaydir(&y, h[0], b)
        }
        guard let otomatik, y != c else { return nil }
        let metin = (s.dogrusu ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SabotajSenaryosu(tip: tip, hedef: h, dogrusu: metin.isEmpty ? otomatik : metin, yazilmis: true, cizim: y)
    }

    // MARK: - Üretilmiş sabotaj

    static func uret(_ c: LevhaCizim, rng: inout TohumluUretec) -> SabotajSenaryosu? {
        guard let tip = c.tip else { return nil }
        var kurallar: [SabotajTipi]
        switch tip {
        case .algoritma, .agac, .yolak: kurallar = [.etiket_takas, .baglanti_ters, .renk_degistir]
        case .matris: kurallar = [.hucre_takas]
        case .sayi_cetveli: kurallar = [.deger_kaydir]
        case .zaman_cizelgesi: kurallar = [.sira_boz, .deger_kaydir]
        case .vucut_haritasi: kurallar = [.bolge_kaydir]
        }
        kurallar.shuffle(using: &rng)
        for kural in kurallar {
            if let s = uret(kural, c, rng: &rng) { return s }
        }
        return nil
    }

    private static func uret(_ kural: SabotajTipi, _ c: LevhaCizim, rng: inout TohumluUretec) -> SabotajSenaryosu? {
        var y = c
        func senaryo(_ hedef: [String], _ dogrusu: String?) -> SabotajSenaryosu? {
            guard let dogrusu, y != c else { return nil }
            return SabotajSenaryosu(tip: kural, hedef: hedef, dogrusu: dogrusu, yazilmis: false, cizim: y)
        }
        switch kural {
        case .etiket_takas:
            // Aynı renk sınıfından iki düğüm: renk ipucu vermesin.
            let gruplar = Dictionary(grouping: c.dugumler, by: \.renkAdi).values
                .filter { Set($0.map(\.etiket)).count >= 2 }
                .sorted { $0[0].id < $1[0].id }
            guard !gruplar.isEmpty else { return nil }
            let grup = gruplar[Int(rng.next() % UInt64(gruplar.count))]
            let (a, b) = ikiFarkli(grup, rng: &rng) { $0.etiket != $1.etiket }
            guard let a, let b else { return nil }
            return senaryo([a.id, b.id], takasEt(&y, a.id, b.id, butun: false))

        case .hucre_takas:
            let sutunlar = Dictionary(grouping: c.dugumler, by: \.sutun).values
                .filter { Set($0.map(\.etiket)).count >= 2 }
                .sorted { $0[0].sutun < $1[0].sutun }
            guard !sutunlar.isEmpty else { return nil }
            let sutun = sutunlar[Int(rng.next() % UInt64(sutunlar.count))]
            let (a, b) = ikiFarkli(sutun, rng: &rng) { $0.etiket != $1.etiket }
            guard let a, let b else { return nil }
            return senaryo([a.id, b.id], takasEt(&y, a.id, b.id, butun: true))

        case .baglanti_ters:
            guard !c.baglantilar.isEmpty else { return nil }
            let b = c.baglantilar[Int(rng.next() % UInt64(c.baglantilar.count))]
            return senaryo([b.from, b.to], baglantiTersle(&y, b.from, b.to))

        case .renk_degistir:
            let karsit = ["kirmizi": "yesil", "yesil": "kirmizi", "mavi": "sari", "sari": "mavi"]
            let adaylar = c.dugumler.filter { karsit[$0.renkAdi] != nil }
            guard !adaylar.isEmpty else { return nil }
            let d = adaylar[Int(rng.next() % UInt64(adaylar.count))]
            return senaryo([d.id], renkDegistir(&y, d.id, karsit[d.renkAdi]!))

        case .deger_kaydir:
            let adaylar = c.dugumler.filter { $0.deger != nil }
            guard !adaylar.isEmpty else { return nil }
            let aralik = c.eksenMax - c.eksenMin
            let tamSayi = adaylar.allSatisfy { ($0.deger ?? 0).rounded() == $0.deger }
            for _ in 0..<12 {
                let d = adaylar[Int(rng.next() % UInt64(adaylar.count))]
                let v = d.deger ?? 0
                let oran = c.tip == .zaman_cizelgesi ? 0.3 : 0.2 + rng.oran() * 0.2
                let fark = v == 0 ? aralik * 0.15 : abs(v) * oran
                var yeni = rng.oran() < 0.5 ? v - fark : v + fark
                yeni = tamSayi ? yeni.rounded() : (yeni * 10).rounded() / 10
                yeni = min(c.eksenMax, max(c.eksenMin, yeni))
                if let bit = d.bit, yeni + (bit - v) > c.eksenMax { continue }
                guard abs(yeni - v) >= max(aralik * 0.03, tamSayi ? 1 : 0.1) else { continue }
                // Komşu işaretle çakışmasın.
                let cakisir = c.dugumler.contains { $0.id != d.id && $0.serit == d.serit && abs(($0.deger ?? .infinity) - yeni) < aralik * 0.03 }
                if cakisir { continue }
                return senaryo([d.id], degerKaydir(&y, d.id, yeni))
            }
            return nil

        case .sira_boz:
            let seritler = Dictionary(grouping: c.dugumler, by: { $0.serit ?? "" }).values
                .filter { Set($0.compactMap(\.deger)).count >= 2 }
                .sorted { ($0[0].serit ?? "") < ($1[0].serit ?? "") }
            guard !seritler.isEmpty else { return nil }
            let serit = seritler[Int(rng.next() % UInt64(seritler.count))]
            let (a, b) = ikiFarkli(serit, rng: &rng) { $0.deger != $1.deger }
            guard let a, let b else { return nil }
            return senaryo([a.id, b.id], siraBoz(&y, a.id, b.id))

        case .bolge_kaydir:
            let adaylar = c.dugumler.filter { $0.bolge != nil }
            guard !adaylar.isEmpty else { return nil }
            let d = adaylar[Int(rng.next() % UInt64(adaylar.count))]
            let digerleri = VucutBolgesi.allCases.filter { $0 != d.bolge }
            let yeni = digerleri[Int(rng.next() % UInt64(digerleri.count))]
            return senaryo([d.id], bolgeKaydir(&y, d.id, yeni))
        }
    }

    private static func ikiFarkli(_ dizi: [CizimDugumu], rng: inout TohumluUretec,
                                  _ farkli: (CizimDugumu, CizimDugumu) -> Bool) -> (CizimDugumu?, CizimDugumu?) {
        for _ in 0..<16 {
            let a = dizi[Int(rng.next() % UInt64(dizi.count))]
            let b = dizi[Int(rng.next() % UInt64(dizi.count))]
            if a.id != b.id && farkli(a, b) { return (a, b) }
        }
        return (nil, nil)
    }

    // MARK: - Dönüşümler (başarılıysa otomatik "Doğrusu" cümlesi döner)

    private static func takasEt(_ c: inout LevhaCizim, _ a: String, _ b: String, butun: Bool) -> String? {
        guard let i = c.indeks(a), let j = c.indeks(b), i != j else { return nil }
        let (da, db) = (c.dugumler[i], c.dugumler[j])
        c.dugumler[i].etiket = db.etiket
        c.dugumler[j].etiket = da.etiket
        if butun {
            c.dugumler[i].renkAdi = db.renkAdi; c.dugumler[j].renkAdi = da.renkAdi
            c.dugumler[i].tus = db.tus; c.dugumler[j].tus = da.tus
            c.dugumler[i].not = db.not; c.dugumler[j].not = da.not
        }
        return "Doğrusu: «\(da.etiket)» ile «\(db.etiket)» yer değiştirmişti."
    }

    private static func degerKaydir(_ c: inout LevhaCizim, _ id: String, _ yeni: Double) -> String? {
        guard let i = c.indeks(id), let eski = c.dugumler[i].deger, eski != yeni else { return nil }
        let fark = yeni - eski
        let eskiBit = c.dugumler[i].bit
        c.dugumler[i].deger = yeni
        if let bit = eskiBit { c.dugumler[i].bit = min(c.eksenMax, bit + fark) }
        let d = c.dugumler[i]
        if c.tip == .zaman_cizelgesi {
            let birim = ZamanBirimi(rawValue: c.birim)?.ad ?? c.birim
            if let eb = eskiBit, let yb = d.bit {
                return "Doğrusu: «\(d.etiket)» \(Bicim.sayi(eski))–\(Bicim.sayi(eb)) \(birim) (gösterilen \(Bicim.sayi(yeni))–\(Bicim.sayi(yb)))."
            }
            return "Doğrusu: «\(d.etiket)» \(Bicim.sayi(eski)). \(birim) (gösterilen \(Bicim.sayi(yeni)))."
        }
        return "Doğrusu: «\(d.etiket)» = \(Bicim.sayi(eski)) \(c.birim) (gösterilen \(Bicim.sayi(yeni)))."
    }

    private static func renkDegistir(_ c: inout LevhaCizim, _ id: String, _ renk: String) -> String? {
        guard let i = c.indeks(id), c.dugumler[i].renkAdi != renk else { return nil }
        let eski = c.dugumler[i].renkAdi
        c.dugumler[i].renkAdi = renk
        return "Doğrusu: «\(c.dugumler[i].etiket)» \(renkAnlami(eski)) olmalı."
    }

    private static func baglantiTersle(_ c: inout LevhaCizim, _ a: String, _ b: String) -> String? {
        guard let i = c.baglantilar.firstIndex(where: { Set([$0.from, $0.to]) == Set([a, b]) }) else { return nil }
        let bag = c.baglantilar[i]
        c.baglantilar[i].from = bag.to
        c.baglantilar[i].to = bag.from
        let kopya = c
        let ad = { (id: String) in kopya.dugum(id)?.etiket ?? id }
        let ok = bag.tip == .inhibe ? "⊣" : "→"
        return "Doğrusu: «\(ad(bag.from))» \(ok) «\(ad(bag.to))» yönündedir."
    }

    private static func siraBoz(_ c: inout LevhaCizim, _ a: String, _ b: String) -> String? {
        guard let i = c.indeks(a), let j = c.indeks(b), let va = c.dugumler[i].deger, let vb = c.dugumler[j].deger, va != vb else { return nil }
        let (da, db) = (c.dugumler[i], c.dugumler[j])
        c.dugumler[i].deger = db.deger; c.dugumler[i].bit = db.bit
        c.dugumler[j].deger = da.deger; c.dugumler[j].bit = da.bit
        let birim = ZamanBirimi(rawValue: c.birim)?.ad ?? c.birim
        let (once, sonra) = va < vb ? (da, db) : (db, da)
        return "Doğrusu: «\(once.etiket)» (\(Bicim.sayi(once.deger ?? 0)). \(birim)) «\(sonra.etiket)»dan (\(Bicim.sayi(sonra.deger ?? 0)). \(birim)) önce gelir."
    }

    private static func bolgeKaydir(_ c: inout LevhaCizim, _ id: String, _ yeni: VucutBolgesi) -> String? {
        guard let i = c.indeks(id), let eski = c.dugumler[i].bolge, eski != yeni else { return nil }
        c.dugumler[i].bolge = yeni
        return "Doğrusu: «\(c.dugumler[i].etiket)» → \(eski.ad) (gösterilen: \(yeni.ad))."
    }

    static func renkAnlami(_ r: String) -> String {
        switch RenkAdi(rawValue: r) {
        case .kirmizi: return "kırmızı (patolojik/acil)"
        case .mavi: return "mavi (tanı/bulgu)"
        case .yesil: return "yeşil (tedavi/normal)"
        case .sari: return "sarı (tuzak/istisna)"
        case .gri, .none: return "gri (bağlam)"
        }
    }
}
