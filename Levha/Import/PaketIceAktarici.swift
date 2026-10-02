import Foundation
import SwiftData

@MainActor
enum PaketIceAktarici {
    struct Sonuc {
        var dosyaAdi: String
        var basarili: Bool
        var paketId: String?
        var bulgular: [LintBulgusu]
        /// Konumları JSON'dan farklı geldiği hâlde eski düzeni korunan levhalar.
        var duzenKorunan: [String]
    }

    static func iceAktar(veri: Data, dosyaAdi: String, context: ModelContext) -> Sonuc {
        let denetim = LevhaLint.denetle(veri: veri)
        guard let json = denetim.paket, !denetim.engelleyiciVar else {
            return Sonuc(dosyaAdi: dosyaAdi, basarili: false, paketId: denetim.paket?.paket_id,
                         bulgular: denetim.bulgular.filter(\.engelleyici), duzenKorunan: [])
        }

        let hamLevhalar = (try? JSONDecoder().decode(HamPaketJSON.self, from: veri))?.levhalar ?? []
        let kodlayici = JSONEncoder()
        kodlayici.outputFormatting = [.sortedKeys]

        let pid = json.paket_id
        let paket: Paket
        if let mevcut = try? context.fetch(FetchDescriptor<Paket>(predicate: #Predicate { $0.paket_id == pid })).first {
            paket = mevcut
        } else {
            paket = Paket(paket_id: pid)
            context.insert(paket)
        }
        paket.sema_surumu = json.sema_surumu
        paket.ders = json.ders
        paket.bolum = json.bolum
        paket.alt_konu = json.alt_konu
        paket.dosyaAdi = dosyaAdi
        paket.iceAktarilma = .now

        var korunan: [String] = []
        var guncelIdler = Set<String>()
        for (i, lj) in json.levhalar.enumerated() {
            guncelIdler.insert(lj.id)
            let ham = i < hamLevhalar.count ? (try? kodlayici.encode(hamLevhalar[i])) ?? Data() : Data()
            if levhaYaz(lj, sira: i, ham: ham, paket: paket, context: context) { korunan.append(lj.id) }
        }
        for eski in paket.levhalar where !guncelIdler.contains(eski.id) {
            context.delete(eski)
        }

        // Kazanımlar ve aileler her zaman yeniden yazılır.
        for k in paket.kazanimlar { context.delete(k) }
        for a in paket.aileler { context.delete(a) }
        for (i, kj) in (json.kazanimlar ?? []).enumerated() {
            let k = Kazanim(kj, sira: i)
            context.insert(k)
            k.paket = paket
        }
        for (i, aj) in (json.aileler ?? []).enumerated() {
            let a = Aile(aj, sira: i)
            context.insert(a)
            a.paket = paket
        }

        // Sorular her zaman yeniden yazılır.
        for s in paket.sorular { context.delete(s) }
        let kazanimSozlugu = Dictionary((json.kazanimlar ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (i, sj) in (json.sorular ?? []).enumerated() {
            let s = Soru(sj, paketId: pid, sira: i)
            context.insert(s)
            s.paket = paket
            let k = sj.kazanim.flatMap { kazanimSozlugu[$0] }
            s.cozumle(ders: json.ders, kazanimKalibi: k?.kalip, kazanimSorulabilirligi: k?.sorulabilirlik)
        }
        SoruOnbellegi.temizle()

        do {
            try context.save()
        } catch {
            return Sonuc(dosyaAdi: dosyaAdi, basarili: false, paketId: pid,
                         bulgular: [LintBulgusu("", "kaydedilemedi: \(error.localizedDescription)")], duzenKorunan: [])
        }
        YedekServisi.bekleyenleriBagla(context)
        OlayDefteri.degisti()
        return Sonuc(dosyaAdi: dosyaAdi, basarili: true, paketId: pid,
                     bulgular: denetim.bulgular, duzenKorunan: korunan)
    }

    /// Levhayı oluşturur ya da günceller. Eski düzen korunduysa true döner.
    ///
    /// Düzen kuralı (v4): paketteki `revizyon` depodakinden büyükse paket kazanır (konumlar JSON'dan, yerel
    /// eklemeler silinir). Değilse aynı id'li ızgara levhasının yerleşimi ve taslaktan eklenen yerel düğümler korunur.
    private static func levhaYaz(_ lj: LevhaJSON, sira: Int, ham: Data, paket: Paket, context: ModelContext) -> Bool {
        let lid = lj.id
        let levha: Levha
        var eskiKonumlar: [String: [Int]] = [:]
        var eskiIzgara: [Int]?
        var eskiImza: String?
        var yerelDugumler: [DugumTaslagi] = []
        var yerelBaglantilar: [BaglantiJSON] = []
        let yeniRevizyon = lj.revizyon ?? 0

        if let mevcut = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == lid })).first {
            levha = mevcut
            let paketKazanir = yeniRevizyon > (mevcut.revizyon ?? 0)
            if mevcut.tip == lj.tip.rawValue, lj.tip.izgaraTabanli, !paketKazanir {
                for d in mevcut.dugumler { eskiKonumlar[d.id] = d.konum }
                eskiIzgara = mevcut.izgara
                eskiImza = mevcut.duzenImzasi
                yerelDugumler = mevcut.siraliDugumler.filter { $0.yerel == true }.map {
                    DugumTaslagi(id: $0.id, etiket: $0.etiket, sekil: $0.sekil, renk: $0.renk, konum: $0.konum,
                                 tus: $0.tus, not: $0.not, deger: nil)
                }
                yerelBaglantilar = mevcut.siraliBaglantilar.filter { $0.yerel == true }.map {
                    BaglantiJSON(from: $0.from, to: $0.to, etiket: $0.etiket.isEmpty ? nil : $0.etiket,
                                 tip: $0.tip.flatMap(BaglantiTipi.init(rawValue:)))
                }
            }
            if paketKazanir { mevcut.yerelRevizyon = 0 }
            levha.revizyon = max(yeniRevizyon, mevcut.revizyon ?? 0)
            for d in mevcut.dugumler { context.delete(d) }
            for b in mevcut.baglantilar { context.delete(b) }
        } else {
            levha = Levha(id: lj.id)
            levha.revizyon = yeniRevizyon
            context.insert(levha)
        }
        levha.paket = paket
        levha.tip = lj.tip.rawValue
        levha.baslik = lj.baslik
        levha.akilda_kalan = lj.akilda_kalan
        levha.sira = sira
        levha.ortme_sirasi = lj.ortme_sirasi ?? []
        levha.satirlar = lj.satirlar ?? []
        levha.sutunlar = lj.sutunlar ?? []
        levha.eksenMin = lj.eksen?.min ?? 0
        levha.eksenMax = lj.eksen?.max ?? 1
        levha.eksenBirim = lj.eksen?.birim ?? ""
        levha.seritIdleri = lj.seritler?.map(\.id)
        levha.seritAdlari = lj.seritler?.map(\.ad)
        levha.sabotajlar = lj.sabotajlar.flatMap { try? JSONEncoder().encode($0) }
        levha.insa_sirasi = lj.insa_sirasi
        levha.kaynak = lj.kaynak.flatMap { try? JSONEncoder().encode($0) }
        levha.hamJSON = ham

        var dugumler = dugumListesi(lj)
        let yeniIzgara = izgara(lj)
        let yeniImza = duzenImzasi(tip: lj.tip, izgara: yeniIzgara, dugumler: dugumler, levha: lj)

        var izgara = yeniIzgara
        var korundu = false
        if let eskiIzgara, let eskiImza, eskiImza != yeniImza {
            korundu = true
            izgara = eskiIzgara
            for i in dugumler.indices {
                if let eski = eskiKonumlar[dugumler[i].id] { dugumler[i].konum = eski }
            }
            // Yeni eklenen düğüm eski ızgaraya sığmıyorsa ızgara büyür, kimse yer değiştirmez.
            for d in dugumler where d.konum.count == 2 {
                izgara[0] = max(izgara[0], d.konum[0] + 1)
                izgara[1] = max(izgara[1], d.konum[1] + 1)
            }
        }
        levha.izgara = izgara
        levha.duzenImzasi = duzenImzasi(tip: lj.tip, izgara: izgara, dugumler: dugumler, levha: lj)

        // Yerel düğümler, paketle id ya da konum çakışmıyorsa geri eklenir.
        let paketIdleri = Set(dugumler.map(\.id))
        var doluKonum = Set(dugumler.map { $0.konum.map(String.init).joined(separator: ",") })
        var yerelIdler = Set<String>()
        for var d in yerelDugumler where !paketIdleri.contains(d.id) && doluKonum.insert(d.konum.map(String.init).joined(separator: ",")).inserted {
            d.yerel = true
            dugumler.append(d)
            yerelIdler.insert(d.id)
            if d.konum.count == 2 {
                izgara[0] = max(izgara[0], d.konum[0] + 1)
                izgara[1] = max(izgara[1], d.konum[1] + 1)
            }
        }
        levha.izgara = izgara
        let tumIdler = paketIdleri.union(yerelIdler)

        for (i, d) in dugumler.enumerated() {
            let dugum = Dugum(id: d.id, etiket: d.etiket, sekil: d.sekil, renk: d.renk, konum: d.konum,
                              tus: d.tus, not: d.not, deger: d.deger, sira: i)
            dugum.bit = d.bit
            dugum.serit = d.serit
            dugum.bolge = d.bolge
            dugum.yerel = d.yerel ? true : nil
            context.insert(dugum)
            dugum.levha = levha
        }
        var baglantilar = baglantiListesi(lj).map { ($0, false) }
        baglantilar += yerelBaglantilar.filter { tumIdler.contains($0.from) && tumIdler.contains($0.to) }.map { ($0, true) }
        for (i, (b, yerel)) in baglantilar.enumerated() {
            let bag = Baglanti(from: b.from, to: b.to, etiket: b.etiket ?? "", tip: b.tip?.rawValue, sira: i)
            bag.yerel = yerel ? true : nil
            context.insert(bag)
            bag.levha = levha
        }
        if yerelIdler.isEmpty { levha.yerelRevizyon = 0 }
        return korundu
    }

