#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import QuartzCore
import os

/// Yalnız DEBUG: performans ölçümü için sentetik yük. Başlatma argümanlarıyla tetiklenir:
/// `-yukOlay 20000` (son 90 güne yayılmış olay), `-yukPaket 12` (12 paket × 50 levha × 15 düğüm),
/// `-yukTemizle 1` (sentetik paketleri ve `yuk` işaretli olayları siler).
@MainActor
enum YukTesti {
    static let gunluk = Logger(subsystem: "tr.kisisel.levha", category: "yuk")
    static let onek = "yuk."

    static func calistir(_ context: ModelContext) {
        let d = UserDefaults.standard
        if d.bool(forKey: "yukTemizle") { temizle(context) }
        let paket = d.integer(forKey: "yukPaket")
        if paket > 0 { paketUret(paket, context) }
        let olay = d.integer(forKey: "yukOlay")
        if olay > 0 { olayUret(olay, context) }
    }

    static func paketUret(_ n: Int, _ context: ModelContext) {
        let bas = Date.now
        for p in 0..<n {
            let pid = "\(onek)paket\(p + 1)"
            var levhalar: [LevhaJSON] = []
            var sorular: [SoruJSON] = []
            for l in 0..<50 {
                let lid = "\(pid).l\(l + 1)"
                let dugumler = (0..<15).map { i in
                    DugumJSON(id: "n\(i + 1)", etiket: "Düğüm \(p + 1)-\(l + 1)-\(i + 1)", sekil: i % 4 == 0 ? .karar : .durum,
                              renk: RenkAdi.allCases[i % 5], konum: [i % 3, i / 3], tus: i % 5 == 0,
                              not: "Sentetik not \(i + 1): performans ölçümü için.", ebeveyn: nil)
                }
                let baglantilar = (0..<12).map { i in BaglantiJSON(from: "n\(i + 1)", to: "n\(i + 4)", etiket: nil, tip: nil) }
                levhalar.append(LevhaJSON(id: lid, tip: .algoritma, baslik: "Yük levhası \(p + 1).\(l + 1)",
                                          akilda_kalan: "Sentetik", duzen: DuzenJSON(izgara: [3, 5], sabit: nil),
                                          dugumler: dugumler, baglantilar: baglantilar, ortme_sirasi: ["n2", "n5", "n8"],
                                          insa_sirasi: ["n3", "n6", "n9"], revizyon: 1))
                sorular.append(SoruJSON(id: "s\(l + 1)", levha: lid, dugumler: ["n2"],
                                        kok: "Sentetik soru \(p + 1).\(l + 1): aşağıdakilerden hangisidir?",
                                        secenekler: ["A", "B", "C", "D", "E"], dogru: l % 5, aciklama: "Sentetik.",
                                        aciklama_yolu: ["n1", "n2"], celdirici_dugum: nil, kazanim: nil, kalip: "en_sik", zorluk: 1,
                                        secenek_aile: nil, ipucu_sirasi: nil, kirilimlar: nil))
            }
            // Şema 2: v3+ her soruya kazanım ister; yük paketinde kazanım yok.
            let paket = PaketJSON(sema_surumu: 2, paket_id: pid, ders: "Yük dersi", bolum: "Yük", alt_konu: "Yük paketi \(p + 1)",
                                  levhalar: levhalar, sorular: sorular, kazanimlar: nil, aileler: nil)
            if let veri = try? JSONEncoder().encode(paket) {
                let sonuc = PaketIceAktarici.iceAktar(veri: veri, dosyaAdi: "\(pid).json", context: context)
                if !sonuc.basarili { gunluk.error("yük paketi içe aktarılamadı: \(sonuc.bulgular.prefix(2).map(\.description).joined(separator: "; "))") }
            }
        }
        gunluk.notice("yük paketleri: \(n) paket, \(n * 50) levha, \(Int(Date.now.timeIntervalSince(bas) * 1000)) ms")
    }

