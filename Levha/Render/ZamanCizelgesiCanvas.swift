import SwiftUI
import UIKit

/// Yatay zaman ekseni + en fazla 4 şerit. Olay `bit` doluysa aralık çubuğu, boşsa nokta (çip + tabana iğne).
/// Bir şeritte üst üste binen olaylar alt alta satırlara paketlenir (sıra deterministik: bas, bit, JSON sırası).
/// Keşif katmanları: 1 eksen + şeritler, 2 olaylar, 3 TUS, 4 notlar.
struct ZamanGeometri {
    let cizim: LevhaCizim
    let boyut: CGSize
    let pad: CGFloat = 10
    let eksenH: CGFloat = 26
    let baslikH: CGFloat = 15
    let tabanBosluk: CGFloat = 9
    let punto: CGFloat = 10
    let kose: CGFloat = 8

    struct Oge {
        let dugum: CizimDugumu
        let cerceve: CGRect
        let etiket: CGRect
        let cubuk: CGRect?
        let etiketDisarida: Bool
        let tabanY: CGFloat
    }

    struct Serit {
        let id: String
        let ad: String
        let cerceve: CGRect
    }

    private(set) var seritler: [Serit] = []
    private(set) var ogeler: [Oge] = []

    var solX: CGFloat { pad + 6 }
    var sagX: CGFloat { boyut.width - pad - 6 }
    var eksenY: CGFloat { boyut.height - pad - eksenH }

    func x(_ v: Double) -> CGFloat {
        let oran = (v - cizim.eksenMin) / max(0.000_001, cizim.eksenMax - cizim.eksenMin)
        return solX + CGFloat(min(1, max(0, oran))) * (sagX - solX)
    }

    init(cizim: LevhaCizim, boyut: CGSize) {
        self.cizim = cizim
        self.boyut = boyut
        yerlestir()
    }

    private mutating func yerlestir() {
        let tanimli: [(id: String, ad: String)] = cizim.seritler.isEmpty ? [(id: "", ad: "")] : cizim.seritler
        let font = UIFont.systemFont(ofSize: punto, weight: .semibold)
        let enGenis = min(112, (sagX - solX) * 0.34)

        // 1) Şerit başına satır paketleme (yatay kapsamlar).
        struct Taslak { var dugum: CizimDugumu; var kapsam: ClosedRange<CGFloat>; var genislik: CGFloat; var satir: Int }
        var seritTaslaklari: [[Taslak]] = []
        var satirSayilari: [Int] = []
        let tanimliIdler = Set(tanimli.map(\.id))
        for (si, s) in tanimli.enumerated() {
            // Şeridi tanımsız olay ilk şeride düşer.
            let secilen: [CizimDugumu] = cizim.dugumler.filter { d in
                let sid = d.serit ?? ""
                return sid == s.id || (si == 0 && !tanimliIdler.contains(sid))
            }
            let olaylar: [CizimDugumu] = secilen.indices.sorted { i, j in
                let a = secilen[i], b = secilen[j]
                let (abas, bbas) = (a.deger ?? 0, b.deger ?? 0)
                if abas != bbas { return abas < bbas }
                let (abit, bbit) = (a.bit ?? abas, b.bit ?? bbas)
                if abit != bbit { return abit < bbit }
                return i < j
            }.map { secilen[$0] }
            var satirSonlari: [CGFloat] = []
            var taslaklar: [Taslak] = []
            for d in olaylar {
                let metinW = (d.etiket as NSString).size(withAttributes: [.font: font]).width
                let w = min(enGenis, metinW + 12)
                let x0 = x(d.deger ?? cizim.eksenMin)
                var kapsam: ClosedRange<CGFloat>
                if let bit = d.bit {
                    let x1 = max(x(bit), x0 + 4)
                    if x1 - x0 >= w { kapsam = x0...x1 }
                    else if x1 + 4 + w <= sagX { kapsam = x0...(x1 + 4 + w) }
                    else { kapsam = max(solX, x0 - 4 - w)...x1 }
                } else {
                    let solKenar: CGFloat = min(max(solX, x0 - w / 2), sagX - w)
                    kapsam = solKenar...(solKenar + w)
                }
                var satir = 0
                while satir < satirSonlari.count && kapsam.lowerBound < satirSonlari[satir] + 4 { satir += 1 }
                if satir == satirSonlari.count { satirSonlari.append(kapsam.upperBound) } else { satirSonlari[satir] = kapsam.upperBound }
                taslaklar.append(Taslak(dugum: d, kapsam: kapsam, genislik: w, satir: satir))
            }
            seritTaslaklari.append(taslaklar)
            satirSayilari.append(max(1, satirSonlari.count))
        }

        // 2) Dikey bölüşüm: satır yüksekliği ortak; artan alan şeritlere eşit dağılır.
        let cizimH = eksenY - pad
        let toplamSatir = CGFloat(satirSayilari.reduce(0, +))
        let sabit = CGFloat(tanimli.count) * (baslikH + tabanBosluk)
        let satirH = min(32, max(16, (cizimH - sabit) / max(1, toplamSatir)))
        let kullanilan = sabit + toplamSatir * satirH
        let ekstra = max(0, cizimH - kullanilan) / CGFloat(tanimli.count)

        var y = pad
        for (si, s) in tanimli.enumerated() {
            let h = baslikH + CGFloat(satirSayilari[si]) * satirH + tabanBosluk + ekstra
            let cerceve = CGRect(x: pad, y: y, width: boyut.width - pad * 2, height: h)
            seritler.append(Serit(id: s.id, ad: s.ad, cerceve: cerceve))
            let alt = cerceve.maxY - tabanBosluk
            // Noktalar tabana yakın dizilir (iğne kısa kalsın); yalnız aralık içeren şerit Gantt gibi yukarıdan aşağı.
            let yalnizAralik = seritTaslaklari[si].allSatisfy { $0.dugum.bit != nil }
            let satirSayisi = satirSayilari[si]
            for t in seritTaslaklari[si] {
                let sira = yalnizAralik ? satirSayisi - 1 - t.satir : t.satir
                let ust = alt - CGFloat(sira + 1) * satirH
                let satirKutusu = CGRect(x: 0, y: ust + 2, width: 0, height: satirH - 4)
                var cubuk: CGRect?
                var etiket: CGRect
                var disarida = false
                if let bit = t.dugum.bit {
                    let x0 = x(t.dugum.deger ?? cizim.eksenMin)
                    let x1 = max(x(bit), x0 + 4)
                    let c = CGRect(x: x0, y: satirKutusu.minY, width: x1 - x0, height: satirKutusu.height)
                    cubuk = c
                    if c.width >= t.genislik {
                        etiket = c
                    } else {
                        disarida = true
                        let sag = t.kapsam.upperBound > x1 + 1
                        etiket = CGRect(x: sag ? x1 + 4 : t.kapsam.lowerBound, y: c.minY, width: t.genislik, height: c.height)
                    }
                } else {
                    etiket = CGRect(x: t.kapsam.lowerBound, y: satirKutusu.minY, width: t.genislik, height: satirKutusu.height)
                }
                let birlesik = cubuk.map { $0.union(etiket) } ?? etiket
                ogeler.append(Oge(dugum: t.dugum, cerceve: birlesik, etiket: etiket, cubuk: cubuk,
                                  etiketDisarida: disarida, tabanY: cerceve.maxY - tabanBosluk / 2))
            }
            y += h
        }
    }

