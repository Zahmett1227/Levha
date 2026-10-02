import Foundation
import SwiftData
import WidgetKit

/// Widget için anlık görüntü: bugünün tur dakikası, vadeli levha sayısı ve önceliğe göre sıralı
/// vadeli levhaların küçültülmüş çizimi (yalnız kutular + renkler). Levha geometrisi uygulamanın
/// render motorundan alınır; widget aynı düzeni hesaplamak zorunda kalmaz.
@MainActor
enum WidgetYazici {
    static let cizimBoyutu = CGSize(width: 340, height: 200)
    static let enFazlaLevha = 12

    static func yaz(_ context: ModelContext) {
        let tur = TurPlanlayici.bugun(context)
        let levhalar = TurPlanlayici.siraliLevhalar(context)
        let durumlar = DurumServisi.tumDurumlar(context)
        let vadeli = levhalar.filter { DurumServisi.vadeliMi(durumlar[$0.id]) }
        let sirali = DurumServisi.oncelikSirala(vadeli.isEmpty ? levhalar : vadeli, context)
        let anlik = WidgetAnligi(olusturma: .now,
                                 tamamlananDakika: TurPlanlayici.tamamlananDakika(tur),
                                 planlananDakika: TurPlanlayici.planlananDakika(tur),
                                 vadeliSayisi: vadeli.count,
                                 levhalar: sirali.prefix(enFazlaLevha).map { levhaAnligi($0, context) })
        if WidgetDeposu.yaz(anlik) { WidgetCenter.shared.reloadAllTimelines() }
    }

    static func levhaAnligi(_ l: Levha, _ context: ModelContext) -> WidgetLevhasi {
        let c = LevhaCizim(l)
        let b = cizimBoyutu
        var kutular: [(id: String, cerceve: CGRect, kose: CGFloat, renk: String)] = []
        switch c.tip {
        case .algoritma, .yolak, .agac, .none:
            let stil: IzgaraStili = c.tip == .yolak ? .yolak : (c.tip == .agac ? .agac : .algoritma)
            let g = IzgaraGeometri(cizim: c, boyut: b, stil: stil)
            kutular = g.yerlesikler.map { ($0.id, g.cerceve($0), g.kose($0), $0.renkAdi) }
        case .matris:
            let g = MatrisGeometri(cizim: c, boyut: b)
            kutular = c.dugumler.map { ($0.id, g.hucre($0), g.kose, $0.renkAdi) }
        case .sayi_cetveli:
            let g = CetvelGeometri(cizim: c, boyut: b)
            kutular = c.dugumler.compactMap { d in g.kutular[d.id].map { (d.id, $0, g.kose, d.renkAdi) } }
        case .zaman_cizelgesi:
            let g = ZamanGeometri(cizim: c, boyut: b)
            kutular = g.ogeler.map { ($0.dugum.id, $0.cubuk ?? $0.etiket, g.kose, $0.dugum.renkAdi) }
        case .vucut_haritasi:
            let g = VucutGeometri(cizim: c, boyut: b)
            kutular = c.dugumler.compactMap { d in g.etiketler[d.id].map { (d.id, $0, g.kose, d.renkAdi) } }
        }
        // Maskeli düğüm: Örtme'deki gibi zayıflığı en yüksek olan, eşitlikte ortme_sirasi'nda öndeki.
        let zayiflik = DurumServisi.zayifliklar(l.id, context)
        let mevcut = Set(kutular.map(\.id))
        let aday = l.ortme_sirasi.filter(mevcut.contains)
        let maskeli = aday.indices.max { i, j in
            let (a, b) = (zayiflik[aday[i]] ?? 0, zayiflik[aday[j]] ?? 0)
            return a != b ? a < b : i > j
        }.map { aday[$0] }
        return WidgetLevhasi(
            id: l.id, baslik: l.baslik, altKonu: l.paket?.alt_konu ?? "",
            oran: b.width / b.height, maskeli: maskeli ?? kutular.first?.id,
            kutular: kutular.map { k in
                WidgetKutusu(id: k.id, x: k.cerceve.minX / b.width, y: k.cerceve.minY / b.height,
                             w: k.cerceve.width / b.width, h: k.cerceve.height / b.height, renk: k.renk,
                             kose: k.kose / max(1, min(k.cerceve.width, k.cerceve.height)))
            })
    }
}