    /// Olaylar mevcut levha ve sorulara dağıtılır; `sabotajTipi`/`baglam` alanlarında "yuk" işareti taşır.
    static func olayUret(_ n: Int, _ context: ModelContext) {
        let bas = Date.now
        let sorular = (try? context.fetch(FetchDescriptor<Soru>())) ?? []
        let levhalar = (try? context.fetch(FetchDescriptor<Levha>())) ?? []
        guard !sorular.isEmpty, !levhalar.isEmpty else { return }
        var rng = TohumluUretec(tohum: "yuk|\(n)")
        let ab = ABDeneyi.ortak
        var yazilan = 0
        while yazilan < n {
            let gun = Double(Int(rng.oran() * 90))
            let tarih = Date.now.addingTimeInterval(-gun * 86_400 - rng.oran() * 40_000)
            let r = rng.oran()
            if r < 0.5 {
                let s = sorular[Int(rng.oran() * Double(sorular.count))]
                let dogru = rng.oran() < 0.62
                let o = SoruOlayi(soruGlobalId: s.kimlik, levhaId: s.levha, secilen: dogru ? s.dogru : (s.dogru + 1) % 5, dogruMu: dogru,
                                  sureSaniye: 20 + rng.oran() * 60, tarih: tarih, guven: Int(rng.oran() * 3) + 1)
                o.baglam = "yuk"
                o.abGrup = ab.grup(s.konuPaketi?.paket_id)
                if rng.oran() < 0.3 {
                    o.kirmaSuresi = 4 + rng.oran() * 6
                    o.kalipTahmini = rng.oran() < 0.6 ? s.kalipTipi?.rawValue : KalipTipi.en_sik.rawValue
                }
                context.insert(o)
                yazilan += 1
            } else if r < 0.85 {
                let l = levhalar[Int(rng.oran() * Double(levhalar.count))]
                let hedefler = Array(l.ortme_sirasi.prefix(3))
                let grup = ab.grup(l.paket?.paket_id)
                for id in hedefler {
                    let o = OrtmeOlayi(levhaId: l.id, dugumId: id, tarih: tarih, bildim: rng.oran() < 0.7)
                    o.abGrup = grup
                    context.insert(o)
                }
                yazilan += max(1, hedefler.count)
            } else if r < 0.95 {
                let s = sorular[Int(rng.oran() * Double(sorular.count))]
                context.insert(IpucuOlayi(soruGlobalId: s.kimlik, ipucuIndeks: Int(rng.oran() * 4) + 1, toplamIpucu: 4,
                                          dogru: rng.oran() < 0.6, puan: Int(rng.oran() * 100) - 25, tarih: tarih))
                yazilan += 1
            } else {
                let l = levhalar[Int(rng.oran() * Double(levhalar.count))]
                context.insert(SabotajOlayi(levhaId: l.id, sabotajTipi: "yuk", bulundu: rng.oran() < 0.7, denemeSayisi: 1, tarih: tarih))
                yazilan += 1
            }
            if yazilan % 2000 < 3 { try? context.save() }
        }
        try? context.save()
        OlayDefteri.degisti()
        gunluk.notice("yük olayları: \(yazilan) olay, \(Int(Date.now.timeIntervalSince(bas) * 1000)) ms")
    }

    static func temizle(_ context: ModelContext) {
        for p in (try? context.fetch(FetchDescriptor<Paket>())) ?? [] where p.paket_id.hasPrefix(onek) { context.delete(p) }
        for o in (try? context.fetch(FetchDescriptor<SoruOlayi>(predicate: #Predicate { $0.baglam == "yuk" }))) ?? [] { context.delete(o) }
        for o in (try? context.fetch(FetchDescriptor<SabotajOlayi>(predicate: #Predicate { $0.sabotajTipi == "yuk" }))) ?? [] { context.delete(o) }
        try? context.save()
        OlayDefteri.degisti()
    }
}

/// `-fpsGoster 1`: köşede saniyelik kare hızı; her saniye günlüğe de yazılır (kaydırma ölçümü için).
final class FPSSayaci: ObservableObject {
    @Published var fps = 0
    private var baglanti: CADisplayLink?
    private var sayac = 0
    private var bas = CACurrentMediaTime()
    private let gunluk = Logger(subsystem: "tr.kisisel.levha", category: "fps")

    init() {
        let b = CADisplayLink(target: self, selector: #selector(adim))
        b.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        b.add(to: .main, forMode: .common)
        baglanti = b
    }

    @objc private func adim(_ b: CADisplayLink) {
        sayac += 1
        let simdi = CACurrentMediaTime()
        if simdi - bas >= 1 {
            fps = Int((Double(sayac) / (simdi - bas)).rounded())
            gunluk.notice("fps \(self.fps)")
            sayac = 0
            bas = simdi
        }
    }
}

struct FPSRozeti: View {
    @StateObject private var sayac = FPSSayaci()
    var body: some View {
        Text("\(sayac.fps) fps")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sayac.fps >= 55 ? Color.green : Color.red, in: Capsule())
            .allowsHitTesting(false)
    }
}
#endif
