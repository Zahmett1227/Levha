import SwiftUI

/// Yatay cetvel. Sabit değerli işaretler eksenin üstüne/altına dönüşümlü yerleşir;
/// değeri olmayan (nomograma bağlı) işaretler alttaki şeritte durur.
/// Keşif katmanları: 1 işaret başlıkları, 2 değerler + bağlantı çizgileri, 3 TUS, 4 notlar.
struct CetvelGeometri {
    let cizim: LevhaCizim
    let boyut: CGSize
    let pad: CGFloat = 12
    let kose: CGFloat = 10
    let kutuH: CGFloat = 46
    let eksenBosluk: CGFloat = 26

    let sabitler: [CizimDugumu]
    let nomogramlar: [CizimDugumu]
    private(set) var kutular: [String: CGRect] = [:]

    init(cizim: LevhaCizim, boyut: CGSize) {
        self.cizim = cizim
        self.boyut = boyut
        sabitler = cizim.dugumler.filter { $0.deger != nil }.sorted { ($0.deger ?? 0) < ($1.deger ?? 0) }
        nomogramlar = cizim.dugumler.filter { $0.deger == nil }
        kutular = yerlestir()
    }

    var seritH: CGFloat { nomogramlar.isEmpty ? 0 : 74 }
    var eksenY: CGFloat { (boyut.height - seritH) / 2 }
    var solX: CGFloat { pad + 10 }
    var sagX: CGFloat { boyut.width - pad - 10 }
    var kutuW: CGFloat { min(124, (boyut.width - pad * 2) * 0.36) }

    func x(_ v: Double) -> CGFloat {
        let oran = (v - cizim.eksenMin) / max(0.000_001, cizim.eksenMax - cizim.eksenMin)
        return solX + CGFloat(oran) * (sagX - solX)
    }

    /// Değere göre sıralı işaretler dönüşümlü üst/alt; çakışan kutu bir kat dışarı itilir.
    private func yerlestir() -> [String: CGRect] {
        var sonuc: [String: CGRect] = [:]
        var ustKatlar: [CGFloat] = []
        var altKatlar: [CGFloat] = []
        for (i, d) in sabitler.enumerated() {
            let ust = i % 2 == 0
            let minX = min(max(pad, x(d.deger ?? 0) - kutuW / 2), boyut.width - pad - kutuW)
            var katlar = ust ? ustKatlar : altKatlar
            var kat = 0
            while kat < katlar.count && minX < katlar[kat] + 6 { kat += 1 }
            if kat == katlar.count { katlar.append(minX + kutuW) } else { katlar[kat] = minX + kutuW }
            if ust { ustKatlar = katlar } else { altKatlar = katlar }
            let adim = CGFloat(kat) * (kutuH + 8)
            let y = ust ? max(pad, eksenY - eksenBosluk - kutuH - adim) : eksenY + eksenBosluk + adim
            sonuc[d.id] = CGRect(x: minX, y: y, width: kutuW, height: kutuH)
        }
        if !nomogramlar.isEmpty {
            let bosluk: CGFloat = 8
            let w = (boyut.width - pad * 2 - bosluk * CGFloat(nomogramlar.count - 1)) / CGFloat(nomogramlar.count)
            let y = boyut.height - seritH + 27
            for (i, d) in nomogramlar.enumerated() {
                sonuc[d.id] = CGRect(x: pad + CGFloat(i) * (w + bosluk), y: y, width: w, height: seritH - 27 - pad + 4)
            }
        }
        return sonuc
    }

    var cizgiler: [Double] { EksenAdimi.cizgiler(min: cizim.eksenMin, max: cizim.eksenMax, birim: cizim.birim) }