    var cizgiler: [Double] { EksenAdimi.cizgiler(min: cizim.eksenMin, max: cizim.eksenMax, birim: cizim.birim) }

    var birimAdi: String { ZamanBirimi(rawValue: cizim.birim)?.ad ?? cizim.birim }

    func iskeletCiz(_ ctx: inout GraphicsContext) {
        for (i, s) in seritler.enumerated() where i % 2 == 0 {
            ctx.fill(Path(roundedRect: s.cerceve, cornerRadius: 8), with: .color(Color(hex: 0xF7F9FB)))
        }
        for v in cizgiler {
            var c = Path()
            c.move(to: CGPoint(x: x(v), y: pad))
            c.addLine(to: CGPoint(x: x(v), y: eksenY))
            ctx.stroke(c, with: .color(Color(hex: 0xE6EAEF)), lineWidth: 1)
        }
        var eksen = Path()
        eksen.move(to: CGPoint(x: solX, y: eksenY))
        eksen.addLine(to: CGPoint(x: sagX, y: eksenY))
        ctx.stroke(eksen, with: .color(Tema.cizgi), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for v in cizgiler {
            var c = Path()
            c.move(to: CGPoint(x: x(v), y: eksenY - 3))
            c.addLine(to: CGPoint(x: x(v), y: eksenY + 3))
            ctx.stroke(c, with: .color(Tema.cizgi), lineWidth: 1.5)
            let t = ctx.resolve(Text(Bicim.sayi(v)).font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundColor(Tema.ikincil))
            ctx.draw(t, at: CGPoint(x: x(v), y: eksenY + 11))
        }
        let birim = ctx.resolve(Text(birimAdi).font(.system(size: 9.5, weight: .bold)).foregroundColor(Tema.ikincil))
        ctx.draw(birim, at: CGPoint(x: sagX, y: eksenY + 21), anchor: .trailing)
    }

    /// Katman 2: iğneler, çubuklar ve çip zeminleri.
    func olaylariCiz(_ ctx: inout GraphicsContext) {
        for o in ogeler where o.cubuk == nil {
            let px = x(o.dugum.deger ?? cizim.eksenMin)
            var igne = Path()
            igne.move(to: CGPoint(x: px, y: o.etiket.maxY))
            igne.addLine(to: CGPoint(x: px, y: o.tabanY))
            ctx.stroke(igne, with: .color(o.dugum.renk.kenar.opacity(0.7)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: px - 3, y: o.tabanY - 3, width: 6, height: 6)), with: .color(o.dugum.renk.kenar))
        }
        for o in ogeler {
            if let c = o.cubuk {
                let yol = Path(roundedRect: c, cornerRadius: min(kose, c.height / 2), style: .continuous)
                ctx.fill(yol, with: .color(o.dugum.renk.zemin))
                ctx.stroke(yol, with: .color(o.dugum.renk.kenar), lineWidth: 1.5)
                if let bit = o.dugum.bit, bit >= cizim.eksenMax {
                    // Eksenin sonuna kadar süren aralık: "devam eder" oku.
                    var ok = Path()
                    ok.move(to: CGPoint(x: c.maxX + 7, y: c.midY))
                    ok.addLine(to: CGPoint(x: c.maxX + 1, y: c.midY - 5))
                    ok.addLine(to: CGPoint(x: c.maxX + 1, y: c.midY + 5))
                    ok.closeSubpath()
                    ctx.fill(ok, with: .color(o.dugum.renk.kenar))
                }
            } else {
                let yol = Path(roundedRect: o.etiket, cornerRadius: kose, style: .continuous)
                ctx.fill(yol, with: .color(o.dugum.renk.zemin))
                ctx.stroke(yol, with: .color(o.dugum.renk.kenar), lineWidth: 1.5)
            }
        }
    }

