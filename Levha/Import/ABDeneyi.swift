import Foundation
import SwiftData
import Observation

/// A/B deneyi: alt konular (paketler) rastgele "levha" ve "metin" gruplarına ayrılır; atama deney boyunca sabittir.
/// Metin grubundaki levhalar `MetinCanvas` ile düz liste olarak çizilir; Sabotaj ve İnşa kapalıdır.
@Observable
@MainActor
final class ABDeneyi {
    static let ortak = ABDeneyi()
    nonisolated static let levha = "levha"
    nonisolated static let metin = "metin"

    private(set) var gruplar: [String: String] = [:]
    private(set) var baslangic: Date?

    var aktif: Bool { !gruplar.isEmpty }

    func yukle(_ context: ModelContext) {
        let hepsi = (try? context.fetch(FetchDescriptor<ABGrup>())) ?? []
        gruplar = Dictionary(hepsi.map { ($0.paketId, $0.grup) }, uniquingKeysWith: { a, _ in a })
        baslangic = hepsi.map(\.atamaTarihi).min()
    }

    func grup(_ paketId: String?) -> String? { paketId.flatMap { gruplar[$0] } }
    func metinMi(_ paketId: String?) -> Bool { grup(paketId) == Self.metin }
    func metinMi(_ levha: Levha) -> Bool { metinMi(levha.paket?.paket_id) }

    /// Tüm alt konuları (Yazdıklarım ve soru paketleri hariç) karıştırıp ikiye böler; tek sayıda fazlası levha grubuna.
    func baslat(_ context: ModelContext) {
        temizle(context)
        let paketler = ((try? context.fetch(FetchDescriptor<Paket>())) ?? []).filter(\.konuPaketiMi).shuffled()
        let simdi = Date.now
        let levhaSayisi = (paketler.count + 1) / 2
        for (i, p) in paketler.enumerated() {
            context.insert(ABGrup(paketId: p.paket_id, grup: i < levhaSayisi ? Self.levha : Self.metin, atamaTarihi: simdi))
        }
        try? context.save()
        yukle(context)
        OlayDefteri.degisti()
    }

    func kapat(_ context: ModelContext) {
        temizle(context)
        try? context.save()
        yukle(context)
        OlayDefteri.degisti()
    }

    private func temizle(_ context: ModelContext) {
        for g in (try? context.fetch(FetchDescriptor<ABGrup>())) ?? [] { context.delete(g) }
    }
}
