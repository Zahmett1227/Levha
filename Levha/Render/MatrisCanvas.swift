import SwiftUI

/// Satır × sütun tablosu. Hücreler düğümdür (id `r{satır}c{sütun}`).
/// Keşif katmanları: 1 başlıklar, 2 hücreler, 3 TUS vurguları, 4 notlar.
struct MatrisGeometri {
    let cizim: LevhaCizim
    let boyut: CGSize
    let pad: CGFloat = 8

    var satirSayisi: Int { max(1, cizim.satirlar.count) }
    var sutunSayisi: Int { max(1, cizim.sutunlar.count) }
    var basSutunW: CGFloat { max(64, boyut.width * 0.22) }
    var basSatirH: CGFloat { min(46, max(32, boyut.height * 0.1)) }
    var hucreW: CGFloat { (boyut.width - pad * 2 - basSutunW) / CGFloat(sutunSayisi) }
    var hucreH: CGFloat { (boyut.height - pad * 2 - basSatirH) / CGFloat(satirSayisi) }
    let kose: CGFloat = 10

    func hucre(_ d: CizimDugumu) -> CGRect {
        CGRect(x: pad + basSutunW + CGFloat(d.sutun) * hucreW, y: pad + basSatirH + CGFloat(d.satir) * hucreH,
               width: hucreW, height: hucreH).insetBy(dx: 3, dy: 3)
    }

    func sutunBasligi(_ c: Int) -> CGRect {
        CGRect(x: pad + basSutunW + CGFloat(c) * hucreW, y: pad, width: hucreW, height: basSatirH).insetBy(dx: 3, dy: 2)
    }

    func satirBasligi(_ r: Int) -> CGRect {
        CGRect(x: pad, y: pad + basSatirH + CGFloat(r) * hucreH, width: basSutunW, height: hucreH).insetBy(dx: 3, dy: 3)
    }

    /// Katman 1: başlık zeminleri ve boş hücre çerçeveleri (iskelet hep görünür).
    func iskeletCiz(_ ctx: inout GraphicsContext) {
        for r in 0..<cizim.satirlar.count {
            ctx.fill(Path(roundedRect: satirBasligi(r), cornerRadius: kose, style: .continuous), with: .color(Tema.maskeZemin))
        }
        for d in cizim.dugumler {
            ctx.stroke(Path(roundedRect: hucre(d), cornerRadius: kose, style: .continuous), with: .color(Tema.kartKenar), lineWidth: 1)
        }
    }

    func hucreleriCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler {
            let yol = Path(roundedRect: hucre(d), cornerRadius: kose, style: .continuous)
            ctx.fill(yol, with: .color(d.renk.zemin))
            ctx.stroke(yol, with: .color(d.renk.kenar), lineWidth: 1.5)
        }
    }

    func tusCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler where d.tus {
            ctx.stroke(Path(roundedRect: hucre(d), cornerRadius: kose, style: .continuous), with: .color(d.renk.kenar), lineWidth: 3)
        }
    }
}

struct MatrisCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        let g = MatrisGeometri(cizim: cizim, boyut: boyut)

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in g.iskeletCiz(&ctx) }
            Canvas { ctx, _ in g.hucreleriCiz(&ctx) }
                .katmanda(durum.katman >= 2)
            Canvas { ctx, _ in g.tusCiz(&ctx) }
                .katmanda(durum.katman >= 3)

            ForEach(Array(cizim.sutunlar.enumerated()), id: \.offset) { c, baslik in
                let f = g.sutunBasligi(c)
                Text(baslik)
                    .font(Sigdir.font(baslik, temel: 10.5, genislik: f.width - 4, agirlik: .bold))
                    .foregroundStyle(Tema.ikincil)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: f.width, height: f.height)
                    .position(x: f.midX, y: f.midY)
            }
            ForEach(Array(cizim.satirlar.enumerated()), id: \.offset) { r, baslik in
                let f = g.satirBasligi(r)
                Text(baslik)
                    .font(Sigdir.font(baslik, temel: 12, genislik: f.width - 16, agirlik: .bold))
                    .foregroundStyle(Tema.metin)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 7)
                    .frame(width: f.width, height: f.height, alignment: .leading)
                    .position(x: f.midX, y: f.midY)
            }

            ForEach(cizim.dugumler) { d in
                let f = g.hucre(d)
                Button { dokun(d.id) } label: {
                    Text(d.etiket)
                        .font(Sigdir.font(d.etiket, temel: 11.5, genislik: f.width - 10, agirlik: .semibold))
                        .foregroundStyle(d.renk.yazi)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                        .frame(width: f.width, height: f.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .katmanda(durum.katman >= 2)
                .allowsHitTesting(durum.dugumlerDokunulabilir)
                .position(x: f.midX, y: f.midY)
                .accessibilityLabel("\(satirAdi(d)), \(sutunAdi(d)): \(d.etiket)")
                .accessibilityValue(d.tus ? "TUS'un sevdiği hücre" : "")
            }

            DugumUstKatmani(alanlar: cizim.dugumler.map { DugumAlani(id: $0.id, cerceve: g.hucre($0), kose: g.kose) },
                            durum: durum, boyut: boyut, dokun: dokun)
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.katman)
    }

    private func satirAdi(_ d: CizimDugumu) -> String { cizim.satirlar.indices.contains(d.satir) ? cizim.satirlar[d.satir] : "" }
    private func sutunAdi(_ d: CizimDugumu) -> String { cizim.sutunlar.indices.contains(d.sutun) ? cizim.sutunlar[d.sutun] : "" }
}
