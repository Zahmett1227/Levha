import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let levhaYedek = UTType(exportedAs: "tr.kisisel.levha.yedek")
}

/// `.levhayedek`: zip içinde `yedek.json`. Uygulamanın ürettiği her şey (olaylar, durumlar, notlar, sohbet,
/// taslaklar, Yazdıklarım, yerel düğümler, A/B, ayarlar); API anahtarı ve paket içeriği HARİÇ.
struct YedekPaketi: Codable {
    var surum = 1
    var olusturma: Date
    var ortme: [OrtmeK] = []
    var soru: [SoruOlayiK] = []
    var sabotaj: [SabotajK] = []
    var insa: [InsaK] = []
    var ipucu: [IpucuK] = []
    var editor: [EditorK] = []
    var sinav: [SinavK] = []
    var llm: [LLMK] = []
    var kullanim: [KullanimK] = []
    var tur: [TurK] = []
    var levhaDurumu: [LevhaDurumuK] = []
    var zayiflik: [ZayiflikK] = []
    var notlar: [NotK] = []
    var sorKayitlari: [SorK] = []
    var taslaklar: [TaslakK] = []
    var yazdiklarim: [YazdigimK] = []
    var yerelEkler: [YerelEkK] = []
    var abGruplar: [ABK] = []
    var ayarlar: AyarlarK?
    /// v5: bağımsız soru zayıflıkları (eski yedeklerde yok).
    var konuZayiflik: [KonuZayiflikK]?

    /// Özet ve "olay sayıları eşit mi?" denetimi için.
    var olaySayisi: Int { ortme.count + soru.count + sabotaj.count + insa.count + ipucu.count + editor.count + sinav.count + llm.count }

    // MARK: Kayıtlar

    struct OrtmeK: Codable { var levhaId, dugumId: String; var tarih: Date; var bildim: Bool; var abGrup: String? }
    struct SoruOlayiK: Codable {
        var soruGlobalId, levhaId: String; var secilen: Int; var dogruMu: Bool; var sureSaniye: Double; var tarih: Date
        var guven: Int?; var kalipTahmini: String?; var ipucuTahminiIndeks: Int?; var kirmaSuresi: Double?
        var baglam: String?; var abGrup: String?
    }
    struct SabotajK: Codable { var levhaId, sabotajTipi: String; var bulundu: Bool; var denemeSayisi: Int; var tarih: Date }
    struct InsaK: Codable { var levhaId: String; var hataSayisi, toplam: Int; var sureSaniye: Double; var tarih: Date }
    struct IpucuK: Codable { var soruGlobalId: String; var ipucuIndeks, toplamIpucu: Int; var dogru: Bool; var puan: Int; var tarih: Date }
    struct EditorK: Codable { var levhaId: String; var puan: Int?; var kaydedildi: Bool; var tarih: Date }
    struct SinavK: Codable {
        var tarih: Date; var soruSayisi: Int; var net: Double; var dogru, yanlis, bos: Int; var sureSaniye: Double
        var dersler: [String]; var tahminBeklenen, tahminAlt, tahminUst: Double?; var detay: Data?
    }
    struct LLMK: Codable { var tarih: Date; var giris, cikis: Int; var amac: String }
    struct KullanimK: Codable { var gun: String; var saniye: Double }
    struct TurK: Codable {
        var gun, calismaYeri: String; var altKonuPaketId: String?; var kisa: Bool; var tamamlananlar: [String]; var kuyruk: Data?
    }
    struct LevhaDurumuK: Codable { var levhaId: String; var kutu: Int; var sonrakiTarih: Date?; var saglamlik: Double; var sonGorulme: Date? }
    struct ZayiflikK: Codable { var levhaId, dugumId: String; var sayac: Int }
    struct KonuZayiflikK: Codable {
        var anahtar, ders, altKonu: String; var kazanimId, kazanimMetni: String?; var yanlis, dogru: Int; var sonTarih: Date
    }
    struct NotK: Codable { var levhaId, dugumId, metin: String; var tarih: Date }
    struct SorK: Codable { var levhaId: String; var dugumId: String?; var soru, cevap: String; var tarih: Date }
    struct TaslakK: Codable { var levhaId: String; var tarih: Date; var ham: String; var json: Data?; var hatalar: [String]; var eklendi: Bool }
    struct YazdigimK: Codable {
        var soru: SoruJSON; var levhaPaketId: String?; var konuDers: String?; var kalipCozulmus: String?; var sorulabilirlikDegeri: Int?
    }
    struct YerelEkK: Codable { var levhaId: String; var yerelRevizyon: Int; var dugumler: [DugumJSON]; var baglantilar: [BaglantiJSON] }
    struct ABK: Codable { var paketId, grup: String; var atamaTarihi: Date }
    struct AyarlarK: Codable {
        var dagilim: [String: Int]; var ceza: Double; var calismaYeri: String?; var soruKirmaAcik: Bool; var kirmaSuresi: Double
        var saglayici: String; var tabanURL: String; var modelAdi: String; var apiBicimi: String; var maxCikisToken: Int; var sicaklik: Double
        var muhakeme: String?
    }
}

