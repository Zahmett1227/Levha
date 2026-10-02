import Foundation
import SwiftData

/// Olay kayıtları ve bunların zamanlayıcıya yansıması. Saf hesap `Zamanlayici`'da; burası yalnız okur/yazar.
@MainActor
enum DurumServisi {
    static var takvim: Calendar { Calendar.current }

    static func durum(_ levhaId: String, _ context: ModelContext) -> LevhaDurumu {
        let id = levhaId
        if let d = try? context.fetch(FetchDescriptor<LevhaDurumu>(predicate: #Predicate { $0.levhaId == id })).first {
            return d
        }
        let d = LevhaDurumu(levhaId: levhaId)
        context.insert(d)
        return d
    }

    static func tumDurumlar(_ context: ModelContext) -> [String: LevhaDurumu] {
        let hepsi = (try? context.fetch(FetchDescriptor<LevhaDurumu>())) ?? []
        return Dictionary(hepsi.map { ($0.levhaId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Kayıtlar

    static func ortmeKaydet(levha: Levha, hedefler: [String], bilemedikler: Set<String>, _ context: ModelContext) {
        let simdi = Date.now
        for id in hedefler {
            context.insert(OrtmeOlayi(levhaId: levha.id, dugumId: id, tarih: simdi, bildim: !bilemedikler.contains(id)))
        }
        levha.sonCalisma = simdi
        let d = durum(levha.id, context)
        d.deger = Zamanlayici.ortmeSonucu(d.deger, bildim: hedefler.count - bilemedikler.count, toplam: hedefler.count,
                                          simdi: simdi, takvim: takvim)
        saglamlikGuncelle(levha.id, context)
        try? context.save()
    }

    static func sabotajKaydet(levha: Levha, tip: SabotajTipi, bulundu: Bool, deneme: Int, _ context: ModelContext) {
        let simdi = Date.now
        context.insert(SabotajOlayi(levhaId: levha.id, sabotajTipi: tip.rawValue, bulundu: bulundu, denemeSayisi: deneme, tarih: simdi))
        levha.sonCalisma = simdi
        durum(levha.id, context).sonGorulme = simdi
        saglamlikGuncelle(levha.id, context)
        try? context.save()
    }

    /// Yanlış cevapta sorunun düğümleri ve seçilen şıkkın çeldirici düğümü zayıflık sayacına +1 yazılır.
    static func soruKaydet(soru: Soru, secilen: Int, sure: TimeInterval, _ context: ModelContext) {
        let dogru = secilen == soru.dogru
        context.insert(SoruOlayi(soruGlobalId: soru.kimlik, levhaId: soru.levha, secilen: secilen, dogruMu: dogru,
                                 sureSaniye: sure, tarih: .now))
        if !dogru {
            var dugumler = soru.dugumler
            if let c = soru.celdiriciler[secilen], !dugumler.contains(c) { dugumler.append(c) }
            for id in dugumler { zayiflikArtir(levhaId: soru.levha, dugumId: id, context) }
        }
        saglamlikGuncelle(soru.levha, context)
        try? context.save()
    }

    private static func zayiflikArtir(levhaId: String, dugumId: String, _ context: ModelContext) {
        let (l, d) = (levhaId, dugumId)
        if let z = try? context.fetch(FetchDescriptor<DugumZayiflik>(predicate: #Predicate { $0.levhaId == l && $0.dugumId == d })).first {
            z.sayac += 1
        } else {
            context.insert(DugumZayiflik(levhaId: levhaId, dugumId: dugumId, sayac: 1))
        }
    }

    static func zayifliklar(_ levhaId: String, _ context: ModelContext) -> [String: Int] {
        let l = levhaId
        let hepsi = (try? context.fetch(FetchDescriptor<DugumZayiflik>(predicate: #Predicate { $0.levhaId == l }))) ?? []
        return Dictionary(hepsi.map { ($0.dugumId, $0.sayac) }, uniquingKeysWith: +)
    }

    /// Sağlamlık olay geçmişinden yeniden hesaplanır (formül `Zamanlayici.saglamlik`).
    static func saglamlikGuncelle(_ levhaId: String, _ context: ModelContext) {
        let l = levhaId
        let ortmeler = (try? context.fetch(FetchDescriptor<OrtmeOlayi>(predicate: #Predicate { $0.levhaId == l },
                                                                      sortBy: [SortDescriptor(\.tarih)]))) ?? []
        // Aynı anda yazılan kayıtlar bir oturumdur.
        var oturumlar: [(Date, Int, Int)] = []
        for o in ortmeler {
            if let son = oturumlar.last, son.0 == o.tarih {
                oturumlar[oturumlar.count - 1] = (son.0, son.1 + (o.bildim ? 1 : 0), son.2 + 1)
            } else {
                oturumlar.append((o.tarih, o.bildim ? 1 : 0, 1))
            }
        }
        let sorular = (try? context.fetch(FetchDescriptor<SoruOlayi>(predicate: #Predicate { $0.levhaId == l },
                                                                    sortBy: [SortDescriptor(\.tarih)]))) ?? []
        let sabotajlar = (try? context.fetch(FetchDescriptor<SabotajOlayi>(predicate: #Predicate { $0.levhaId == l },
                                                                          sortBy: [SortDescriptor(\.tarih)]))) ?? []
        durum(levhaId, context).saglamlik = Zamanlayici.saglamlik(
            ortmeOranlari: oturumlar.map { Double($0.1) / Double($0.2) },
            soruSonuclari: sorular.map(\.dogruMu),
            sabotajSonuclari: sabotajlar.map(\.bulundu))
    }

    static func gunAnahtari(_ tarih: Date = .now) -> String { Zamanlayici.gunAnahtari(tarih, takvim: takvim) }

    static func vadeliMi(_ d: LevhaDurumu?, simdi: Date = .now) -> Bool {
        Zamanlayici.vadeliMi(d?.deger, simdi: simdi, takvim: takvim)
    }
}