    private struct DugumTaslagi {
        var id: String
        var etiket: String
        var sekil: String
        var renk: String
        var konum: [Int]
        var tus: Bool
        var not: String
        var deger: Double?
        var bit: Double?
        var serit: String?
        var bolge: String?
        var yerel = false
    }

    /// Ağaçta bağlantısı verilmemiş her `ebeveyn` ilişkisi normal bir kenara dönüşür.
    private static func baglantiListesi(_ lj: LevhaJSON) -> [BaglantiJSON] {
        var liste = lj.baglantilar ?? []
        guard lj.tip == .agac else { return liste }
        let mevcut = Set(liste.map { "\($0.from)>\($0.to)" })
        for d in lj.dugumler ?? [] {
            if let e = d.ebeveyn, !mevcut.contains("\(e)>\(d.id)") {
                liste.append(BaglantiJSON(from: e, to: d.id, etiket: nil, tip: nil))
            }
        }
        return liste
    }

    /// Her tipi ortak düğüm listesine indirger: matris hücreleri ve cetvel işaretleri de düğümdür.
    private static func dugumListesi(_ lj: LevhaJSON) -> [DugumTaslagi] {
        switch lj.tip {
        case .matris:
            var sonuc: [DugumTaslagi] = []
            for (r, satir) in (lj.hucreler ?? []).enumerated() {
                for (c, h) in satir.enumerated() {
                    sonuc.append(DugumTaslagi(id: "r\(r)c\(c)", etiket: h.metin, sekil: DugumSekli.durum.rawValue,
                                              renk: (h.renk ?? .gri).rawValue, konum: [c, r], tus: h.tus ?? false,
                                              not: h.not ?? "", deger: nil))
                }
            }
            return sonuc
        case .sayi_cetveli:
            return (lj.isaretler ?? []).map {
                DugumTaslagi(id: $0.id, etiket: $0.etiket, sekil: DugumSekli.durum.rawValue, renk: ($0.renk ?? .gri).rawValue,
                             konum: [], tus: $0.tus ?? false, not: $0.not ?? "", deger: $0.deger)
            }
        case .zaman_cizelgesi:
            return (lj.olaylar ?? []).map {
                DugumTaslagi(id: $0.id, etiket: $0.etiket, sekil: DugumSekli.durum.rawValue, renk: ($0.renk ?? .gri).rawValue,
                             konum: [], tus: $0.tus ?? false, not: $0.not ?? "", deger: $0.bas, bit: $0.bit, serit: $0.serit)
            }
        case .vucut_haritasi:
            return (lj.bolgeler ?? []).map {
                DugumTaslagi(id: $0.id, etiket: $0.etiket, sekil: DugumSekli.durum.rawValue, renk: ($0.renk ?? .gri).rawValue,
                             konum: [], tus: $0.tus ?? false, not: $0.not ?? "", deger: nil, bolge: $0.bolge.rawValue)
            }
        case .algoritma, .yolak, .agac:
            return (lj.dugumler ?? []).map {
                DugumTaslagi(id: $0.id, etiket: $0.etiket, sekil: ($0.sekil ?? .durum).rawValue, renk: ($0.renk ?? .gri).rawValue,
                             konum: $0.konum ?? [], tus: $0.tus ?? false, not: $0.not ?? "", deger: nil)
            }
        }
    }

