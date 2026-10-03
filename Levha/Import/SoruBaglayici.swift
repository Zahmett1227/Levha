import Foundation
import SwiftData

/// Soru paketi (v5) sorularının levha ve kazanım referansları. Levha tam id'siyle (`paket_id.levha`) ya da paket
/// öneki + kısa id ile aranır. Kazanım sırayla soru paketinin kendi kazanımlarında, tam yolda (`paket_id.k3`), bağlı
/// levhanın paketinde ve aynı ders/alt konunun konu paketlerinde aranır. Çözülemeyen referans saklanır; ilgili paket
/// içe aktarılınca ya da silinince yeniden denenir.
@MainActor
enum SoruBaglayici {
    struct KazanimBilgisi {
        var paketId: String
        var id: String
        var kalip: String
        var sorulabilirlik: Int
    }

    static func bagla(_ s: Soru, paket: Paket, ozKazanimlar: [String: KazanimBilgisi], _ context: ModelContext) {
        if let ref = s.levhaRef, let l = levhaBul(ref, context) {
            s.levha = l.id
            s.levhaPaketId = l.paket?.paket_id
        } else {
            s.levha = ""
            s.levhaPaketId = nil
        }
        let k = kazanimBul(s, paket: paket, ozKazanimlar: ozKazanimlar, context)
        s.kazanimPaketId = k?.paketId
        s.cozumle(ders: paket.ders, kazanimKalibi: k?.kalip, kazanimSorulabilirligi: k?.sorulabilirlik)
    }

    static func levhaBul(_ ref: String, _ context: ModelContext) -> Levha? {
        if let l = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == ref })).first { return l }
        let paketler = (try? context.fetch(FetchDescriptor<Paket>())) ?? []
        for p in paketler where ref.hasPrefix(p.paket_id + ".") {
            let kisa = String(ref.dropFirst(p.paket_id.count + 1))
            if let l = p.levhalar.first(where: { $0.id == kisa }) { return l }
        }
        return nil
    }

    static func kazanimBul(_ s: Soru, paket: Paket, ozKazanimlar: [String: KazanimBilgisi], _ context: ModelContext) -> KazanimBilgisi? {
        guard let ref = s.kazanim, !ref.isEmpty else { return nil }
        if let k = ozKazanimlar[ref] { return k }
        let digerleri = ((try? context.fetch(FetchDescriptor<Paket>())) ?? []).filter { $0.paket_id != paket.paket_id }
        func bilgi(_ p: Paket, _ id: String) -> KazanimBilgisi? {
            p.kazanimlar.first { $0.id == id }.map { KazanimBilgisi(paketId: p.paket_id, id: $0.id, kalip: $0.kalip, sorulabilirlik: $0.sorulabilirlik) }
        }
        for p in digerleri where ref.hasPrefix(p.paket_id + ".") {
            if let k = bilgi(p, String(ref.dropFirst(p.paket_id.count + 1))) { return k }
        }
        if let pid = s.levhaPaketId, let p = digerleri.first(where: { $0.paket_id == pid }), let k = bilgi(p, ref) { return k }
        for p in digerleri where p.konuPaketiMi && p.ders == paket.ders && p.alt_konu == paket.alt_konu {
            if let k = bilgi(p, ref) { return k }
        }
        return nil
    }

    static func ozKazanimlar(_ p: Paket) -> [String: KazanimBilgisi] {
        Dictionary(p.kazanimlar.map { ($0.id, KazanimBilgisi(paketId: p.paket_id, id: $0.id, kalip: $0.kalip, sorulabilirlik: $0.sorulabilirlik)) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Tüm soru paketlerinde çözülmemiş (ya da paketi silinmiş) levha/kazanım referanslarını yeniden dener.
    static func yenidenBagla(_ context: ModelContext) {
        let tumPaketler = (try? context.fetch(FetchDescriptor<Paket>())) ?? []
        let soruPaketleri = tumPaketler.filter(\.soruPaketiMi)
        guard !soruPaketleri.isEmpty else { return }
        let paketIdleri = Set(tumPaketler.map(\.paket_id))
        var istek = FetchDescriptor<Levha>()
        istek.propertiesToFetch = [\.id]
        let levhaIdleri = Set(((try? context.fetch(istek)) ?? []).map(\.id))
        var degisti = false
        for p in soruPaketleri {
            let oz = ozKazanimlar(p)
            for s in p.sorular {
                let levhaEksik = s.levhaRef != nil && (s.levha.isEmpty || !levhaIdleri.contains(s.levha))
                let kazanimEksik = s.kazanim != nil && (s.kazanimPaketId.map { !paketIdleri.contains($0) } ?? true)
                guard levhaEksik || kazanimEksik else { continue }
                let onceki = (s.levha, s.kazanimPaketId)
                bagla(s, paket: p, ozKazanimlar: oz, context)
                if onceki != (s.levha, s.kazanimPaketId) { degisti = true }
            }
        }
        if degisti {
            try? context.save()
            OlayDefteri.degisti()
        }
    }
}