@MainActor
enum YedekServisi {
    enum Kip { case birlestir, uzerineYaz }

    struct Ozet {
        var tarih: Date
        var olay: Int
        var not: Int
        var yazilmisSoru: Int
        var taslak: Int
        var sohbet: Int
        var bekleyen: Int = 0

        var metin: String {
            "\(Bicim.sayi(Double(olay))) olay, \(not) not, \(yazilmisSoru) yazılmış soru, \(taslak) taslak, \(sohbet) sohbet kaydı"
        }
    }

    static let gunlukAnahtar = "sonOtomatikYedek"
    static let tutulacakGun = 7

    // MARK: - Yedekle

    static func paket(_ context: ModelContext) -> YedekPaketi {
        func al<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var y = YedekPaketi(olusturma: .now)
        y.ortme = al(OrtmeOlayi.self).map { .init(levhaId: $0.levhaId, dugumId: $0.dugumId, tarih: $0.tarih, bildim: $0.bildim, abGrup: $0.abGrup) }
        y.soru = al(SoruOlayi.self).map {
            .init(soruGlobalId: $0.soruGlobalId, levhaId: $0.levhaId, secilen: $0.secilen, dogruMu: $0.dogruMu, sureSaniye: $0.sureSaniye,
                  tarih: $0.tarih, guven: $0.guven, kalipTahmini: $0.kalipTahmini, ipucuTahminiIndeks: $0.ipucuTahminiIndeks,
                  kirmaSuresi: $0.kirmaSuresi, baglam: $0.baglam, abGrup: $0.abGrup)
        }
        y.sabotaj = al(SabotajOlayi.self).map { .init(levhaId: $0.levhaId, sabotajTipi: $0.sabotajTipi, bulundu: $0.bulundu, denemeSayisi: $0.denemeSayisi, tarih: $0.tarih) }
        y.insa = al(InsaOlayi.self).map { .init(levhaId: $0.levhaId, hataSayisi: $0.hataSayisi, toplam: $0.toplam, sureSaniye: $0.sureSaniye, tarih: $0.tarih) }
        y.ipucu = al(IpucuOlayi.self).map { .init(soruGlobalId: $0.soruGlobalId, ipucuIndeks: $0.ipucuIndeks, toplamIpucu: $0.toplamIpucu, dogru: $0.dogru, puan: $0.puan, tarih: $0.tarih) }
        y.editor = al(EditorOlayi.self).map { .init(levhaId: $0.levhaId, puan: $0.puan, kaydedildi: $0.kaydedildi, tarih: $0.tarih) }
        y.sinav = al(SinavOlayi.self).map {
            .init(tarih: $0.tarih, soruSayisi: $0.soruSayisi, net: $0.net, dogru: $0.dogru, yanlis: $0.yanlis, bos: $0.bos, sureSaniye: $0.sureSaniye,
                  dersler: $0.dersler, tahminBeklenen: $0.tahminBeklenen, tahminAlt: $0.tahminAlt, tahminUst: $0.tahminUst, detay: $0.detay)
        }
        y.llm = al(LLMKullanim.self).map { .init(tarih: $0.tarih, giris: $0.giris, cikis: $0.cikis, amac: $0.amac) }
        y.kullanim = al(KullanimKaydi.self).map { .init(gun: $0.gun, saniye: $0.saniye) }
        y.tur = al(TurDurumu.self).map { .init(gun: $0.gun, calismaYeri: $0.calismaYeri, altKonuPaketId: $0.altKonuPaketId, kisa: $0.kisa, tamamlananlar: $0.tamamlananlar, kuyruk: $0.kuyruk) }
        y.levhaDurumu = al(LevhaDurumu.self).map { .init(levhaId: $0.levhaId, kutu: $0.kutu, sonrakiTarih: $0.sonrakiTarih, saglamlik: $0.saglamlik, sonGorulme: $0.sonGorulme) }
        y.zayiflik = al(DugumZayiflik.self).map { .init(levhaId: $0.levhaId, dugumId: $0.dugumId, sayac: $0.sayac) }
        y.konuZayiflik = al(KonuZayiflik.self).map {
            .init(anahtar: $0.anahtar, ders: $0.ders, altKonu: $0.altKonu, kazanimId: $0.kazanimId, kazanimMetni: $0.kazanimMetni,
                  yanlis: $0.yanlis, dogru: $0.dogru, sonTarih: $0.sonTarih)
        }
        y.notlar = al(DugumNotu.self).map { .init(levhaId: $0.levhaId, dugumId: $0.dugumId, metin: $0.metin, tarih: $0.tarih) }
        y.sorKayitlari = al(SorKaydi.self).map { .init(levhaId: $0.levhaId, dugumId: $0.dugumId, soru: $0.soru, cevap: $0.cevap, tarih: $0.tarih) }
        y.taslaklar = al(Taslak.self).map { .init(levhaId: $0.levhaId, tarih: $0.tarih, ham: $0.ham, json: $0.json, hatalar: $0.hatalar, eklendi: $0.eklendi) }
        y.yazdiklarim = al(Soru.self).filter(\.kullaniciSorusu).map {
            .init(soru: $0.json, levhaPaketId: $0.levhaPaketId, konuDers: $0.konuDers, kalipCozulmus: $0.kalipCozulmus, sorulabilirlikDegeri: $0.sorulabilirlikDegeri)
        }
        y.yerelEkler = al(Levha.self).compactMap { l in
            let d = l.siraliDugumler.filter { $0.yerel == true }
            guard !d.isEmpty else { return nil }
            return .init(levhaId: l.id, yerelRevizyon: l.yerelRevizyon ?? 0,
                         dugumler: d.map { DugumJSON(id: $0.id, etiket: $0.etiket, sekil: DugumSekli(rawValue: $0.sekil), renk: RenkAdi(rawValue: $0.renk),
                                                     konum: $0.konum, tus: $0.tus, not: $0.not, ebeveyn: nil) },
                         baglantilar: l.siraliBaglantilar.filter { $0.yerel == true }.map {
                             BaglantiJSON(from: $0.from, to: $0.to, etiket: $0.etiket.isEmpty ? nil : $0.etiket, tip: $0.tip.flatMap(BaglantiTipi.init(rawValue:)))
                         })
        }
        y.abGruplar = al(ABGrup.self).map { .init(paketId: $0.paketId, grup: $0.grup, atamaTarihi: $0.atamaTarihi) }
        let d = UserDefaults.standard
        y.ayarlar = .init(dagilim: SinavAyarlari.dagilim, ceza: SinavAyarlari.ceza, calismaYeri: d.string(forKey: "calismaYeri"),
                          soruKirmaAcik: SoruKirmaAyari.acik, kirmaSuresi: SoruKirmaAyari.sure,
                          saglayici: LLMAyarlari.saglayici.rawValue, tabanURL: LLMAyarlari.apiTabanURL, modelAdi: LLMAyarlari.modelAdi,
                          apiBicimi: LLMAyarlari.apiBicimi.rawValue, maxCikisToken: LLMAyarlari.maxCikisToken, sicaklik: LLMAyarlari.sicaklik,
                          muhakeme: LLMAyarlari.muhakeme.rawValue)
        return y
    }