    private static func izgara(_ lj: LevhaJSON) -> [Int] {
        switch lj.tip {
        case .matris: return [lj.sutunlar?.count ?? 0, lj.satirlar?.count ?? 0]
        default: return lj.duzen?.izgara ?? [0, 0]
        }
    }

    private static func duzenImzasi(tip: LevhaTipi, izgara: [Int], dugumler: [DugumTaslagi], levha lj: LevhaJSON) -> String {
        var parcalar = ["\(tip.rawValue)|\(izgara.map(String.init).joined(separator: "x"))"]
        switch tip {
        case .sayi_cetveli:
            parcalar.append("\(lj.eksen?.min ?? 0)-\(lj.eksen?.max ?? 0)")
            parcalar += dugumler.map { "\($0.id)@\($0.deger.map { "\($0)" } ?? "-")" }.sorted()
        case .matris:
            parcalar += (lj.satirlar ?? []) + (lj.sutunlar ?? [])
        case .zaman_cizelgesi:
            parcalar.append("\(lj.eksen?.min ?? 0)-\(lj.eksen?.max ?? 0)")
            parcalar += dugumler.map { "\($0.id)@\($0.serit ?? "")@\($0.deger ?? 0)-\($0.bit.map { "\($0)" } ?? "")" }.sorted()
        case .vucut_haritasi:
            parcalar += dugumler.map { "\($0.id)@\($0.bolge ?? "")" }
        default:
            parcalar += dugumler.map { "\($0.id)@\($0.konum.map(String.init).joined(separator: ","))" }.sorted()
        }
        return fnv1a(parcalar.joined(separator: "|"))
    }

    private static func fnv1a(_ metin: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for bayt in metin.utf8 {
            h ^= UInt64(bayt)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