    func eksenCiz(_ ctx: inout GraphicsContext) {
        var eksen = Path()
        eksen.move(to: CGPoint(x: solX, y: eksenY))
        eksen.addLine(to: CGPoint(x: sagX, y: eksenY))
        ctx.stroke(eksen, with: .color(Tema.cizgi), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for v in cizgiler {
            var c = Path()
            c.move(to: CGPoint(x: x(v), y: eksenY - 4))
            c.addLine(to: CGPoint(x: x(v), y: eksenY + 4))
            ctx.stroke(c, with: .color(Tema.cizgi), lineWidth: 1.5)
        }
        let birim = ctx.resolve(Text(cizim.birim).font(.system(size: 9.5, weight: .bold)).foregroundColor(Tema.ikincil))
        ctx.draw(birim, at: CGPoint(x: sagX, y: eksenY - 12), anchor: .trailing)

        if !nomogramlar.isEmpty {
            var ayrac = Path()
            let y = boyut.height - seritH + 4
            ayrac.move(to: CGPoint(x: pad, y: y))
            ayrac.addLine(to: CGPoint(x: boyut.width - pad, y: y))
            ctx.stroke(ayrac, with: .color(Tema.kartKenar), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// Tik değerleri bağlantı çizgilerinin üstünde, beyaz zeminle çizilir ki okunur kalsın.
    func tikEtiketleriniCiz(_ ctx: inout GraphicsContext) {
        for v in cizgiler {
            let t = ctx.resolve(Text(Bicim.sayi(v)).font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundColor(Tema.ikincil))
            let s = t.measure(in: CGSize(width: 60, height: 20))
            let merkez = CGPoint(x: x(v), y: eksenY + 13)
            ctx.fill(Path(roundedRect: CGRect(x: merkez.x - s.width / 2 - 2, y: merkez.y - s.height / 2, width: s.width + 4, height: s.height), cornerRadius: 3),
                     with: .color(.white))
            ctx.draw(t, at: merkez)
        }
    }

    func kutulariCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler {
            guard let f = kutular[d.id] else { continue }
            let yol = Path(roundedRect: f, cornerRadius: kose, style: .continuous)
            ctx.fill(yol, with: .color(d.renk.zemin))
            ctx.stroke(yol, with: .color(d.renk.kenar), lineWidth: 1.5)
        }
    }

    /// Katman 2: işaret noktaları ve kutuya giden bağlantı çizgileri.
    /// Örtmede gizli işaretin noktası da saklanır; yoksa eksendeki yeri cevabı ele verir.
    func baglantilariCiz(_ ctx: inout GraphicsContext, gizli: Set<String>) {
        let sabitler = sabitler.filter { !gizli.contains($0.id) }
        for d in sabitler {
            guard let v = d.deger, let f = kutular[d.id] else { continue }
            let px = x(v)
            let ust = f.maxY <= eksenY
            let hedefX = min(max(px, f.minX + 10), f.maxX - 10)
            var cizgi = Path()
            cizgi.move(to: CGPoint(x: px, y: eksenY + (ust ? -6 : 6)))
            cizgi.addLine(to: CGPoint(x: hedefX, y: ust ? f.maxY : f.minY))
            ctx.stroke(cizgi, with: .color(d.renk.kenar), lineWidth: 1.5)
        }
        for d in sabitler {
            guard let v = d.deger else { continue }
            let nokta = Path(ellipseIn: CGRect(x: x(v) - 6, y: eksenY - 6, width: 12, height: 12))
            ctx.fill(nokta, with: .color(d.renk.kenar))
            ctx.stroke(nokta, with: .color(.white), lineWidth: 2)
        }
    }

    func tusCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler where d.tus {
            guard let f = kutular[d.id] else { continue }
            ctx.stroke(Path(roundedRect: f, cornerRadius: kose, style: .continuous), with: .color(d.renk.kenar), lineWidth: 3)
        }
    }
}

struct SayiCetveliCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        let g = CetvelGeometri(cizim: cizim, boyut: boyut)

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in g.eksenCiz(&ctx) }
            Canvas { ctx, _ in g.baglantilariCiz(&ctx, gizli: durum.mod == .ortme ? durum.gizli : []) }
                .katmanda(durum.katman >= 2)
            Canvas { ctx, _ in g.tikEtiketleriniCiz(&ctx) }
            Canvas { ctx, _ in g.kutulariCiz(&ctx) }
            Canvas { ctx, _ in g.tusCiz(&ctx) }
                .katmanda(durum.katman >= 3)

            if !g.nomogramlar.isEmpty {
                Text("SABİT SAYI YOK · NOTUNA BAK")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Tema.ikincil)
                    .frame(width: boyut.width - g.pad * 2, alignment: .leading)
                    .position(x: boyut.width / 2, y: boyut.height - g.seritH + 14)
            }

            ForEach(cizim.dugumler) { d in
                if let f = g.kutular[d.id] {
                    Button { dokun(d.id) } label: {
                        VStack(spacing: 2) {
                            Text(d.etiket)
                                .font(Sigdir.font(d.etiket, temel: 11, genislik: f.width - 12, agirlik: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text(d.deger.map { "\(Bicim.sayi($0)) \(cizim.birim)" } ?? "sabit değil")
                                .font(.system(size: 11.5, weight: .heavy).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .katmanda(durum.katman >= 2)
                        }
                        .foregroundStyle(d.renk.yazi)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 5)
                        .frame(width: f.width, height: f.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(durum.dokunulabilir)
                    .position(x: f.midX, y: f.midY)
                    .accessibilityLabel(d.etiket)
                    .accessibilityValue(d.deger.map { "\(Bicim.sayi($0)) \(cizim.birim)" } ?? "sabit sayı yok")
                }
            }

            DugumUstKatmani(alanlar: cizim.dugumler.compactMap { d in g.kutular[d.id].map { DugumAlani(id: d.id, cerceve: $0, kose: g.kose) } },
                            durum: durum, boyut: boyut, dokun: dokun)
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.katman)
    }
}
