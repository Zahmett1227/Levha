import Foundation

public struct LintBulgusu: Hashable, CustomStringConvertible {
    public var yer: String
    public var mesaj: String
    /// Uygulamada içe aktarmayı durduran hata mı? (CLI hepsini hata sayar.)
    public var engelleyici: Bool

    public init(_ yer: String, _ mesaj: String, engelleyici: Bool = true) {
        self.yer = yer
        self.mesaj = mesaj
        self.engelleyici = engelleyici
    }

    public var description: String { yer.isEmpty ? mesaj : "\(yer): \(mesaj)" }
}

public struct LintSonucu {
    public var paket: PaketJSON?
    public var bulgular: [LintBulgusu]
    public var engelleyiciVar: Bool { paket == nil || bulgular.contains { $0.engelleyici } }
}

public enum LevhaLint {
    public static let desteklenenSurum = 1
    public static let etiketSiniri = 28
    public static let dugumAraligi = 6...20
    public static let hucreAraligi = 6...24
    public static let sutunAraligi = 2...4
    public static let satirAraligi = 2...6

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

    /// Matris hücreleri `r{satır}c{sütun}`, sayı cetveli işaretleri kendi id'leriyle düğüm sayılır.
    public static func dugumKimlikleri(_ l: LevhaJSON) -> [String] {
        var idler = (l.dugumler ?? []).map(\.id)
        if l.tip == .matris, let hucreler = l.hucreler {
            for (r, satir) in hucreler.enumerated() {
                for c in satir.indices { idler.append("r\(r)c\(c)") }
            }
        }
        if l.tip == .sayi_cetveli { idler += (l.isaretler ?? []).map(\.id) }
        return idler
    }

    public static func denetle(_ p: PaketJSON) -> [LintBulgusu] {
        var b: [LintBulgusu] = []
        if p.sema_surumu != desteklenenSurum {
            b.append(.init("sema_surumu", "desteklenmeyen sürüm \(p.sema_surumu) (beklenen \(desteklenenSurum))"))
        }
        for (ad, deger) in [("paket_id", p.paket_id), ("ders", p.ders), ("bolum", p.bolum), ("alt_konu", p.alt_konu)] where bos(deger) {
            b.append(.init(ad, "boş olamaz"))
        }
        if p.levhalar.isEmpty { b.append(.init("levhalar", "en az bir levha olmalı")) }

        var levhaDugumleri: [String: Set<String>] = [:]
        for l in p.levhalar {
            let yer = "levha «\(l.id)»"
            if levhaDugumleri[l.id] != nil { b.append(.init(yer, "levha id tekrar ediyor")) }
            b += levhaDenetle(l, yer: yer)
            levhaDugumleri[l.id] = Set(dugumKimlikleri(l))
        }

        var soruIdleri = Set<String>()
        for s in p.sorular ?? [] {
            let yer = "soru «\(s.id)»"
            if !soruIdleri.insert(s.id).inserted { b.append(.init(yer, "soru id tekrar ediyor")) }
            if bos(s.kok) { b.append(.init(yer + " › kok", "boş olamaz")) }
            if bos(s.aciklama) { b.append(.init(yer + " › aciklama", "boş olamaz", engelleyici: false)) }
            if s.secenekler.count != 5 { b.append(.init(yer + " › secenekler", "5 seçenek olmalı (\(s.secenekler.count) var)")) }
            if !(0...4).contains(s.dogru) { b.append(.init(yer + " › dogru", "0–4 arasında olmalı (\(s.dogru))")) }
            guard let idler = levhaDugumleri[s.levha] else {
                b.append(.init(yer + " › levha", "bilinmeyen levha \"\(s.levha)\""))
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
        return b
    }

    static func levhaDenetle(_ l: LevhaJSON, yer: String) -> [LintBulgusu] {
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
        case .algoritma:
            guard let izgara = l.duzen?.izgara, izgara.count == 2, izgara[0] > 0, izgara[1] > 0 else {
                b.append(.init(yer + " › duzen.izgara", "algoritma için [sütun, satır] zorunlu"))
                break
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
            baglantilariDenetle(l, idler, yer, &b)

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
            guard let eksen = l.eksen else {
                b.append(.init(yer + " › eksen", "sayı cetveli için zorunlu"))
                break
            }
            if !(eksen.min < eksen.max) { b.append(.init(yer + " › eksen", "min, max'tan küçük olmalı")) }
            let isaretler = l.isaretler ?? []
            sayiDenetle(isaretler.count, dugumAraligi, "işaret sayısı", yer, &b)
            for m in isaretler {
                etiketDenetle(m.etiket, yer: "\(yer) › \(m.id).etiket", &b)
                if let v = m.deger, eksen.min < eksen.max, !(eksen.min...eksen.max).contains(v) {
                    b.append(.init("\(yer) › \(m.id).deger", "\(v) eksen aralığının (\(eksen.min)–\(eksen.max)) dışında"))
                }
            }

        default:
            // Part 2 tipleri: yalnız referans bütünlüğü.
            baglantilariDenetle(l, idler, yer, &b)
        }

        var gorulen = Set<String>()
        for id in l.ortme_sirasi ?? [] {
            if !idler.contains(id) { b.append(.init(yer + " › ortme_sirasi", "bilinmeyen düğüm \"\(id)\"")) }
            if !gorulen.insert(id).inserted { b.append(.init(yer + " › ortme_sirasi", "\(id) tekrar ediyor", engelleyici: false)) }
        }
        if l.tip.cizilebilir && gorulen.count < 3 {
            b.append(.init(yer + " › ortme_sirasi", "en az 3 düğüm olmalı", engelleyici: false))
        }

        for (i, s) in (l.sabotajlar ?? []).enumerated() {
            let syer = "\(yer) › sabotajlar[\(i)]"
            if s["tip"]?.metinDegeri == nil { b.append(.init(syer, "tip zorunlu", engelleyici: false)) }
            for h in s["hedef"]?.diziDegeri ?? [] {
                if let hid = h.metinDegeri, !idler.contains(hid) {
                    b.append(.init(syer + ".hedef", "bilinmeyen düğüm \"\(hid)\"", engelleyici: false))
                }
            }
        }
        return b
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
