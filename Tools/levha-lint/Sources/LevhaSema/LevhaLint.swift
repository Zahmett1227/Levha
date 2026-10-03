import Foundation

public struct LintBulgusu: Hashable, CustomStringConvertible {
    public var yer: String
    public var mesaj: String
    /// Uygulamada içe aktarmayı durduran hata mı?
    public var engelleyici: Bool
    /// Yalnız bilgi: CLI bunu hata saymaz.
    public var uyari: Bool

    public init(_ yer: String, _ mesaj: String, engelleyici: Bool = true, uyari: Bool = false) {
        self.yer = yer
        self.mesaj = mesaj
        self.engelleyici = engelleyici && !uyari
        self.uyari = uyari
    }

    public var description: String { yer.isEmpty ? mesaj : "\(yer): \(mesaj)" }
}

public struct LintSonucu {
    public var paket: PaketJSON?
    public var bulgular: [LintBulgusu]
    public var engelleyiciVar: Bool { paket == nil || bulgular.contains { $0.engelleyici } }
    public var hatalar: [LintBulgusu] { bulgular.filter { !$0.uyari } }
    public var uyarilar: [LintBulgusu] { bulgular.filter(\.uyari) }
}

public enum LevhaLint {
    public static let desteklenenSurumler = 1...5
    public static let etiketSiniri = 28
    public static let dugumAraligi = 6...20
    public static let hucreAraligi = 6...24
    public static let sutunAraligi = 2...4
    public static let satirAraligi = 2...6
    public static let seritSiniri = 4
    /// `ipucu_sirasi` beklenen (klinik) dersler.
    public static let klinikDersler: Set<String> = ["Pediatri", "Dahiliye", "Genel Cerrahi", "Kadın-Doğum", "Küçük Stajlar"]

    /// Vaka kökü: en az 20 kelime (klinik tablo anlatır). Kısa bilgi sorularında ipucu sırası beklenmez.
    public static func vakaKokuMu(_ kok: String) -> Bool {
        kok.split(whereSeparator: { $0 == " " || $0 == "\n" }).count >= 20
    }

    public static func denetle(veri: Data) -> LintSonucu {
        do {
            let paket = try JSONDecoder().decode(PaketJSON.self, from: veri)
            return LintSonucu(paket: paket, bulgular: denetle(paket))
        } catch let hata as DecodingError {
            return LintSonucu(paket: nil, bulgular: [cozumHatasi(hata, veri: veri)])
        } catch {
            return LintSonucu(paket: nil, bulgular: [LintBulgusu("", "okunamadı: \(error.localizedDescription)")])
        }
    }

    /// Örtme, sabotaj ve sorular için düğüm sayılan her şey: düğümler, matris hücreleri
    /// (`r{satır}c{sütun}`), cetvel işaretleri, zaman olayları, vücut bölgeleri.
    public static func dugumKimlikleri(_ l: LevhaJSON) -> [String] {
        var idler = (l.dugumler ?? []).map(\.id)
        if l.tip == .matris, let hucreler = l.hucreler {
            for (r, satir) in hucreler.enumerated() {
                for c in satir.indices { idler.append("r\(r)c\(c)") }
            }
        }
        if l.tip == .sayi_cetveli { idler += (l.isaretler ?? []).map(\.id) }
        if l.tip == .zaman_cizelgesi { idler += (l.olaylar ?? []).map(\.id) }
        if l.tip == .vucut_haritasi { idler += (l.bolgeler ?? []).map(\.id) }
        return idler
    }

    public static func denetle(_ p: PaketJSON) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        if !desteklenenSurumler.contains(p.sema_surumu) {
            b.append(.init("sema_surumu", "desteklenmeyen sürüm \(p.sema_surumu) (beklenen 1–5)"))
        }
        for (ad, deger) in [("paket_id", p.paket_id), ("ders", p.ders), ("bolum", p.bolum), ("alt_konu", p.alt_konu)] where bos(deger) {
            b.append(.init(ad, "boş olamaz"))
        }
        if let t = p.tur, !p.soruPaketiMi {
            b.append(.init("tur", "bilinmeyen tür \"\(t)\" (izinli: \(PaketJSON.soruPaketiTuru))"))
        }
        if p.soruPaketiMi { return b + soruPaketiDenetle(p) }
        if p.levhalar.isEmpty { b.append(.init("levhalar", "en az bir levha olmalı")) }

        var levhaDugumleri: [String: Set<String>] = [:]
        for l in p.levhalar {
            let yer = "levha «\(l.id)»"
            if levhaDugumleri[l.id] != nil { b.append(.init(yer, "levha id tekrar ediyor")) }
            b += levhaDenetle(l, yer: yer, surum: p.sema_surumu)
            levhaDugumleri[l.id] = Set(dugumKimlikleri(l))
        }
        let v4 = p.sema_surumu >= 4

        let v3 = p.sema_surumu >= 3
        let tumDugumler = levhaDugumleri.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let (kazanimlar, aileler) = kazanimAileDenetle(p, tumDugumler: tumDugumler, &b)

