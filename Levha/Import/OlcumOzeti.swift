import Foundation
import SwiftData
import Observation
import os

/// Olay tablolarına yazılan her şeyin sürüm sayacı. Ölçüm özeti yalnız bu sayaç değişince yeniden hesaplanır.
@Observable
@MainActor
final class OlayDefteri {
    static let ortak = OlayDefteri()
    private(set) var surum = 0

    static func degisti() { ortak.surum += 1 }
}

struct Sayac: Equatable {
    var d = 0
    var n = 0
    mutating func ekle(_ dogru: Bool) {
        n += 1
        if dogru { d += 1 }
    }
}

struct KaristirmaSatiri: Hashable {
    var dogru: String
    var secilen: String
    var sayi: Int
    var ipucu: String?
}

struct ABOzeti {
    var baslangic: Date
    var levhaPaket: Int
    var metinPaket: Int
    /// Soru doğruluğu, levhanın ilk Örtme/cloze oturumundan en az 7 gün sonra verilen cevaplarda.
    var soru: (levha: Sayac, metin: Sayac)
    /// Örtme/cloze bildim oranı, aynı levhanın önceki oturumundan en az 7 gün sonra.
    var ortme: (levha: Sayac, metin: Sayac)
}

struct SinavKarsilastirmasi {
    var tarih: Date
    var soruSayisi: Int
    var net: Double
    var tahminAlt: Double?
    var tahminUst: Double?
}

/// Ölçüm sekmesinin tüm sayıları; olaylar tek geçişte toplanır.
struct OlcumOzeti {
    // İçerik
    var paketSayisi = 0
    var levhaSayisi = 0
    var soruSayisi = 0
    var kazanimSayisi = 0
    var sorusuzKazanim = 0
    var yazdiklarim = 0
    var dersBolumler: [(ad: String, levha: Int)] = []
    var dersler: [String] = []
    // Öğrenme
    var calisilan = 0
    var histogram = Array(repeating: 0, count: 5)
    var kutular = Array(repeating: 0, count: 5)
    var g7 = Sayac()
    var g30 = Sayac()
    var ab: ABOzeti?
    // Soru
    var kalip: [KalipTipi: Sayac] = [:]
    var kirma = (bilgi: 0, okuma: 0, ringa: 0, kirilan: 0)
    var kirmaKalip: [KalipTipi: (bilgi: Int, okuma: Int, ringa: Int)] = [:]
    var ipucuGecikme: [Double] = []
    var ipucuPuan: [Int] = []
    var ipucuKalip: [KalipTipi: [Double]] = [:]
    var karistirma: [KaristirmaSatiri] = []
    var netler: [(ders: String, N: Int, tahmin: NetTahmini)] = []
    var guven: [Int: Sayac] = [:]
    var kalipTahmin: [KalipTipi: Sayac] = [:]
    var guvensiz = 0
    var sonSinav: SinavKarsilastirmasi?
    // Kullanım
    var gunler: [(gun: Date, dk: Int)] = []
    var turTamamlanan = 0
    var turPlanlanan = 0
    var yerler: [(ad: String, n: Int)] = []
    var llm = (cagri: 0, giris: 0, cikis: 0)
    // Ölçüm
    var olaySayisi = 0
    var sureMs = 0.0
}

/// Son hesaplanan özet ve hangi olay sürümüne ait olduğu. Açılışta ve her olay yazımından 1 sn sonra
/// arka planda yeniden hesaplanır; Ölçüm sekmesi açılınca hazır özet anında gösterilir.
@Observable
@MainActor
final class OlcumOnbellegi {
    static let ortak = OlcumOnbellegi()
    private(set) var ozet: OlcumOzeti?
    private(set) var surum = -1
    private(set) var hesaplaniyor = false
    private var gorev: Task<Void, Never>?

    var guncel: Bool { surum == OlayDefteri.ortak.surum && ozet != nil }

    /// Sürüm değiştiyse (debounce ile) yeniden hesaplar.
    func isit(_ container: ModelContainer, gecikme: Duration = .seconds(1)) {
        let hedef = OlayDefteri.ortak.surum
        guard hedef != surum || ozet == nil else { return }
        gorev?.cancel()
        gorev = Task {
            try? await Task.sleep(for: gecikme)
            guard !Task.isCancelled else { return }
            hesaplaniyor = true
            let o = await Task.detached(priority: .utility) { OlcumHesaplayici.hesapla(container) }.value
            hesaplaniyor = false
            guard !Task.isCancelled else { return }
            ozet = o
            surum = hedef
            // Hesap sürerken yeni olay geldiyse bir tur daha.
            if OlayDefteri.ortak.surum != hedef { isit(container) }
        }
    }
}

