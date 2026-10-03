import Foundation
import SwiftData

enum TurBlogu: String, CaseIterable, Identifiable {
    case isinma, yeni, soru, pekistirme, kapanis
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .isinma: return "Isınma"
        case .yeni: return "Yeni"
        case .soru: return "Soru"
        case .pekistirme: return "Pekiştirme"
        case .kapanis: return "Kapanış"
        }
    }

    var dakika: Int {
        switch self {
        case .isinma, .kapanis: return 5
        case .yeni, .soru: return 20
        case .pekistirme: return 10
        }
    }

    var modAdi: String {
        switch self {
        case .isinma: return "Sabotaj"
        case .yeni: return "Keşif + Örtme"
        case .soru: return "Soru"
        case .pekistirme: return "Örtme"
        case .kapanis: return "İnşa"
        }
    }

    var simge: String {
        switch self {
        case .isinma: return "flame"
        case .yeni: return "sparkles"
        case .soru: return "questionmark.circle"
        case .pekistirme: return "arrow.triangle.2.circlepath"
        case .kapanis: return "hammer"
        }
    }

    var hazir: Bool { true }

    var izinliModlar: [LevhaModu] {
        switch self {
        case .isinma: return [.sabotaj]
        case .yeni: return [.kesif, .ortme]
        case .pekistirme: return [.ortme]
        case .kapanis: return [.insa]
        case .soru: return []
        }
    }
}

struct TurKuyrugu: Codable, Equatable {
    var isinma: [String] = []
    var yeni: [String] = []
    var soru: [String] = []
    /// Soru bloğu bitince hesaplanır; nil = henüz hesaplanmadı.
    var pekistirme: [String]?
    /// İnşa (Kapanış). Part 2 kayıtlarında yok.
    var kapanis: [String]?
    /// Soru bloğunda İpucu avı formatında gelecek sorular (`soru`nun alt kümesi). Part 3 kayıtlarında yok.
    var ipucuAvi: [String]?
    /// Kitap sayfası eşlemesinden seçilen levhalar; Yeni bloğuna girer (Kitaplı modda alt konunun yerine).
    var kitap: [String]?
    /// Bugün "Önce oku" ile anlatımı açılmış paketler.
    var okunan: [String]?
}