        var soruIdleri = Set<String>()
        for s in p.sorular ?? [] {
            let yer = "soru «\(s.id)»"
            if !soruIdleri.insert(s.id).inserted { b.append(.init(yer, "soru id tekrar ediyor")) }
            if bos(s.kok) { b.append(.init(yer + " › kok", "boş olamaz")) }
            if bos(s.aciklama) { b.append(.init(yer + " › aciklama", "boş olamaz", engelleyici: false)) }
            if s.secenekler.count != 5 { b.append(.init(yer + " › secenekler", "5 seçenek olmalı (\(s.secenekler.count) var)")) }
            if !(0...4).contains(s.dogru) { b.append(.init(yer + " › dogru", "0–4 arasında olmalı (\(s.dogru))")) }
            b += soruV3Denetle(s, yer: yer, v3: v3, kazanimlar: kazanimlar, aileler: aileler)
            b += soruV4Denetle(s, yer: yer, v4: v4, klinik: klinikDersler.contains(p.ders), idler: s.levha.flatMap { levhaDugumleri[$0] })
            if let ab = s.anlatim_baslik { b += anlatimBaslikDenetle(ab, anlatim: p.anlatim, yer: yer) }
            guard let lid = s.levha, !bos(lid) else {
                b.append(.init(yer + " › levha", "zorunlu (levhasız soru yalnız soru paketinde olur)"))
                continue
            }
            guard let idler = levhaDugumleri[lid] else {
                b.append(.init(yer + " › levha", "bilinmeyen levha \"\(lid)\""))
                continue
            }
            for d in s.dugumler ?? [] where !idler.contains(d) {
                b.append(.init(yer + " › dugumler", "bilinmeyen düğüm \"\(d)\""))
            }
            for d in s.aciklama_yolu ?? [] where !idler.contains(d) {
                b.append(.init(yer + " › aciklama_yolu", "bilinmeyen düğüm \"\(d)\""))
            }
            for (anahtar, dugum) in (s.celdirici_dugum ?? [:]).sorted(by: { $0.key < $1.key }) {
                guard let i = Int(anahtar), (0...4).contains(i) else {
                    b.append(.init(yer + " › celdirici_dugum", "geçersiz seçenek anahtarı \"\(anahtar)\" (0–4 olmalı)"))
                    continue
                }
                if i == s.dogru {
                    b.append(.init(yer + " › celdirici_dugum", "doğru seçenek (\(i)) çeldirici olarak işaretlenmiş", engelleyici: false))
                }
                if !idler.contains(dugum) {
                    b.append(.init(yer + " › celdirici_dugum", "bilinmeyen düğüm \"\(dugum)\""))
                }
            }
        }
        b += anlatimDenetle(p)
        return b
    }

    /// Aileler ve kazanımlar (v3). `tumDugumler` nil → kazanım düğümleri denetlenmez (soru paketi).
    static func kazanimAileDenetle(_ p: PaketJSON, tumDugumler: Set<String>?, _ b: inout [LintBulgusu])
        -> (kazanimlar: [String: KazanimJSON], aileler: [String: AileJSON]) {
        var aileler: [String: AileJSON] = [:]
        for a in p.aileler ?? [] {
            let yer = "aile «\(a.id)»"
            if aileler[a.id] != nil { b.append(.init(yer, "aile id tekrar ediyor")) }
            aileler[a.id] = a
            if a.uyeler.count < 2 { b.append(.init(yer + " › uyeler", "en az 2 üye olmalı", engelleyici: false)) }
            for anahtar in (a.ayirici ?? [:]).keys.sorted() {
                let parca = anahtar.split(separator: "|").map(String.init)
                if parca.count != 2 || !parca.allSatisfy(a.uyeler.contains) {
                    b.append(.init(yer + " › ayirici", "\"\(anahtar)\" iki aile üyesini \"A|B\" biçiminde vermeli", engelleyici: false))
                }
            }
        }
        var kazanimlar: [String: KazanimJSON] = [:]
        for k in p.kazanimlar ?? [] {
            let yer = "kazanım «\(k.id)»"
            if kazanimlar[k.id] != nil { b.append(.init(yer, "kazanım id tekrar ediyor")) }
            kazanimlar[k.id] = k
            if bos(k.metin) { b.append(.init(yer + " › metin", "boş olamaz")) }
            if KalipTipi(rawValue: k.kalip) == nil { b.append(.init(yer + " › kalip", "tanımsız kalıp \"\(k.kalip)\"")) }
            if !(1...5).contains(k.sorulabilirlik) { b.append(.init(yer + " › sorulabilirlik", "1–5 olmalı (\(k.sorulabilirlik))")) }
            if let a = k.aile, aileler[a] == nil { b.append(.init(yer + " › aile", "bilinmeyen aile \"\(a)\"")) }
            if let tumDugumler {
                for d in k.dugumler ?? [] where !tumDugumler.contains(d) {
                    b.append(.init(yer + " › dugumler", "paketin hiçbir levhasında yok: \"\(d)\""))
                }
            }
        }
        let soruluKazanimlar = Set((p.sorular ?? []).compactMap(\.kazanim))
        for k in p.kazanimlar ?? [] where !soruluKazanimlar.contains(k.id) {
            b.append(.init("kazanım «\(k.id)»", "sorusuz kazanım", uyari: true))
        }
        return (kazanimlar, aileler)
    }

    // MARK: - v5: anlatım ve soru paketi

    /// Anlatım: `[[...]]` referansları paketteki düğüm/levha olmalı (hata, içe aktarmayı durdurmaz);
    /// 2.000–6.000 kelime ve `##` başlıklar beklenir (uyarı).
    static func anlatimDenetle(_ p: PaketJSON) -> [LintBulgusu] {
        guard let a = p.anlatim else { return [] }
        let yer = "anlatim"
        guard !bos(a) else { return [.init(yer, "boş olamaz", engelleyici: false)] }
        var b: [LintBulgusu] = []
        let n = AnlatimMetni.kelimeSayisi(a)
        if !AnlatimMetni.kelimeAraligi.contains(n) {
            b.append(.init(yer, "\(n) kelime (beklenen \(AnlatimMetni.kelimeAraligi.lowerBound)–\(AnlatimMetni.kelimeAraligi.upperBound))", uyari: true))
        }
        let basliklar = AnlatimMetni.basliklar(a)
        if !basliklar.contains(where: { $0.seviye == 2 }) { b.append(.init(yer, "## başlık yok", uyari: true)) }
        var gorulen = Set<String>()
        for h in basliklar where !gorulen.insert(AnlatimMetni.baslikAnahtari(h.metin)).inserted {
            b.append(.init(yer, "başlık tekrar ediyor: \"\(h.metin)\" (anlatim_baslik ilkine gider)", uyari: true))
        }
        let levhalar = p.levhalar.map { (id: $0.id, dugumler: Set(dugumKimlikleri($0))) }
        for r in AnlatimMetni.referanslar(a) {
            let ryer = "\(yer) › [[\(r.ham)]]"
            guard !bos(r.hedef) else {
                b.append(.init(ryer, "boş referans", engelleyici: false))
                continue
            }
            switch AnlatimMetni.coz(r, paketId: p.paket_id, levhalar: levhalar) {
            case .levha, .dugum:
                break
            case .belirsiz(let levha, _, let adaylar):
                b.append(.init(ryer, "düğüm \(adaylar.count) levhada var; \(levha) açılır (belirli levha için levha_id#düğüm yaz)", uyari: true))
            case .disPaket(let id):
                b.append(.init(ryer, "başka paketin levhası (\(id)); o paket içe aktarılmışsa açılır", uyari: true))
            case .yok:
                b.append(.init(ryer, r.dugum == nil ? "bilinmeyen düğüm/levha \"\(r.hedef)\"" : "bilinmeyen levha ya da düğüm", engelleyici: false))
            }
        }
        return b
    }

    /// `anlatim_baslik` paketin anlatımında bir başlık olmalı.
    static func anlatimBaslikDenetle(_ baslik: String, anlatim: String?, yer: String) -> [LintBulgusu] {
        let yer = yer + " › anlatim_baslik"
        guard let anlatim, !bos(anlatim) else { return [.init(yer, "paketin anlatımı yok", engelleyici: false)] }
        let anahtar = AnlatimMetni.baslikAnahtari(baslik)
        guard !AnlatimMetni.basliklar(anlatim).contains(where: { AnlatimMetni.baslikAnahtari($0.metin) == anahtar }) else { return [] }
        return [.init(yer, "anlatımda böyle başlık yok: \"\(baslik)\"", engelleyici: false)]
    }

    /// `tur: "soru_paketi"`: levhasız soru dosyası. 5 şık, doğru şık ve açıklama zorunlu; kalıp ve kazanım
    /// zorunlu değil (uyarı). `levha` başka paketin levhası olabilir (burada doğrulanamaz); yoksa soru bağımsızdır
    /// ve düğüm alanı taşıyamaz.
    static func soruPaketiDenetle(_ p: PaketJSON) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        if !p.levhalar.isEmpty { b.append(.init("levhalar", "soru paketinde levha olmaz (levhalar konu paketine yazılır)")) }
        let sorular = p.sorular ?? []
        if sorular.isEmpty { b.append(.init("sorular", "en az bir soru olmalı")) }
        let (kazanimlar, aileler) = kazanimAileDenetle(p, tumDugumler: nil, &b)
        var soruIdleri = Set<String>()
        for s in sorular {
            let yer = "soru «\(s.id)»"
            if !soruIdleri.insert(s.id).inserted { b.append(.init(yer, "soru id tekrar ediyor")) }
            if bos(s.kok) { b.append(.init(yer + " › kok", "boş olamaz")) }
            if bos(s.aciklama) { b.append(.init(yer + " › aciklama", "boş olamaz (soru paketinde zorunlu)")) }
            if s.secenekler.count != 5 { b.append(.init(yer + " › secenekler", "5 seçenek olmalı (\(s.secenekler.count) var)")) }
            if s.secenekler.contains(where: bos) { b.append(.init(yer + " › secenekler", "boş seçenek var")) }
            if !(0...4).contains(s.dogru) { b.append(.init(yer + " › dogru", "0–4 arasında olmalı (\(s.dogru))")) }
            if let z = s.zorluk, !(1...3).contains(z) { b.append(.init(yer + " › zorluk", "1–3 olmalı (\(z))")) }
            var kazanim: KazanimJSON?
            if let kalip = s.kalip {
                if KalipTipi(rawValue: kalip) == nil { b.append(.init(yer + " › kalip", "tanımsız kalıp \"\(kalip)\"")) }
            }
            if let kid = s.kazanim {
                kazanim = kazanimlar[kid]
                if kazanim == nil {
                    b.append(.init(yer + " › kazanim", "pakette yok: \"\(kid)\" (içe aktarmada bağlı levhanın ya da aynı alt konunun paketinde aranır)", uyari: true))
                }
            } else {
                b.append(.init(yer + " › kazanim", "yok (yanlışlar alt konu düzeyinde sayılır)", uyari: true))
            }
            if s.kalip == nil && kazanim == nil { b.append(.init(yer + " › kalip", "yok (kalıp istatistiğine girmez)", uyari: true)) }
            b += secenekAileDenetle(s, yer: yer, kazanim: kazanim, aileler: aileler)
            let levhali = !bos(s.levha ?? "")
            if !levhali {
                for (alan, dolu) in [("dugumler", !(s.dugumler ?? []).isEmpty), ("aciklama_yolu", !(s.aciklama_yolu ?? []).isEmpty),
                                     ("celdirici_dugum", !(s.celdirici_dugum ?? [:]).isEmpty),
                                     ("ipucu_sirasi.dugum", (s.ipucu_sirasi ?? []).contains { $0.dugum != nil })] where dolu {
                    b.append(.init(yer + " › \(alan)", "levhası olmayan soruda düğüm olmaz"))
                }
            }
            b += soruV4Denetle(s, yer: yer, v4: true, klinik: klinikDersler.contains(p.ders), idler: nil)
            if let ab = s.anlatim_baslik, p.anlatim != nil { b += anlatimBaslikDenetle(ab, anlatim: p.anlatim, yer: yer) }
        }
        b += anlatimDenetle(p)
        return b
    }

    /// v4: ipucu sırası ve kırılımlar.
    static func soruV4Denetle(_ s: SoruJSON, yer: String, v4: Bool, klinik: Bool, idler: Set<String>?) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        let ipuclari = s.ipucu_sirasi ?? []
        for (i, ip) in ipuclari.enumerated() {
            let iyer = "\(yer) › ipucu_sirasi[\(i)]"
            if bos(ip.metin) {
                b.append(.init(iyer + ".metin", "boş olamaz"))
            } else if !s.kok.contains(ip.metin) {
                b.append(.init(iyer + ".metin", "kökte birebir geçmiyor: \"\(ip.metin)\""))
            }
            if ip.ipucuTuru == nil {
                b.append(.init(iyer + ".tur", "geçersiz tür \"\(ip.tur)\" (izinli: \(IpucuTuru.allCases.map(\.rawValue).joined(separator: ", ")))"))
            }
            if let a = ip.agirlik, !(0...3).contains(a) { b.append(.init(iyer + ".agirlik", "0–3 olmalı (\(a))")) }
            if let d = ip.dugum, let idler, !idler.contains(d) { b.append(.init(iyer + ".dugum", "bilinmeyen düğüm \"\(d)\"")) }
        }
        for (i, k) in (s.kirilimlar ?? []).enumerated() {
            let kyer = "\(yer) › kirilimlar[\(i)]"
            if !ipuclari.indices.contains(k.ipucu) {
                b.append(.init(kyer + ".ipucu", "ipucu_sirasi indeksi dışında (\(k.ipucu); \(ipuclari.count) ipucu var)"))
            }
            if !(0...4).contains(k.yeni_dogru) { b.append(.init(kyer + ".yeni_dogru", "0–4 arasında olmalı (\(k.yeni_dogru))")) }
            if bos(k.yeni_metin) { b.append(.init(kyer + ".yeni_metin", "boş olamaz")) }
        }
        if v4 && klinik && ipuclari.isEmpty && vakaKokuMu(s.kok) {
            b.append(.init(yer + " › ipucu_sirasi", "klinik soruda ipucu_sirasi yok", uyari: true))
        }
        return b
    }

    static func soruV3Denetle(_ s: SoruJSON, yer: String, v3: Bool, kazanimlar: [String: KazanimJSON],
                              aileler: [String: AileJSON]) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        if let kalip = s.kalip, KalipTipi(rawValue: kalip) == nil {
            b.append(.init(yer + " › kalip", "tanımsız kalıp \"\(kalip)\""))
        }
        if let z = s.zorluk, !(1...3).contains(z) { b.append(.init(yer + " › zorluk", "1–3 olmalı (\(z))")) }
        var kazanim: KazanimJSON?
        if let kid = s.kazanim {
            kazanim = kazanimlar[kid]
            if kazanim == nil { b.append(.init(yer + " › kazanim", "tanımsız kazanım \"\(kid)\"")) }
        } else if v3 {
            b.append(.init(yer + " › kazanim", "v3 pakette her sorunun kazanımı olmalı"))
        }
        b += secenekAileDenetle(s, yer: yer, kazanim: kazanim, aileler: aileler)
        return b
    }

    static func secenekAileDenetle(_ s: SoruJSON, yer: String, kazanim: KazanimJSON?, aileler: [String: AileJSON]) -> [LintBulgusu] {
        guard let sa = s.secenek_aile, !sa.isEmpty else { return [] }
        var b: [LintBulgusu] = []
        // Kazanımın ailesi varsa ona, yoksa paketin tüm ailelerine bakılır.
        let uyeler: Set<String> = kazanim?.aile.flatMap { aileler[$0] }.map { Set($0.uyeler) }
            ?? aileler.values.reduce(into: Set<String>()) { $0.formUnion($1.uyeler) }
        var celdiriciSayisi = 0
        for (anahtar, uye) in sa.sorted(by: { $0.key < $1.key }) {
            guard let i = Int(anahtar), (0...4).contains(i) else {
                b.append(.init(yer + " › secenek_aile", "geçersiz şık anahtarı \"\(anahtar)\" (0–4 olmalı)"))
                continue
            }
            if !uyeler.contains(uye) { b.append(.init(yer + " › secenek_aile", "\"\(uye)\" ailede yok")) }
            if i != s.dogru { celdiriciSayisi += 1 }
        }
        if celdiriciSayisi < 3 {
            b.append(.init(yer + " › secenek_aile", "4 çeldiricinin yalnız \(celdiriciSayisi) tanesi aileden", uyari: true))
        }
        return b
    }

    static func levhaDenetle(_ l: LevhaJSON, yer: String, surum: Int) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        if bos(l.baslik) { b.append(.init(yer + " › baslik", "boş olamaz", engelleyici: false)) }
        if bos(l.akilda_kalan) { b.append(.init(yer + " › akilda_kalan", "boş olamaz", engelleyici: false)) }

        var idler = Set<String>()
        for id in dugumKimlikleri(l) where !idler.insert(id).inserted {
            b.append(.init(yer, "düğüm id tekrar ediyor: \(id)"))
        }
        let dugumler = l.dugumler ?? []
        for d in dugumler { etiketDenetle(d.etiket, yer: "\(yer) › \(d.id).etiket", &b) }

        switch l.tip {
        case .algoritma, .yolak, .agac:
            izgaraDenetle(l, yer: yer, &b)
            baglantilariDenetle(l, idler, yer, &b)
            if l.tip == .agac { agacDenetle(l, idler, yer, &b) }

        case .matris:
            guard let satirlar = l.satirlar, let sutunlar = l.sutunlar, let hucreler = l.hucreler else {
                b.append(.init(yer, "matris için satirlar, sutunlar ve hucreler zorunlu"))
                break
            }
            if hucreler.count != satirlar.count {
                b.append(.init(yer + " › hucreler", "\(satirlar.count) satır bekleniyor, \(hucreler.count) var"))
            }
            for (r, satir) in hucreler.enumerated() where satir.count != sutunlar.count {
                b.append(.init("\(yer) › hucreler[\(r)]", "\(sutunlar.count) hücre bekleniyor, \(satir.count) var"))
            }
            sayiDenetle(hucreler.reduce(0) { $0 + $1.count }, hucreAraligi, "hücre sayısı", yer, &b)
            for (r, satir) in hucreler.enumerated() {
                for (c, h) in satir.enumerated() { etiketDenetle(h.metin, yer: "\(yer) › r\(r)c\(c).metin", &b) }
            }
            for (i, s) in satirlar.enumerated() { etiketDenetle(s, yer: "\(yer) › satirlar[\(i)]", &b) }
            for (i, s) in sutunlar.enumerated() { etiketDenetle(s, yer: "\(yer) › sutunlar[\(i)]", &b) }

        case .sayi_cetveli:
            guard let eksen = eksenDenetle(l, yer: yer, &b) else { break }
            let isaretler = l.isaretler ?? []
            sayiDenetle(isaretler.count, dugumAraligi, "işaret sayısı", yer, &b)
            for m in isaretler {
                etiketDenetle(m.etiket, yer: "\(yer) › \(m.id).etiket", &b)
                if let v = m.deger, !eksen.contains(v) {
                    b.append(.init("\(yer) › \(m.id).deger", "\(sayi(v)) eksen aralığının (\(sayi(eksen.lowerBound))–\(sayi(eksen.upperBound))) dışında"))
                }
            }

        case .zaman_cizelgesi:
            guard let eksen = eksenDenetle(l, yer: yer, &b) else { break }
            if let birim = l.eksen?.birim, ZamanBirimi(rawValue: birim) == nil {
                b.append(.init(yer + " › eksen.birim", "\"\(birim)\" geçersiz (izinli: gun, hafta, ay, yil)", engelleyici: false))
            }
            let seritler = l.seritler ?? []
            if seritler.isEmpty { b.append(.init(yer + " › seritler", "en az bir şerit olmalı")) }
            if seritler.count > seritSiniri { b.append(.init(yer + " › seritler", "en fazla \(seritSiniri) şerit (\(seritler.count) var)", engelleyici: false)) }
            var seritIdleri = Set<String>()
            for s in seritler {
                if !seritIdleri.insert(s.id).inserted { b.append(.init(yer + " › seritler", "şerit id tekrar ediyor: \(s.id)")) }
                etiketDenetle(s.ad, yer: "\(yer) › \(s.id).ad", &b)
            }
            let olaylar = l.olaylar ?? []
            sayiDenetle(olaylar.count, dugumAraligi, "olay sayısı", yer, &b)
            for o in olaylar {
                let oyer = "\(yer) › \(o.id)"
                etiketDenetle(o.etiket, yer: oyer + ".etiket", &b)
                if !seritIdleri.contains(o.serit) { b.append(.init(oyer + ".serit", "bilinmeyen şerit \"\(o.serit)\"")) }
                if !eksen.contains(o.bas) { b.append(.init(oyer + ".bas", "\(sayi(o.bas)) eksen dışında")) }
                if let bit = o.bit {
                    if !eksen.contains(bit) { b.append(.init(oyer + ".bit", "\(sayi(bit)) eksen dışında")) }
                    if bit < o.bas { b.append(.init(oyer + ".bit", "bit, bas'tan küçük olamaz")) }
                }
            }

        case .vucut_haritasi:
            let bolgeler = l.bolgeler ?? []
            sayiDenetle(bolgeler.count, dugumAraligi, "bölge sayısı", yer, &b)
            for g in bolgeler { etiketDenetle(g.etiket, yer: "\(yer) › \(g.id).etiket", &b) }
        }

        var gorulen = Set<String>()
        for id in l.ortme_sirasi ?? [] {
            if !idler.contains(id) { b.append(.init(yer + " › ortme_sirasi", "bilinmeyen düğüm \"\(id)\"")) }
            if !gorulen.insert(id).inserted { b.append(.init(yer + " › ortme_sirasi", "\(id) tekrar ediyor", engelleyici: false)) }
        }
        if gorulen.count < 3 {
            b.append(.init(yer + " › ortme_sirasi", "en az 3 düğüm olmalı", engelleyici: false))
        }

        if let r = l.revizyon, r < 0 { b.append(.init(yer + " › revizyon", "negatif olamaz (\(r))")) }
        if surum >= 4 && (l.kaynak?.anahtar_kelimeler ?? []).isEmpty {
            b.append(.init(yer + " › kaynak.anahtar_kelimeler", "yok (kitap sayfası eşlemesi yalnız başlık ve etiketlerle yapılır)", uyari: true))
        }

        for id in l.insa_sirasi ?? [] where !idler.contains(id) {
            b.append(.init(yer + " › insa_sirasi", "bilinmeyen düğüm \"\(id)\""))
        }
        if surum >= 3 && (l.insa_sirasi ?? []).isEmpty {
            b.append(.init(yer + " › insa_sirasi", "yok (İnşa ortme_sirasi ile idare eder)", uyari: true))
        }

        let sabotajlar = l.sabotajlar ?? []
        if sabotajlar.isEmpty {
            b.append(.init(yer + " › sabotajlar", "yazılmış sabotaj yok (üretilmiş ile idare edilir)", uyari: true))
        }
        for (i, s) in sabotajlar.enumerated() {
            for m in sabotajHatalari(s, levha: l, idler: idler, surum: surum) {
                b.append(.init("\(yer) › sabotajlar[\(i)]", m, engelleyici: false))
            }
        }
        return b
    }

    /// v2'de tip bazlı tam denetim; v1'de yalnız tip ve hedef referansları.
    public static func sabotajHatalari(_ s: SabotajJSON, levha l: LevhaJSON, idler: Set<String>, surum: Int) -> [String] {
        var h: [String] = []
        let hedefler = s.hedef ?? []
        for hid in hedefler where !idler.contains(hid) { h.append("bilinmeyen hedef \"\(hid)\"") }
        guard surum >= 2 else {
            if bos(s.tip) { h.append("tip zorunlu") }
            return h
        }
        guard let tip = s.sabotajTipi else {
            return h + ["geçersiz tip \"\(s.tip)\" (izinli: \(SabotajTipi.allCases.map(\.rawValue).joined(separator: ", ")))"]
        }
        if !tip.uygun(l.tip) { h.append("\(tip.rawValue) \(l.tip.ad.lowercased()) levhasına uygulanamaz") }
        if hedefler.count != tip.hedefSayisi { h.append("\(tip.rawValue) için \(tip.hedefSayisi) hedef gerekir (\(hedefler.count) var)") }
        if bos(s.dogrusu ?? "") { h.append("dogrusu zorunlu") }
        switch tip {
        case .deger_kaydir:
            if s.yanlis_deger == nil { h.append("yanlis_deger zorunlu") }
        case .renk_degistir:
            if RenkAdi(rawValue: s.yanlis_renk ?? "") == nil { h.append("yanlis_renk zorunlu (kirmizi, mavi, yesil, sari, gri)") }
        case .bolge_kaydir:
            if VucutBolgesi(rawValue: s.yanlis_bolge ?? "") == nil { h.append("yanlis_bolge zorunlu, sabit bölge listesinden") }
        case .baglanti_ters:
            if hedefler.count == 2 {
                let var_ = (l.baglantilar ?? []).contains { Set([$0.from, $0.to]) == Set(hedefler) }
                    || (l.tip == .agac && (l.dugumler ?? []).contains { Set([$0.id, $0.ebeveyn ?? ""]) == Set(hedefler) })
                if !var_ { h.append("\(hedefler[0]) ile \(hedefler[1]) arasında bağlantı yok") }
            }
        case .sira_boz:
            if hedefler.count == 2 {
                let olaylar = (l.olaylar ?? []).filter { hedefler.contains($0.id) }
                if Set(olaylar.map(\.serit)).count > 1 { h.append("sira_boz hedefleri aynı şeritte olmalı") }
                if Set(olaylar.map(\.bas)).count < olaylar.count { h.append("sira_boz hedeflerinin bas değerleri farklı olmalı") }
            }
        case .hucre_takas:
            if hedefler.count == 2, Set(hedefler.compactMap { $0.split(separator: "c").last }).count > 1 {
                h.append("hucre_takas hedefleri aynı sütunda olmalı")
            }
        case .etiket_takas:
            break
        }
        if let v = s.yanlis_deger, let e = l.eksen, !(e.min...e.max).contains(v) {
            h.append("yanlis_deger eksen dışında")
        }
        return h
    }

    static func izgaraDenetle(_ l: LevhaJSON, yer: String, _ b: inout [LintBulgusu]) {
        let dugumler = l.dugumler ?? []
        guard let izgara = l.duzen?.izgara, izgara.count == 2, izgara[0] > 0, izgara[1] > 0 else {
            b.append(.init(yer + " › duzen.izgara", "\(l.tip.ad.lowercased()) için [sütun, satır] zorunlu"))
            return
        }
        let (sutun, satir) = (izgara[0], izgara[1])
        if !sutunAraligi.contains(sutun) { b.append(.init(yer + " › duzen.izgara", "sütun sayısı 2–4 olmalı (\(sutun))", engelleyici: false)) }
        if !satirAraligi.contains(satir) { b.append(.init(yer + " › duzen.izgara", "satır sayısı 2–6 olmalı (\(satir))", engelleyici: false)) }
        sayiDenetle(dugumler.count, dugumAraligi, "düğüm sayısı", yer, &b)
        var dolu: [String: String] = [:]
        for d in dugumler {
            guard let k = d.konum, k.count == 2 else {
                b.append(.init("\(yer) › \(d.id).konum", "[sütun, satır] zorunlu"))
                continue
            }
            if !(0..<sutun).contains(k[0]) || !(0..<satir).contains(k[1]) {
                b.append(.init("\(yer) › \(d.id).konum", "[\(k[0]), \(k[1])] ızgaranın (\(sutun)×\(satir)) dışında"))
            }
            let anahtar = "\(k[0]), \(k[1])"
            if let onceki = dolu[anahtar] {
                b.append(.init("\(yer) › \(d.id).konum", "[\(anahtar)] konumu \(onceki) ile çakışıyor"))
            } else {
                dolu[anahtar] = d.id
            }
        }
    }

    static func agacDenetle(_ l: LevhaJSON, _ idler: Set<String>, _ yer: String, _ b: inout [LintBulgusu]) {
        let dugumler = l.dugumler ?? []
        var ebeveynli = Set((l.baglantilar ?? []).map(\.to))
        for d in dugumler {
            guard let e = d.ebeveyn else { continue }
            if !idler.contains(e) { b.append(.init("\(yer) › \(d.id).ebeveyn", "bilinmeyen düğüm \"\(e)\"")) }
            ebeveynli.insert(d.id)
        }
        for d in dugumler where !ebeveynli.contains(d.id) {
            if let k = d.konum, k.count == 2, k[1] != 0 {
                b.append(.init("\(yer) › \(d.id)", "ebeveyni yok ama satır 0'da değil (kök satır 0'da olmalı)", engelleyici: false))
            }
        }
    }

    static func eksenDenetle(_ l: LevhaJSON, yer: String, _ b: inout [LintBulgusu]) -> ClosedRange<Double>? {
        guard let eksen = l.eksen else {
            b.append(.init(yer + " › eksen", "\(l.tip.ad.lowercased()) için zorunlu"))
            return nil
        }
        guard eksen.min < eksen.max else {
            b.append(.init(yer + " › eksen", "min, max'tan küçük olmalı"))
            return nil
        }
        return eksen.min...eksen.max
    }

    static func baglantilariDenetle(_ l: LevhaJSON, _ idler: Set<String>, _ yer: String, _ b: inout [LintBulgusu]) {
        for (i, bag) in (l.baglantilar ?? []).enumerated() {
            let byer = "\(yer) › baglantilar[\(i)]"
            if !idler.contains(bag.from) { b.append(.init(byer, "bilinmeyen kaynak düğüm \"\(bag.from)\"")) }
            if !idler.contains(bag.to) { b.append(.init(byer, "bilinmeyen hedef düğüm \"\(bag.to)\"")) }
            if bag.from == bag.to { b.append(.init(byer, "düğüm kendine bağlanmış", engelleyici: false)) }
        }
    }

    static func etiketDenetle(_ etiket: String, yer: String, _ b: inout [LintBulgusu]) {
        if bos(etiket) {
            b.append(.init(yer, "boş olamaz", engelleyici: false))
        } else if etiket.count > etiketSiniri {
            b.append(.init(yer, "\(etiket.count) karakter; en fazla \(etiketSiniri) (\"\(etiket)\")", engelleyici: false))
        }
    }

    static func sayiDenetle(_ sayi: Int, _ aralik: ClosedRange<Int>, _ ad: String, _ yer: String, _ b: inout [LintBulgusu]) {
        if !aralik.contains(sayi) {
            b.append(.init(yer, "\(ad) \(aralik.lowerBound)–\(aralik.upperBound) olmalı (\(sayi) var)", engelleyici: false))
        }
    }

    static func sayi(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    static func bos(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Decode hatalarını okunur hâle getirme

    static func cozumHatasi(_ hata: DecodingError, veri: Data) -> LintBulgusu {
        let ham = try? JSONSerialization.jsonObject(with: veri)
        switch hata {
        case .dataCorrupted(let ctx):
            if ctx.codingPath.isEmpty {
                let alt = (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                return LintBulgusu("JSON", "geçersiz JSON" + (alt.map { " — \($0)" } ?? ""))
            }
            return LintBulgusu(yer(ctx.codingPath, ham), ctx.debugDescription)
        case .keyNotFound(let anahtar, let ctx):
            return LintBulgusu(yer(ctx.codingPath + [anahtar], ham), "zorunlu alan eksik")
        case .typeMismatch(let tip, let ctx):
            return LintBulgusu(yer(ctx.codingPath, ham), "tip uyuşmuyor, beklenen: \(tipAdi(tip))")
        case .valueNotFound(let tip, let ctx):
            return LintBulgusu(yer(ctx.codingPath, ham), "değer boş (null), beklenen: \(tipAdi(tip))")
        @unknown default:
            return LintBulgusu("", "\(hata)")
        }
    }

    static func yer(_ yol: [CodingKey], _ ham: Any?) -> String {
        func metin(_ parca: ArraySlice<CodingKey>) -> String {
            var s = ""
            for k in parca {
                // JSONDecoder dizi indekslerini "Index N" anahtarıyla verir.
                if let i = k.intValue, k.stringValue.hasPrefix("Index") {
                    s += "[\(i)]"
                } else {
                    s += s.isEmpty ? k.stringValue : ".\(k.stringValue)"
                }
            }
            return s
        }
        // levhalar[i] / sorular[i] yerine, okunabilsin diye id'yi yaz.
        if yol.count >= 2, let i = yol[1].intValue, let kok = ham as? [String: Any] {
            let ad = yol[0].stringValue
            if ad == "levhalar" || ad == "sorular", let dizi = kok[ad] as? [[String: Any]], i < dizi.count, let id = dizi[i]["id"] as? String {
                let onek = "\(ad == "levhalar" ? "levha" : "soru") «\(id)»"
                return yol.count > 2 ? "\(onek) › \(metin(yol.dropFirst(2)))" : onek
            }
        }
        return metin(yol[...])
    }

    static func tipAdi(_ tip: Any.Type) -> String {
        if tip == String.self { return "metin" }
        if tip == Int.self { return "tam sayı" }
        if tip == Double.self { return "sayı" }
        if tip == Bool.self { return "true/false" }
        let ad = String(describing: tip)
        if ad.hasPrefix("Array") { return "dizi" }
        if ad.hasPrefix("Dictionary") { return "nesne" }
        return ad
    }
}