enum OlcumHesaplayici {
    static let gunluk = Logger(subsystem: "tr.kisisel.levha", category: "olcum")
    static let isaret = OSSignposter(subsystem: "tr.kisisel.levha", category: "olcum")

    /// Arka planda kendi bağlamıyla hesaplar.
    static func hesapla(_ container: ModelContainer, simdi: Date = .now) -> OlcumOzeti {
        let aralik = isaret.beginInterval("OlcumOzeti")
        let bas = Date.now
        let context = ModelContext(container)
        var o = hesapla(context, simdi: simdi)
        o.sureMs = Date.now.timeIntervalSince(bas) * 1000
        isaret.endInterval("OlcumOzeti", aralik)
        gunluk.notice("Ölçüm özeti: \(o.olaySayisi) olay, \(String(format: "%.0f", o.sureMs)) ms")
        return o
    }

    static func hesapla(_ context: ModelContext, simdi: Date) -> OlcumOzeti {
        var o = OlcumOzeti()
        let takvim = Calendar.current
        func al<T: PersistentModel>(_ d: FetchDescriptor<T>) -> [T] { (try? context.fetch(d)) ?? [] }

        // İçerik
        let paketler = al(FetchDescriptor<Paket>(sortBy: [SortDescriptor(\.ders), SortDescriptor(\.bolum), SortDescriptor(\.alt_konu)]))
        let icerik = paketler.filter { !$0.kullaniciMi }
        let sorular = al(FetchDescriptor<Soru>())
        let kazanimlar = al(FetchDescriptor<Kazanim>())
        let soruSozlugu = Dictionary(sorular.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        o.paketSayisi = icerik.count
        o.soruSayisi = sorular.count
        o.kazanimSayisi = kazanimlar.count
        o.yazdiklarim = sorular.filter(\.kullaniciSorusu).count
        var sira: [String] = []
        var sayi: [String: Int] = [:]
        for p in paketler {
            let levhalar = p.levhalar
            o.levhaSayisi += levhalar.count
            guard !p.kullaniciMi else { continue }
            let ad = "\(p.ders) › \(p.bolum)"
            if sayi[ad] == nil { sira.append(ad) }
            sayi[ad, default: 0] += levhalar.count
            if !o.dersler.contains(p.ders) { o.dersler.append(p.ders) }
        }
        o.dersBolumler = sira.map { ($0, sayi[$0] ?? 0) }
        let soruluKazanim = Set(sorular.compactMap { s in s.kazanim.map { "\(s.paket?.paket_id ?? "").\($0)" } })
        o.sorusuzKazanim = kazanimlar.filter { !soruluKazanim.contains("\($0.paket?.paket_id ?? "").\($0.id)") }.count

        // Öğrenme
        let durumlar = al(FetchDescriptor<LevhaDurumu>())
        for d in durumlar {
            if d.sonGorulme != nil || d.sonrakiTarih != nil {
                o.calisilan += 1
                o.histogram[min(4, max(0, Int(d.saglamlik / 20)))] += 1
            }
            if d.sonrakiTarih != nil, (0...4).contains(d.kutu) { o.kutular[d.kutu] += 1 }
        }
        // Yalnız gereken alanlar okunur: nesne oluşturma maliyeti olay sayısıyla doğrusal.
        var ortmeIstegi = FetchDescriptor<OrtmeOlayi>(sortBy: [SortDescriptor(\.tarih)])
        ortmeIstegi.propertiesToFetch = [\.levhaId, \.tarih, \.bildim, \.abGrup]
        let ortmeler = al(ortmeIstegi)
        o.olaySayisi += ortmeler.count
        // Oturum = aynı anda yazılan kayıtlar.
        var oturumlar: [String: [(tarih: Date, bildim: Int, toplam: Int, ab: String?)]] = [:]
        for x in ortmeler {
            var dizi = oturumlar[x.levhaId] ?? []
            if let son = dizi.last, son.tarih == x.tarih {
                dizi[dizi.count - 1] = (son.tarih, son.bildim + (x.bildim ? 1 : 0), son.toplam + 1, son.ab ?? x.abGrup)
            } else {
                dizi.append((x.tarih, x.bildim ? 1 : 0, 1, x.abGrup))
            }
            oturumlar[x.levhaId] = dizi
        }
        var abOrtme = (levha: Sayac(), metin: Sayac())
        var ilkAbOturum: [String: Date] = [:]
        for (levhaId, dizi) in oturumlar {
            if let ilk = dizi.first(where: { $0.ab != nil }) { ilkAbOturum[levhaId] = ilk.tarih }
            guard dizi.count > 1 else { continue }
            for i in 1..<dizi.count {
                let gun = dizi[i].tarih.timeIntervalSince(dizi[i - 1].tarih) / 86_400
                if gun >= 7 { o.g7.d += dizi[i].bildim; o.g7.n += dizi[i].toplam }
                if gun >= 30 { o.g30.d += dizi[i].bildim; o.g30.n += dizi[i].toplam }
                if gun >= 7, let g = dizi[i].ab {
                    if g == ABDeneyi.metin { abOrtme.metin.d += dizi[i].bildim; abOrtme.metin.n += dizi[i].toplam }
                    else { abOrtme.levha.d += dizi[i].bildim; abOrtme.levha.n += dizi[i].toplam }
                }
            }
        }

        // Soru
        var soruIstegi = FetchDescriptor<SoruOlayi>(sortBy: [SortDescriptor(\.tarih)])
        soruIstegi.propertiesToFetch = [\.soruGlobalId, \.levhaId, \.secilen, \.dogruMu, \.tarih, \.guven,
                                        \.kalipTahmini, \.ipucuTahminiIndeks, \.kirmaSuresi, \.abGrup]
        let soruOlaylari = al(soruIstegi)
        o.olaySayisi += soruOlaylari.count
        let netSiniri = takvim.date(byAdding: .day, value: -14, to: simdi) ?? simdi
        var netDersler: [String: [(sorulabilirlik: Int, dogru: Bool)]] = [:]
        var karistirma: [String: KaristirmaSatiri] = [:]
        var abSoru = (levha: Sayac(), metin: Sayac())
        for e in soruOlaylari {
            let s = soruSozlugu[e.soruGlobalId]
            let k = s?.kalipTipi
            if let k { o.kalip[k, default: Sayac()].ekle(e.dogruMu) }
            if let g = e.guven {
                o.guven[g, default: Sayac()].ekle(e.dogruMu)
                if g == 3, let k { o.kalipTahmin[k, default: Sayac()].ekle(e.dogruMu) }
            } else {
                o.guvensiz += 1
            }
            if e.tarih >= netSiniri, let s, let ders = s.ders {
                netDersler[ders, default: []].append((s.sorulabilirlik ?? 3, e.dogruMu))
            }
            if e.kirmaSuresi != nil, let s {
                o.kirma.kirilan += 1
                var dag = k.flatMap { o.kirmaKalip[$0] } ?? (0, 0, 0)
                switch KirmaSinifi.sinifla(kalipTahmini: e.kalipTahmini, gercekKalip: k?.rawValue, cevapDogru: e.dogruMu) {
                case .bilgiEksigi: o.kirma.bilgi += 1; dag.bilgi += 1
                case .okumaEksigi: o.kirma.okuma += 1; dag.okuma += 1
                case nil: break
                }
                let ip = s.ipuclari
                if let i = e.ipucuTahminiIndeks, ip.indices.contains(i), ip[i].yanilticiMi { o.kirma.ringa += 1; dag.ringa += 1 }
                if let k { o.kirmaKalip[k] = dag }
            }
            if !e.dogruMu, let s {
                let aile = s.secenekAileleri
                if let x = aile[e.secilen], let y = aile[s.dogru], x != y {
                    let anahtar = "\(y)|\(x)"
                    var satir = karistirma[anahtar] ?? KaristirmaSatiri(dogru: y, secilen: x, sayi: 0, ipucu: nil)
                    satir.sayi += 1
                    if satir.ipucu == nil { satir.ipucu = s.konuPaketi?.aileler.lazy.compactMap { $0.ayiriciIpucu(x, y) }.first }
                    karistirma[anahtar] = satir
                }
            }
            if let g = e.abGrup, let ilk = ilkAbOturum[e.levhaId], e.tarih.timeIntervalSince(ilk) >= 7 * 86_400 {
                if g == ABDeneyi.metin { abSoru.metin.ekle(e.dogruMu) } else { abSoru.levha.ekle(e.dogruMu) }
            }
        }
        o.karistirma = Array(karistirma.values.sorted { ($0.sayi, $1.secilen) > ($1.sayi, $0.secilen) }.prefix(10))
        let ceza = SinavAyarlari.ceza
        o.netler = netDersler.keys.sorted().map { ders in
            let N = SinavAyarlari.soruSayisi(ders)
            return (ders, N, NetHesabi.tahmin(cevaplar: netDersler[ders] ?? [], N: N, ceza: ceza))
        }

        let ipucuOlaylari = al(FetchDescriptor<IpucuOlayi>(sortBy: [SortDescriptor(\.tarih)]))
        o.olaySayisi += ipucuOlaylari.count
        for e in ipucuOlaylari where e.tarih >= netSiniri {
            o.ipucuGecikme.append(e.gecikme)
            o.ipucuPuan.append(e.puan)
            if let k = soruSozlugu[e.soruGlobalId]?.kalipTipi { o.ipucuKalip[k, default: []].append(e.gecikme) }
        }

        var sonSinav = FetchDescriptor<SinavOlayi>(sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        sonSinav.fetchLimit = 1
        if let s = al(sonSinav).first {
            o.sonSinav = SinavKarsilastirmasi(tarih: s.tarih, soruSayisi: s.soruSayisi, net: s.net, tahminAlt: s.tahminAlt, tahminUst: s.tahminUst)
        }
        o.olaySayisi += (try? context.fetchCount(FetchDescriptor<SinavOlayi>())) ?? 0
        o.olaySayisi += (try? context.fetchCount(FetchDescriptor<SabotajOlayi>())) ?? 0
        o.olaySayisi += (try? context.fetchCount(FetchDescriptor<InsaOlayi>())) ?? 0

        // A/B
        let gruplar = al(FetchDescriptor<ABGrup>())
        if let baslangic = gruplar.map(\.atamaTarihi).min() {
            o.ab = ABOzeti(baslangic: baslangic,
                           levhaPaket: gruplar.filter { $0.grup != ABDeneyi.metin }.count,
                           metinPaket: gruplar.filter { $0.grup == ABDeneyi.metin }.count,
                           soru: abSoru, ortme: abOrtme)
        }

        // Kullanım
        let bugun = Zamanlayici.calismaGunu(simdi, takvim: takvim)
        let kullanim = Dictionary(al(FetchDescriptor<KullanimKaydi>()).map { ($0.gun, $0.saniye) }, uniquingKeysWith: +)
        // Çalışma gününün öğlesi: 04:00 kaydırması anahtarı bir önceki güne düşürmesin.
        func anahtar(_ g: Date) -> String { Zamanlayici.gunAnahtari(g.addingTimeInterval(12 * 3600), takvim: takvim) }
        o.gunler = (0..<14).reversed().compactMap { geri in
            guard let g = takvim.date(byAdding: .day, value: -geri, to: bugun) else { return nil }
            return (g, Int(((kullanim[anahtar(g)] ?? 0) / 60).rounded()))
        }
        let anahtarlar = Set(o.gunler.map { anahtar($0.gun) })
        let turlar = al(FetchDescriptor<TurDurumu>()).filter { anahtarlar.contains($0.gun) }
        o.turTamamlanan = turlar.reduce(0) { $0 + TurPlanlayici.tamamlananDakika($1) }
        o.turPlanlanan = turlar.reduce(0) { $0 + TurPlanlayici.planlananDakika($1) }
        o.yerler = CalismaYeri.allCases.map { y in (y.ad, turlar.filter { $0.calismaYeri == y.rawValue }.count) }
        let ayBasi = takvim.date(from: takvim.dateComponents([.year, .month], from: simdi)) ?? simdi
        for k in al(FetchDescriptor<LLMKullanim>(predicate: #Predicate { $0.tarih >= ayBasi })) {
            o.llm.cagri += 1
            o.llm.giris += k.giris
            o.llm.cikis += k.cikis
        }
        return o
    }
}