/// Günlük turun planı ve ilerlemesi. Gün 04:00'te döner (`Zamanlayici.gunAnahtari`).
@MainActor
enum TurPlanlayici {
    static func bugun(_ context: ModelContext) -> TurDurumu {
        let gun = DurumServisi.gunAnahtari()
        if let t = try? context.fetch(FetchDescriptor<TurDurumu>(predicate: #Predicate { $0.gun == gun })).first {
            // Önceki sürümlerde oluşan kayıtta Kapanış / İpucu avı kuyruğu yoktur; eksikse tamamlanır.
            var k = kuyruk(t)
            var degisti = false
            if k.kapanis == nil && !t.tamamlananlar.contains(TurBlogu.kapanis.rawValue) {
                k.kapanis = kapanisSec(k, siraliLevhalar(context), context)
                degisti = true
            }
            if k.ipucuAvi == nil && !t.tamamlananlar.contains(TurBlogu.soru.rawValue) {
                let sorular = (try? context.fetch(FetchDescriptor<Soru>(sortBy: [SortDescriptor(\.sira)]))) ?? []
                (k.soru, k.ipucuAvi) = SoruSecici.ipucuAviKarisimi(k.soru, havuz: sorular, sayi: 5, tohum: "ipucu|\(t.gun)")
                degisti = true
            }
            if degisti {
                t.kuyruk = try? JSONEncoder().encode(k)
                try? context.save()
            }
            return t
        }
        let varsayilan = UserDefaults.standard.string(forKey: "calismaYeri") ?? CalismaYeri.kitapli.rawValue
        let t = TurDurumu(gun: gun, calismaYeri: varsayilan)
        t.altKonuPaketId = UserDefaults.standard.string(forKey: "aktifPaketId").flatMap { $0.isEmpty ? nil : $0 }
        context.insert(t)
        planla(t, context)
        return t
    }

    static func kuyruk(_ t: TurDurumu) -> TurKuyrugu {
        t.kuyruk.flatMap { try? JSONDecoder().decode(TurKuyrugu.self, from: $0) } ?? TurKuyrugu()
    }

    nonisolated static func aktifBloklar(_ t: TurDurumu) -> [TurBlogu] {
        if t.kisa { return [.isinma, .soru] }
        if t.calismaYeri == CalismaYeri.sadeceTekrar.rawValue { return [.isinma, .soru, .pekistirme, .kapanis] }
        return TurBlogu.allCases
    }

    /// Tamamlanabilir blokların toplam dakikası.
    nonisolated static func planlananDakika(_ t: TurDurumu) -> Int {
        aktifBloklar(t).filter(\.hazir).reduce(0) { $0 + $1.dakika }
    }

    nonisolated static func tamamlananDakika(_ t: TurDurumu) -> Int {
        aktifBloklar(t).filter { t.tamamlananlar.contains($0.rawValue) }.reduce(0) { $0 + $1.dakika }
    }

    /// Henüz bitmemiş blokların kuyruklarını yeniden kurar (çalışma yeri / alt konu değişince de çağrılır).
    static func planla(_ t: TurDurumu, _ context: ModelContext) {
        var k = kuyruk(t)
        let levhalar = siraliLevhalar(context)
        let durumlar = DurumServisi.tumDurumlar(context)
        let ortulmus = Set(((try? context.fetch(FetchDescriptor<OrtmeOlayi>())) ?? []).map(\.levhaId))
        let bitti = { (b: TurBlogu) in t.tamamlananlar.contains(b.rawValue) }

        if !bitti(.isinma) {
            // "Eski ve sağlam" olan sabote edilir: geçmişi olan, sağlamlığı yüksek, vadesi gelmiş.
            // A/B: metin grubunda Sabotaj kapalı.
            let gorsel = levhalar.filter { !ABDeneyi.ortak.metinMi($0) }
            let vadeliler = gorsel.filter { DurumServisi.vadeliMi(durumlar[$0.id]) }
            let vadeli: [String] = vadeliler.indices.sorted { i, j in
                let (a, b) = (durumlar[vadeliler[i].id], durumlar[vadeliler[j].id])
                let (aEski, bEski) = (a?.sonGorulme != nil, b?.sonGorulme != nil)
                if aEski != bEski { return aEski }
                let (as_, bs) = (a?.saglamlik ?? 0, b?.saglamlik ?? 0)
                if as_ != bs { return as_ > bs }
                return i < j
            }.map { vadeliler[$0].id }
            let digerleri: [String] = gorsel.map(\.id).filter { !vadeli.contains($0) }
            k.isinma = Array((vadeli + digerleri).prefix(3))
        }

        // Isınma dışındaki kuyruklar öncelik puanına göre sıralanır.
        if !bitti(.yeni) {
            let kitap = (k.kitap ?? []).filter { id in levhalar.contains { $0.id == id } }
            switch CalismaYeri(rawValue: t.calismaYeri) ?? .kitapli {
            case .kitapli:
                // Kitap sayfasından seçilen levhalar alt konu seçiminin yerine geçer.
                k.yeni = !kitap.isEmpty ? kitap
                    : DurumServisi.oncelikSirala(levhalar.filter { $0.paket?.paket_id == t.altKonuPaketId }, context).map(\.id)
            case .kitapsiz:
                let adaylar = levhalar.filter { !ortulmus.contains($0.id) && DurumServisi.vadeliMi(durumlar[$0.id]) && !kitap.contains($0.id) }
                k.yeni = kitap + Array(DurumServisi.oncelikSirala(adaylar, context).map(\.id).prefix(6))
            case .sadeceTekrar:
                k.yeni = kitap
            }
        }

        if !bitti(.soru) {
            let sorular = (try? context.fetch(FetchDescriptor<Soru>(sortBy: [SortDescriptor(\.sira)]))) ?? []
            let secilen = SoruSecici.tur(bugunLevhalari: Set(k.isinma + k.yeni), havuz: sorular, sayi: 15,
                                         tohum: "tur|\(t.gun)|\(t.calismaYeri)", context)
            (k.soru, k.ipucuAvi) = SoruSecici.ipucuAviKarisimi(secilen, havuz: sorular, sayi: 5, tohum: "ipucu|\(t.gun)")
            k.pekistirme = nil
        }

        if !bitti(.kapanis) { k.kapanis = kapanisSec(k, levhalar, context) }
        t.kuyruk = try? JSONEncoder().encode(k)
        try? context.save()
    }

    static func tamamla(_ blok: TurBlogu, _ t: TurDurumu, _ context: ModelContext) {
        if !t.tamamlananlar.contains(blok.rawValue) { t.tamamlananlar.append(blok.rawValue) }
        if blok == .soru {
            // Pekiştirme: bugünkü Soru bloğunda yanlış çıkan düğümlerin levhaları.
            var k = kuyruk(t)
            let bugun = Zamanlayici.calismaGunu(.now, takvim: DurumServisi.takvim)
            let idler = Set(k.soru)
            let yanlislar = ((try? context.fetch(FetchDescriptor<SoruOlayi>(sortBy: [SortDescriptor(\.tarih)]))) ?? [])
                .filter { !$0.dogruMu && $0.tarih >= bugun && idler.contains($0.soruGlobalId) }
            var levhalar: [String] = []
            var sorular: [String: Soru]?
            for o in yanlislar {
                if !o.levhaId.isEmpty {
                    if !levhalar.contains(o.levhaId) { levhalar.append(o.levhaId) }
                    continue
                }
                // Bağımsız soru: kazanımının düğümlerinin levhaları.
                if sorular == nil {
                    let hepsi = (try? context.fetch(FetchDescriptor<Soru>())) ?? []
                    sorular = Dictionary(hepsi.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
                }
                guard let s = sorular?[o.soruGlobalId] else { continue }
                for l in DurumServisi.kazanimLevhalari(s, context) where !levhalar.contains(l) { levhalar.append(l) }
            }
            k.pekistirme = DurumServisi.oncelikSirala(self.levhalar(levhalar, context), context).map(\.id)
            if !t.tamamlananlar.contains(TurBlogu.kapanis.rawValue) {
                k.kapanis = kapanisSec(k, siraliLevhalar(context), context)
            }
            t.kuyruk = try? JSONEncoder().encode(k)
            if levhalar.isEmpty && !t.tamamlananlar.contains(TurBlogu.pekistirme.rawValue) {
                t.tamamlananlar.append(TurBlogu.pekistirme.rawValue)
            }
        }
        try? context.save()
        WidgetYazici.yaz(context)
        OlayDefteri.degisti()
    }

    /// Kitap sayfasından seçilen levhaları bugünkü Yeni bloğuna ekler. Blok bitmişse yeniden açılır;
    /// Sadece tekrar modunda Yeni bloğu olmadığından Kitaplı'ya geçilir.
    static func kitapEkle(_ idler: [String], _ t: TurDurumu, _ context: ModelContext) {
        var k = kuyruk(t)
        var kitap = k.kitap ?? []
        for id in idler where !kitap.contains(id) { kitap.append(id) }
        k.kitap = kitap
        t.kuyruk = try? JSONEncoder().encode(k)
        t.tamamlananlar.removeAll { $0 == TurBlogu.yeni.rawValue }
        if t.calismaYeri == CalismaYeri.sadeceTekrar.rawValue { t.calismaYeri = CalismaYeri.kitapli.rawValue }
        t.kisa = false
        planla(t, context)
    }

    /// "Önce oku" kapanınca: bugünün kuyruğunda okundu işareti.
    static func okundu(_ paketId: String, _ t: TurDurumu, _ context: ModelContext) {
        var k = kuyruk(t)
        guard !(k.okunan ?? []).contains(paketId) else { return }
        k.okunan = (k.okunan ?? []) + [paketId]
        t.kuyruk = try? JSONEncoder().encode(k)
        try? context.save()
        OlayDefteri.degisti()
    }

    static func kitapTemizle(_ t: TurDurumu, _ context: ModelContext) {
        var k = kuyruk(t)
        k.kitap = nil
        t.kuyruk = try? JSONEncoder().encode(k)
        planla(t, context)
    }

    /// Editör'de kaydedilen soru, Soru bloğu bitmemişse bugünkü tura eklenir.
    static func soruEkle(_ soruId: String, _ context: ModelContext) {
        let t = bugun(context)
        guard !t.tamamlananlar.contains(TurBlogu.soru.rawValue) else { return }
        var k = kuyruk(t)
        guard !k.soru.contains(soruId) else { return }
        k.soru.append(soruId)
        t.kuyruk = try? JSONEncoder().encode(k)
        try? context.save()
    }

    /// Kapanış (İnşa): bugün çalışılan levhalardan önceliği en yüksek iki tanesi; yoksa tüm levhalardan.
    static func kapanisSec(_ k: TurKuyrugu, _ hepsi: [Levha], _ context: ModelContext) -> [String] {
        // A/B: metin grubunda İnşa kapalı.
        let tumu = hepsi.filter { !ABDeneyi.ortak.metinMi($0) }
        let bugunku = Set((k.pekistirme ?? []) + k.yeni + k.isinma)
        let adaylar = tumu.filter { bugunku.contains($0.id) }
        return Array(DurumServisi.oncelikSirala(adaylar.isEmpty ? tumu : adaylar, context).map(\.id).prefix(2))
    }

    static func siraliLevhalar(_ context: ModelContext) -> [Levha] {
        let paketler = (try? context.fetch(FetchDescriptor<Paket>(sortBy: [SortDescriptor(\.ders), SortDescriptor(\.bolum), SortDescriptor(\.alt_konu)]))) ?? []
        return paketler.flatMap(\.siraliLevhalar)
    }

    static func levhalar(_ idler: [String], _ context: ModelContext) -> [Levha] {
        let hepsi = Dictionary(siraliLevhalar(context).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return idler.compactMap { hepsi[$0] }
    }
}

@MainActor
enum SoruSecici {
    /// Sorulabilirlik ağırlıklı tohumlu karıştırma (Efraimidis–Spirakis): ağırlığı yüksek soru öne çıkma eğiliminde,
    /// ama düşük ağırlıklı da arada gelir. Ağırlık = kazanım sorulabilirliği / 5 (kazanımsız 0,6).
    static func agirlikliKaristir(_ havuz: [Soru], rng: inout TohumluUretec) -> [Soru] {
        let anahtarlar = havuz.map { s -> Double in
            let w = s.sorulabilirlik.map { Double($0) / 5 } ?? Oncelik.varsayilanSorulabilirlik
            return pow(max(rng.oran(), 1e-12), 1 / w)
        }
        return havuz.indices.sorted { anahtarlar[$0] > anahtarlar[$1] }.map { havuz[$0] }
    }

    /// Konu oturumu: önce son 7 günün yanlışları, sonra vadesi gelmiş levhaların soruları,
    /// sonra hiç çözülmemişler, en son kalanlar. Grup içi sıra sorulabilirlik ağırlıklı tohumlu karışık.
    static func konu(_ havuz: [Soru], sayi: Int, tohum: String, _ context: ModelContext) -> [String] {
        let (yanlis7, cozulen) = gecmis(context)
        let durumlar = DurumServisi.tumDurumlar(context)
        var rng = TohumluUretec(tohum: tohum)
        let karisik = agirlikliKaristir(havuz, rng: &rng)
        func grup(_ s: Soru) -> Int {
            if yanlis7.contains(s.kimlik) { return 0 }
            if !s.bagimsiz && DurumServisi.vadeliMi(durumlar[s.levha]) { return 1 }
            if !cozulen.contains(s.kimlik) { return 2 }
            return 3
        }
        return karisik.enumerated()
            .sorted { (grup($0.element), $0.offset) < (grup($1.element), $1.offset) }
            .prefix(sayi)
            .map(\.element.kimlik)
    }

    /// Tur: %50 bugünkü levhalardan, %30 son 7 günün yanlışlarından, %20 rastgele; eksik kalan diğerlerinden dolar.
    static func tur(bugunLevhalari: Set<String>, havuz: [Soru], sayi: Int, tohum: String, _ context: ModelContext) -> [String] {
        let (yanlis7, _) = gecmis(context)
        var rng = TohumluUretec(tohum: tohum)
        let karisik = agirlikliKaristir(havuz, rng: &rng)
        let a = karisik.filter { bugunLevhalari.contains($0.levha) }.map(\.kimlik)
        let b = karisik.filter { yanlis7.contains($0.kimlik) }.map(\.kimlik)
        let c = karisik.map(\.kimlik)
        var secilen: [String] = []
        func al(_ kaynak: [String], _ n: Int) {
            var alinan = 0
            for id in kaynak where secilen.count < sayi && alinan < n && !secilen.contains(id) {
                secilen.append(id)
                alinan += 1
            }
        }
        let na = Int((Double(sayi) * 0.5).rounded())
        let nb = Int((Double(sayi) * 0.3).rounded())
        al(a, na)
        al(b, nb)
        al(c, sayi)
        return secilen
    }

    /// Tur listesinden en fazla `sayi` soru İpucu avı formatına alınır (yalnız ipucu sırası olanlar).
    /// Listede yeterince yoksa sondaki ipucusuz sorular havuzdan ipuçlu sorularla değiştirilir.
    static func ipucuAviKarisimi(_ liste: [String], havuz: [Soru], sayi: Int, tohum: String) -> (soru: [String], ipucuAvi: [String]) {
        let ipuclu = havuz.filter { !$0.ipuclari.isEmpty }
        let ipucluIdler = Set(ipuclu.map(\.kimlik))
        var sonuc = liste
        var avi = Array(sonuc.filter { ipucluIdler.contains($0) }.prefix(sayi))
        if avi.count < sayi {
            var rng = TohumluUretec(tohum: tohum)
            let adaylar = agirlikliKaristir(ipuclu, rng: &rng).map(\.kimlik).filter { !sonuc.contains($0) }
            var degistirilebilir = sonuc.indices.filter { !ipucluIdler.contains(sonuc[$0]) }
            for id in adaylar where avi.count < sayi {
                guard let i = degistirilebilir.popLast() else { break }
                sonuc[i] = id
                avi.append(id)
            }
        }
        // İpucu avı soruları bloğa yayılır (15 soruda 5 → 2., 5., 8., 11., 14. sıra).
        guard !avi.isEmpty else { return (sonuc, avi) }
        let aviKume = Set(avi)
        var digerleri = sonuc.filter { !aviKume.contains($0) }[...]
        var aviSirali = sonuc.filter { aviKume.contains($0) }[...]
        let adim = max(1, sonuc.count / aviSirali.count)
        var yayilmis: [String] = []
        for i in sonuc.indices {
            let aviYeri = i % adim == adim / 2 && !aviSirali.isEmpty
            if aviYeri || digerleri.isEmpty, let id = aviSirali.popFirst() {
                yayilmis.append(id)
            } else if let id = digerleri.popFirst() {
                yayilmis.append(id)
            }
        }
        return (yayilmis, avi)
    }

    private static func gecmis(_ context: ModelContext) -> (yanlis7: Set<String>, cozulen: Set<String>) {
        let olaylar = (try? context.fetch(FetchDescriptor<SoruOlayi>())) ?? []
        let sinir = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return (Set(olaylar.filter { !$0.dogruMu && $0.tarih >= sinir }.map(\.soruGlobalId)),
                Set(olaylar.map(\.soruGlobalId)))
    }
}