    func tusCiz(_ ctx: inout GraphicsContext) {
        for o in ogeler where o.dugum.tus {
            let r = o.cubuk ?? o.etiket
            ctx.stroke(Path(roundedRect: r, cornerRadius: min(kose, r.height / 2), style: .continuous),
                       with: .color(o.dugum.renk.kenar), lineWidth: 3)
        }
    }

    func degerMetni(_ d: CizimDugumu) -> String {
        let bas = Bicim.sayi(d.deger ?? 0)
        if let bit = d.bit { return "\(bas)–\(bit >= cizim.eksenMax ? "…" : Bicim.sayi(bit)) \(birimAdi)" }
        return "\(bas). \(birimAdi)"
    }
}

struct ZamanCizelgesiCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        let g = ZamanGeometri(cizim: cizim, boyut: boyut)

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in g.iskeletCiz(&ctx) }
            ForEach(g.seritler, id: \.id) { s in
                Text(s.ad.uppercased(with: Bicim.tr))
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Tema.ikincil)
                    .lineLimit(1)
                    .frame(width: s.cerceve.width - 12, alignment: .leading)
                    .position(x: s.cerceve.midX, y: s.cerceve.minY + 9)
            }
            Canvas { ctx, _ in g.olaylariCiz(&ctx) }
                .katmanda(durum.katman >= 2)
            Canvas { ctx, _ in g.tusCiz(&ctx) }
                .katmanda(durum.katman >= 3)

            ForEach(g.ogeler, id: \.dugum.id) { o in
                Button { dokun(o.dugum.id) } label: {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        Text(o.dugum.etiket)
                            .font(Sigdir.font(o.dugum.etiket, temel: g.punto, genislik: o.etiket.width - 8, agirlik: .semibold))
                            .foregroundStyle(o.dugum.renk.yazi)
                            .multilineTextAlignment(o.etiketDisarida ? .leading : .center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                            .frame(width: o.etiket.width, height: o.etiket.height,
                                   alignment: o.etiketDisarida ? .leading : .center)
                            .offset(x: o.etiket.minX - o.cerceve.minX, y: o.etiket.minY - o.cerceve.minY)
                    }
                    .frame(width: o.cerceve.width, height: o.cerceve.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // İnşa'da boş olayın çubuk dışındaki etiketi de gizlenir (yoksa cevabı ele verir).
                .katmanda(durum.katman >= 2 && !(durum.mod == .insa && durum.gizli.contains(o.dugum.id)))
                .allowsHitTesting(durum.dokunulabilir)
                .position(x: o.cerceve.midX, y: o.cerceve.midY)
                .accessibilityLabel(o.dugum.etiket)
                .accessibilityValue(g.degerMetni(o.dugum))
            }

            // İnşa'da boş kutu yalnız çubuk kadardır (aralığın uzunluğu ipucudur); diğer modlarda etiket dahil.
            DugumUstKatmani(alanlar: g.ogeler.map { DugumAlani(id: $0.dugum.id,
                                                              cerceve: durum.mod == .insa ? ($0.cubuk ?? $0.cerceve) : $0.cerceve,
                                                              kose: g.kose) },
                            durum: durum, boyut: boyut, dokun: dokun)
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.katman)
    }
}