    static func veri(_ context: ModelContext) throws -> Data {
        let json = try JSONEncoder().encode(paket(context))
        return ZipArsiv.yaz([.init(ad: "yedek.json", veri: json)])
    }

    /// Paylaşım için geçici dosya.
    static func dosya(_ context: ModelContext) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "levha-yedek-\(DurumServisi.gunAnahtari()).levhayedek")
        try veri(context).write(to: url, options: .atomic)
        return url
    }

    static func coz(_ veri: Data) throws -> YedekPaketi {
        guard let giris = try ZipArsiv.oku(veri).first(where: { $0.ad == "yedek.json" }) else { throw ZipArsiv.Hata.bozuk("yedek.json yok") }
        return try JSONDecoder().decode(YedekPaketi.self, from: giris.veri)
    }

    static func ozet(_ y: YedekPaketi) -> Ozet {
        Ozet(tarih: y.olusturma, olay: y.olaySayisi, not: y.notlar.count, yazilmisSoru: y.yazdiklarim.count,
             taslak: y.taslaklar.count, sohbet: y.sorKayitlari.count)
    }

    // MARK: - Geri yükle

    /// Birleştir: aynı kimlikli kayıtlar atlanır. Üzerine yaz: uygulamanın ürettiği her şey silinip yedekten yazılır.
    /// Levhası henüz içe aktarılmamış yerel düğüm ekleri bekleme listesine alınır.
    @discardableResult
    static func geriYukle(_ y: YedekPaketi, kip: Kip, _ context: ModelContext) -> Ozet {
        if kip == .uzerineYaz { kullaniciVerisiniSil(context) }
        func al<T: PersistentModel>(_ t: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        func ts(_ d: Date) -> String { String(d.timeIntervalSinceReferenceDate) }
        let birlestir = kip == .birlestir

        var mevcut = Set(birlestir ? al(OrtmeOlayi.self).map { "\($0.levhaId)|\($0.dugumId)|\(ts($0.tarih))" } : [])
        for k in y.ortme where mevcut.insert("\(k.levhaId)|\(k.dugumId)|\(ts(k.tarih))").inserted {
            let o = OrtmeOlayi(levhaId: k.levhaId, dugumId: k.dugumId, tarih: k.tarih, bildim: k.bildim)
            o.abGrup = k.abGrup
            context.insert(o)
        }
        mevcut = Set(birlestir ? al(SoruOlayi.self).map { "\($0.soruGlobalId)|\(ts($0.tarih))" } : [])
        for k in y.soru where mevcut.insert("\(k.soruGlobalId)|\(ts(k.tarih))").inserted {
            let o = SoruOlayi(soruGlobalId: k.soruGlobalId, levhaId: k.levhaId, secilen: k.secilen, dogruMu: k.dogruMu,
                              sureSaniye: k.sureSaniye, tarih: k.tarih, guven: k.guven)
            o.kalipTahmini = k.kalipTahmini
            o.ipucuTahminiIndeks = k.ipucuTahminiIndeks
            o.kirmaSuresi = k.kirmaSuresi
            o.baglam = k.baglam
            o.abGrup = k.abGrup
            context.insert(o)
        }
        mevcut = Set(birlestir ? al(SabotajOlayi.self).map { "\($0.levhaId)|\(ts($0.tarih))" } : [])
        for k in y.sabotaj where mevcut.insert("\(k.levhaId)|\(ts(k.tarih))").inserted {
            context.insert(SabotajOlayi(levhaId: k.levhaId, sabotajTipi: k.sabotajTipi, bulundu: k.bulundu, denemeSayisi: k.denemeSayisi, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(InsaOlayi.self).map { "\($0.levhaId)|\(ts($0.tarih))" } : [])
        for k in y.insa where mevcut.insert("\(k.levhaId)|\(ts(k.tarih))").inserted {
            context.insert(InsaOlayi(levhaId: k.levhaId, hataSayisi: k.hataSayisi, toplam: k.toplam, sureSaniye: k.sureSaniye, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(IpucuOlayi.self).map { "\($0.soruGlobalId)|\(ts($0.tarih))" } : [])
        for k in y.ipucu where mevcut.insert("\(k.soruGlobalId)|\(ts(k.tarih))").inserted {
            context.insert(IpucuOlayi(soruGlobalId: k.soruGlobalId, ipucuIndeks: k.ipucuIndeks, toplamIpucu: k.toplamIpucu, dogru: k.dogru, puan: k.puan, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(EditorOlayi.self).map { "\($0.levhaId)|\(ts($0.tarih))" } : [])
        for k in y.editor where mevcut.insert("\(k.levhaId)|\(ts(k.tarih))").inserted {
            context.insert(EditorOlayi(levhaId: k.levhaId, puan: k.puan, kaydedildi: k.kaydedildi, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(SinavOlayi.self).map { ts($0.tarih) } : [])
        for k in y.sinav where mevcut.insert(ts(k.tarih)).inserted {
            let s = SinavOlayi(tarih: k.tarih, soruSayisi: k.soruSayisi, net: k.net, dogru: k.dogru, yanlis: k.yanlis, bos: k.bos,
                               sureSaniye: k.sureSaniye, dersler: k.dersler)
            s.tahminBeklenen = k.tahminBeklenen
            s.tahminAlt = k.tahminAlt
            s.tahminUst = k.tahminUst
            s.detay = k.detay
            context.insert(s)
        }
        mevcut = Set(birlestir ? al(LLMKullanim.self).map { "\(ts($0.tarih))|\($0.amac)" } : [])
        for k in y.llm where mevcut.insert("\(ts(k.tarih))|\(k.amac)").inserted {
            context.insert(LLMKullanim(tarih: k.tarih, giris: k.giris, cikis: k.cikis, amac: k.amac))
        }
        mevcut = Set(birlestir ? al(KullanimKaydi.self).map(\.gun) : [])
        for k in y.kullanim where mevcut.insert(k.gun).inserted { context.insert(KullanimKaydi(gun: k.gun, saniye: k.saniye)) }
        mevcut = Set(birlestir ? al(TurDurumu.self).map(\.gun) : [])
        for k in y.tur where mevcut.insert(k.gun).inserted {
            let t = TurDurumu(gun: k.gun, calismaYeri: k.calismaYeri)
            t.altKonuPaketId = k.altKonuPaketId
            t.kisa = k.kisa
            t.tamamlananlar = k.tamamlananlar
            t.kuyruk = k.kuyruk
            context.insert(t)
        }
        mevcut = Set(birlestir ? al(LevhaDurumu.self).map(\.levhaId) : [])
        for k in y.levhaDurumu where mevcut.insert(k.levhaId).inserted {
            let d = LevhaDurumu(levhaId: k.levhaId)
            d.kutu = k.kutu
            d.sonrakiTarih = k.sonrakiTarih
            d.saglamlik = k.saglamlik
            d.sonGorulme = k.sonGorulme
            context.insert(d)
        }
        mevcut = Set(birlestir ? al(DugumZayiflik.self).map { "\($0.levhaId)|\($0.dugumId)" } : [])
        for k in y.zayiflik where mevcut.insert("\(k.levhaId)|\(k.dugumId)").inserted {
            context.insert(DugumZayiflik(levhaId: k.levhaId, dugumId: k.dugumId, sayac: k.sayac))
        }
        mevcut = Set(birlestir ? al(KonuZayiflik.self).map(\.anahtar) : [])
        for k in y.konuZayiflik ?? [] where mevcut.insert(k.anahtar).inserted {
            let z = KonuZayiflik(anahtar: k.anahtar, ders: k.ders, altKonu: k.altKonu, kazanimId: k.kazanimId, kazanimMetni: k.kazanimMetni)
            z.yanlis = k.yanlis
            z.dogru = k.dogru
            z.sonTarih = k.sonTarih
            context.insert(z)
        }
        mevcut = Set(birlestir ? al(DugumNotu.self).map { "\($0.levhaId)|\($0.dugumId)|\(ts($0.tarih))" } : [])
        for k in y.notlar where mevcut.insert("\(k.levhaId)|\(k.dugumId)|\(ts(k.tarih))").inserted {
            context.insert(DugumNotu(levhaId: k.levhaId, dugumId: k.dugumId, metin: k.metin, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(SorKaydi.self).map { "\($0.levhaId)|\(ts($0.tarih))" } : [])
        for k in y.sorKayitlari where mevcut.insert("\(k.levhaId)|\(ts(k.tarih))").inserted {
            context.insert(SorKaydi(levhaId: k.levhaId, dugumId: k.dugumId, soru: k.soru, cevap: k.cevap, tarih: k.tarih))
        }
        mevcut = Set(birlestir ? al(Taslak.self).map { "\($0.levhaId)|\(ts($0.tarih))" } : [])
        for k in y.taslaklar where mevcut.insert("\(k.levhaId)|\(ts(k.tarih))").inserted {
            let t = Taslak(levhaId: k.levhaId, tarih: k.tarih, ham: k.ham, json: k.json, hatalar: k.hatalar)
            t.eklendi = k.eklendi
            context.insert(t)
        }
        if !y.yazdiklarim.isEmpty {
            let paket = EditorView.kullaniciPaketi(context)
            mevcut = Set(birlestir ? paket.sorular.map(\.kimlik) : [])
            for k in y.yazdiklarim where mevcut.insert("\(Paket.kullaniciId).\(k.soru.id)").inserted {
                let s = Soru(k.soru, paketId: Paket.kullaniciId, sira: paket.sorular.count)
                s.kaynakTuru = Paket.kullaniciKaynak
                s.levhaPaketId = k.levhaPaketId
                s.cozumle(ders: k.konuDers, kazanimKalibi: k.kalipCozulmus, kazanimSorulabilirligi: k.sorulabilirlikDegeri)
                context.insert(s)
                s.paket = paket
            }
        }
        var bekleyen = 0
        for k in y.yerelEkler where !yerelEkUygula(k, birlestir: birlestir, context) {
            if let v = try? JSONEncoder().encode(k) {
                context.insert(BekleyenYedek(levhaId: k.levhaId, tur: "yerelEk", veri: v, tarih: .now))
                bekleyen += 1
            }
        }
        mevcut = Set(birlestir ? al(ABGrup.self).map(\.paketId) : [])
        for k in y.abGruplar where mevcut.insert(k.paketId).inserted {
            context.insert(ABGrup(paketId: k.paketId, grup: k.grup, atamaTarihi: k.atamaTarihi))
        }
        if let a = y.ayarlar, kip == .uzerineYaz || UserDefaults.standard.object(forKey: "sinavDagilimi") == nil {
            SinavAyarlari.dagilim = a.dagilim
            SinavAyarlari.ceza = a.ceza
            let d = UserDefaults.standard
            if let yer = a.calismaYeri { d.set(yer, forKey: "calismaYeri") }
            d.set(a.soruKirmaAcik, forKey: SoruKirmaAyari.anahtar)
            d.set(a.kirmaSuresi, forKey: "kirmaSuresi")
            LLMAyarlari.saglayici = LLMSaglayici(rawValue: a.saglayici) ?? .sahte
            LLMAyarlari.apiTabanURL = a.tabanURL
            LLMAyarlari.modelAdi = a.modelAdi
            LLMAyarlari.apiBicimi = APIBicimi(rawValue: a.apiBicimi) ?? .responses
            LLMAyarlari.maxCikisToken = a.maxCikisToken
            LLMAyarlari.sicaklik = a.sicaklik
            if let m = a.muhakeme.flatMap(MuhakemeDuzeyi.init(rawValue:)) { LLMAyarlari.muhakeme = m }
            LLMAyarlari.denetle()
        }
        try? context.save()
        // Sağlamlık olay geçmişinden yeniden hesaplanır.
        for levhaId in Set(y.ortme.map(\.levhaId) + y.soru.map(\.levhaId) + y.sabotaj.map(\.levhaId) + y.insa.map(\.levhaId)) {
            DurumServisi.saglamlikGuncelle(levhaId, context)
        }
        try? context.save()
        ABDeneyi.ortak.yukle(context)
        SoruOnbellegi.temizle()
        OlayDefteri.degisti()
        var o = ozet(y)
        o.bekleyen = bekleyen
        return o
    }

    /// Yerel düğüm ekini levhaya uygular; levha yoksa false (bekleme listesine).
    private static func yerelEkUygula(_ k: YedekPaketi.YerelEkK, birlestir: Bool, _ context: ModelContext) -> Bool {
        let lid = k.levhaId
        guard let levha = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == lid })).first else { return false }
        var idler = Set(levha.dugumler.map(\.id))
        var dolu = Set(levha.dugumler.map { $0.konum.map(String.init).joined(separator: ",") })
        var sira = (levha.dugumler.map(\.sira).max() ?? -1) + 1
        var izgara = levha.izgara
        for d in k.dugumler {
            let konum = d.konum ?? []
            guard idler.insert(d.id).inserted, dolu.insert(konum.map(String.init).joined(separator: ",")).inserted else { continue }
            let dugum = Dugum(id: d.id, etiket: d.etiket, sekil: (d.sekil ?? .durum).rawValue, renk: (d.renk ?? .gri).rawValue,
                              konum: konum, tus: d.tus ?? false, not: d.not ?? "", deger: nil, sira: sira)
            dugum.yerel = true
            context.insert(dugum)
            dugum.levha = levha
            sira += 1
            if konum.count == 2, izgara.count == 2 {
                izgara[0] = max(izgara[0], konum[0] + 1)
                izgara[1] = max(izgara[1], konum[1] + 1)
            }
        }
        let mevcutBag = Set(levha.baglantilar.map { "\($0.from)>\($0.to)" })
        var bsira = (levha.baglantilar.map(\.sira).max() ?? -1) + 1
        for b in k.baglantilar where idler.contains(b.from) && idler.contains(b.to) && !mevcutBag.contains("\(b.from)>\(b.to)") {
            let bag = Baglanti(from: b.from, to: b.to, etiket: b.etiket ?? "", tip: b.tip?.rawValue, sira: bsira)
            bag.yerel = true
            context.insert(bag)
            bag.levha = levha
            bsira += 1
        }
        levha.izgara = izgara
        levha.yerelRevizyon = max(levha.yerelRevizyon ?? 0, k.yerelRevizyon)
        return true
    }

    /// Paket içe aktarılınca: bekleyen yerel ekler levhalarına bağlanır.
    static func bekleyenleriBagla(_ context: ModelContext) {
        let bekleyenler = (try? context.fetch(FetchDescriptor<BekleyenYedek>())) ?? []
        guard !bekleyenler.isEmpty else { return }
        for b in bekleyenler where b.tur == "yerelEk" {
            guard let k = try? JSONDecoder().decode(YedekPaketi.YerelEkK.self, from: b.veri) else { context.delete(b); continue }
            if yerelEkUygula(k, birlestir: true, context) { context.delete(b) }
        }
        try? context.save()
    }

    private static func kullaniciVerisiniSil(_ context: ModelContext) {
        func sil<T: PersistentModel>(_ t: T.Type) { for x in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(x) } }
        sil(OrtmeOlayi.self); sil(SoruOlayi.self); sil(SabotajOlayi.self); sil(InsaOlayi.self); sil(IpucuOlayi.self)
        sil(EditorOlayi.self); sil(SinavOlayi.self); sil(LLMKullanim.self); sil(KullanimKaydi.self); sil(TurDurumu.self)
        sil(LevhaDurumu.self); sil(DugumZayiflik.self); sil(DugumNotu.self); sil(SorKaydi.self); sil(Taslak.self)
        sil(ABGrup.self); sil(BekleyenYedek.self); sil(KonuZayiflik.self)
        for s in ((try? context.fetch(FetchDescriptor<Soru>())) ?? []) where s.kullaniciSorusu { context.delete(s) }
        for d in ((try? context.fetch(FetchDescriptor<Dugum>())) ?? []) where d.yerel == true { context.delete(d) }
        for b in ((try? context.fetch(FetchDescriptor<Baglanti>())) ?? []) where b.yerel == true { context.delete(b) }
        for l in ((try? context.fetch(FetchDescriptor<Levha>())) ?? []) where (l.yerelRevizyon ?? 0) > 0 { l.yerelRevizyon = 0 }
        try? context.save()
    }

    // MARK: - Gece otomatik yedeği

    /// Gün 04:00'te döner; dönüşten sonraki ilk açılışta `Levha/Yedek/` klasörüne tarihli yedek yazılır,
    /// en yeni 7 dosya kalır.
    static func otomatik(klasor: PaketKlasoru, _ context: ModelContext) {
        let gun = DurumServisi.gunAnahtari()
        let d = UserDefaults.standard
        guard d.string(forKey: gunlukAnahtar) != gun, let kok = klasor.kok?.deletingLastPathComponent() else { return }
        let yedekKlasoru = kok.appending(path: "Yedek", directoryHint: .isDirectory)
        let fm = FileManager.default
        try? fm.createDirectory(at: yedekKlasoru, withIntermediateDirectories: true)
        guard let veri = try? veri(context) else { return }
        let hedef = yedekKlasoru.appending(path: "levha-yedek-\(gun).levhayedek")
        var hata: NSError?
        var yazildi = false
        NSFileCoordinator().coordinate(writingItemAt: hedef, options: .forReplacing, error: &hata) { u in
            yazildi = (try? veri.write(to: u, options: .atomic)) != nil
        }
        guard yazildi else { return }
        d.set(gun, forKey: gunlukAnahtar)
        let eskiler = ((try? fm.contentsOfDirectory(at: yedekKlasoru, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("levha-yedek-") && $0.pathExtension == "levhayedek" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(tutulacakGun)
        for url in eskiler {
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &hata) { try? fm.removeItem(at: $0) }
        }
    }

    static func yedekKlasoruAdi(_ klasor: PaketKlasoru) -> String {
        klasor.iCloud ? "iCloud Drive › Levha › Yedek" : "Bu iPhone'da › Levha › Yedek"
    }
}

extension Soru {
    /// Şema karşılığı (Yazdıklarım yedeği için).
    var json: SoruJSON {
        let celdirici = celdirici_dugum.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let aile = secenek_aile.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        return SoruJSON(id: id, levha: levha, dugumler: dugumler, kok: kok, secenekler: secenekler, dogru: dogru,
                        aciklama: aciklama, aciklama_yolu: aciklama_yolu, celdirici_dugum: celdirici, kazanim: kazanim,
                        kalip: kalip, zorluk: zorluk, secenek_aile: aile,
                        ipucu_sirasi: ipuclari.isEmpty ? nil : ipuclari, kirilimlar: kirilimListesi.isEmpty ? nil : kirilimListesi)
    }
}
