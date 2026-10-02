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
}

/// Günlük turun planı ve ilerlemesi. Gün 04:00'te döner (`Zamanlayici.gunAnahtari`).
@MainActor
enum TurPlanlayici {
    static func bugun(_ context: ModelContext) -> TurDurumu {
        let gun = DurumServisi.gunAnahtari()
        if let t = try? context.fetch(FetchDescriptor<TurDurumu>(predicate: #Predicate { $0.gun == gun })).first {
            // Part 2'de oluşan kayıtta Kapanış kuyruğu yoktur; eksikse tamamlanır.
            var k = kuyruk(t)
            if k.kapanis == nil && !t.tamamlananlar.contains(TurBlogu.kapanis.rawValue) {
                k.kapanis = kapanisSec(k, siraliLevhalar(context), context)
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

    static func aktifBloklar(_ t: TurDurumu) -> [TurBlogu] {
        if t.kisa { return [.isinma, .soru] }
        if t.calismaYeri == CalismaYeri.sadeceTekrar.rawValue { return [.isinma, .soru, .pekistirme, .kapanis] }
        return TurBlogu.allCases
    }

    /// Tamamlanabilir blokların toplam dakikası.
    static func planlananDakika(_ t: TurDurumu) -> Int {
        aktifBloklar(t).filter(\.hazir).reduce(0) { $0 + $1.dakika }
    }

    static func tamamlananDakika(_ t: TurDurumu) -> Int {
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
            let vadeliler = levhalar.filter { DurumServisi.vadeliMi(durumlar[$0.id]) }
            let vadeli: [String] = vadeliler.indices.sorted { i, j in
                let (a, b) = (durumlar[vadeliler[i].id], durumlar[vadeliler[j].id])
                let (aEski, bEski) = (a?.sonGorulme != nil, b?.sonGorulme != nil)
                if aEski != bEski { return aEski }
                let (as_, bs) = (a?.saglamlik ?? 0, b?.saglamlik ?? 0)
                if as_ != bs { return as_ > bs }
                return i < j
            }.map { vadeliler[$0].id }
            let digerleri: [String] = levhalar.map(\.id).filter { !vadeli.contains($0) }
            k.isinma = Array((vadeli + digerleri).prefix(3))
        }

        // Isınma dışındaki kuyruklar öncelik puanına göre sıralanır.
        if !bitti(.yeni) {
            switch CalismaYeri(rawValue: t.calismaYeri) ?? .kitapli {
            case .kitapli:
                k.yeni = DurumServisi.oncelikSirala(levhalar.filter { $0.paket?.paket_id == t.altKonuPaketId }, context).map(\.id)
            case .kitapsiz:
                let adaylar = levhalar.filter { !ortulmus.contains($0.id) && DurumServisi.vadeliMi(durumlar[$0.id]) }
                k.yeni = Array(DurumServisi.oncelikSirala(adaylar, context).map(\.id).prefix(6))
            case .sadeceTekrar:
                k.yeni = []
            }
        }

        if !bitti(.soru) {
            let sorular = (try? context.fetch(FetchDescriptor<Soru>(sortBy: [SortDescriptor(\.sira)]))) ?? []
            k.soru = SoruSecici.tur(bugunLevhalari: Set(k.isinma + k.yeni), havuz: sorular, sayi: 15,
                                    tohum: "tur|\(t.gun)|\(t.calismaYeri)", context)
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
            for o in yanlislar where !levhalar.contains(o.levhaId) { levhalar.append(o.levhaId) }
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
    }

    /// Kapanış (İnşa): bugün çalışılan levhalardan önceliği en yüksek iki tanesi; yoksa tüm levhalardan.
    static func kapanisSec(_ k: TurKuyrugu, _ tumu: [Levha], _ context: ModelContext) -> [String] {
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
            if DurumServisi.vadeliMi(durumlar[s.levha]) { return 1 }
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

    private static func gecmis(_ context: ModelContext) -> (yanlis7: Set<String>, cozulen: Set<String>) {
        let olaylar = (try? context.fetch(FetchDescriptor<SoruOlayi>())) ?? []
        let sinir = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return (Set(olaylar.filter { !$0.dogruMu && $0.tarih >= sinir }.map(\.soruGlobalId)),
                Set(olaylar.map(\.soruGlobalId)))
    }
}
