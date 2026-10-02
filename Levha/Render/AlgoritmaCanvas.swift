import SwiftUI

/// Algoritma, yolak ve ağaç: düğümler JSON'daki [sütun, satır] ızgarasına oturur;
/// motor hiçbir düğümü yeniden yerleştirmez.
enum IzgaraStili {
    case algoritma, yolak, agac

    /// Yolakta aynı satırda yatay oklar sık; sütun arası daha geniş.
    var yatayBosluk: CGFloat { self == .yolak ? 26 : 12 }
}

struct IzgaraGeometri {
    let cizim: LevhaCizim
    let boyut: CGSize
    let stil: IzgaraStili
    let pad: CGFloat = 10

    var hucreW: CGFloat { (boyut.width - pad * 2) / CGFloat(cizim.sutun) }
    var hucreH: CGFloat { (boyut.height - pad * 2) / CGFloat(cizim.satir) }
    var dugumW: CGFloat { max(40, hucreW - stil.yatayBosluk) }
    /// Satırlar arasında bağlantı etiketleri için ~30 pt kanal bırakılır.
    var dugumH: CGFloat { min(max(34, hucreH - 30), 68) }
    var punto: CGFloat { hucreW >= 100 ? 12.5 : 11 }

    var yerlesikler: [CizimDugumu] { cizim.dugumler.filter { $0.konum.count == 2 } }

    func cerceve(_ d: CizimDugumu) -> CGRect {
        CGRect(x: pad + CGFloat(d.sutun) * hucreW + (hucreW - dugumW) / 2,
               y: pad + CGFloat(d.satir) * hucreH + (hucreH - dugumH) / 2,
               width: dugumW, height: dugumH)
    }

    func kose(_ d: CizimDugumu) -> CGFloat {
        switch d.sekil {
        case .surec: return min(22, dugumH / 2)
        case .madde: return 4
        case .durum, .karar: return 10
        }
    }

    // MARK: Katmanlar

    /// Ağaçta derinlik (kök 0). Bağlantılar ebeveyn → çocuk yönündedir.
    var derinlikler: [String: Int] {
        var ebeveyn: [String: String] = [:]
        for b in cizim.baglantilar where ebeveyn[b.to] == nil { ebeveyn[b.to] = b.from }
        var sonuc: [String: Int] = [:]
        for d in cizim.dugumler {
            var n = 0
            var simdiki = d.id
            var gorulen: Set<String> = [simdiki]
            while let e = ebeveyn[simdiki], gorulen.insert(e).inserted {
                n += 1
                simdiki = e
            }
            sonuc[d.id] = n
        }
        return sonuc
    }

    /// Düğümün göründüğü ilk Keşif katmanı.
    func dugumKatmani(_ d: CizimDugumu, derinlik: [String: Int]) -> Int {
        stil == .agac && (derinlik[d.id] ?? 0) > 1 ? 2 : 1
    }

    func baglantiKatmani(_ b: CizimBaglantisi, derinlik: [String: Int]) -> Int {
        guard stil == .agac else { return 2 }
        let k = [b.from, b.to].compactMap { id in cizim.dugum(id).map { dugumKatmani($0, derinlik: derinlik) } }
        return k.max() ?? 1
    }

    // MARK: Rota

    /// `r` satırının altındaki kanalın (iki satır arasındaki boşluğun) orta çizgisi.
    func kanalY(altinda r: Int) -> CGFloat { pad + CGFloat(r + 1) * hucreH }

    struct Rota {
        var noktalar: [CGPoint]
        var etiketNoktasi: CGPoint
    }

    /// Dik (ortogonal) rota: kaynaktan kanala in, kanalda yatay git, hedefe in.
    func rota(_ b: CizimBaglantisi, dolu: Set<[Int]>) -> Rota? {
        guard let a = cizim.dugum(b.from), let t = cizim.dugum(b.to), a.konum.count == 2, t.konum.count == 2 else { return nil }
        let fa = cerceve(a), ft = cerceve(t)
        let (c1, r1, c2, r2) = (a.sutun, a.satir, t.sutun, t.satir)

        if r1 == r2 {
            let sag = c2 > c1
            let p0 = CGPoint(x: sag ? fa.maxX : fa.minX, y: fa.midY)
            let p1 = CGPoint(x: sag ? ft.minX : ft.maxX, y: ft.midY)
            return Rota(noktalar: [p0, p1], etiketNoktasi: CGPoint(x: (p0.x + p1.x) / 2, y: fa.midY - 10))
        }

        let asagi = r2 > r1
        let p0 = CGPoint(x: fa.midX, y: asagi ? fa.maxY : fa.minY)
        let p1 = CGPoint(x: ft.midX, y: asagi ? ft.minY : ft.maxY)
        let hedefeYakinKanal = asagi ? kanalY(altinda: r2 - 1) : kanalY(altinda: r2)

        if c1 == c2 {
            return Rota(noktalar: [p0, p1], etiketNoktasi: CGPoint(x: p0.x, y: hedefeYakinKanal))
        }

        // Hedef sütunu aradaki satırlarda boşsa kaynağın hemen yanındaki kanalı kullan.
        let araSatirlar = asagi ? Array((r1 + 1)..<r2) : Array((r2 + 1)..<r1)
        let hedefSutunuBos = araSatirlar.allSatisfy { !dolu.contains([c2, $0]) }
        let kaynagaYakinKanal = asagi ? kanalY(altinda: r1) : kanalY(altinda: r1 - 1)
        let kanal = hedefSutunuBos ? kaynagaYakinKanal : hedefeYakinKanal

        return Rota(noktalar: [p0, CGPoint(x: p0.x, y: kanal), CGPoint(x: p1.x, y: kanal), p1],
                    etiketNoktasi: CGPoint(x: p1.x, y: kanal))
    }

    // MARK: Çizim

    /// `katman`: yalnız o katmanda beliren bağlantılar; nil ise hepsi. `vurgu`: yalnız kalın vurgulananlar.
    func baglantilariCiz(_ ctx: inout GraphicsContext, katman: Int?, vurgu: Set<String>?) {
        let dolu = Set(yerlesikler.map(\.konum))
        let derinlik = derinlikler
        var etiketler: [(String, CGPoint)] = []

        for b in cizim.baglantilar {
            if let katman, baglantiKatmani(b, derinlik: derinlik) != katman { continue }
            if let vurgu, !vurgu.contains(b.anahtar) && !vurgu.contains("\(b.to)>\(b.from)") { continue }
            guard let r = rota(b, dolu: dolu), r.noktalar.count >= 2 else { continue }
            let kalin = vurgu != nil
            let renk = kalin ? Tema.metin : (b.tip == .inhibe ? Tema.ikincil : Tema.cizgi)
            let kalinlik: CGFloat = kalin ? 3 : 1.5

            var noktalar = r.noktalar
            let uc = noktalar[noktalar.count - 1]
            let onceki = noktalar[noktalar.count - 2]
            let uzunluk = max(0.001, hypot(uc.x - onceki.x, uc.y - onceki.y))
            let yon = CGVector(dx: (uc.x - onceki.x) / uzunluk, dy: (uc.y - onceki.y) / uzunluk)
            let dik = CGVector(dx: -yon.dy, dy: yon.dx)
            let okBoyu: CGFloat = b.tip == .inhibe ? 4 : 7
            let taban = CGPoint(x: uc.x - yon.dx * okBoyu, y: uc.y - yon.dy * okBoyu)
            noktalar[noktalar.count - 1] = taban

            var yol = Path()
            yol.addLines(noktalar)
            let cizgiStili = StrokeStyle(lineWidth: kalinlik, lineCap: .round, lineJoin: .round,
                                         dash: b.tip == .olasi ? [5, 4] : [])
            ctx.stroke(yol, with: .color(renk), style: cizgiStili)

            if b.tip == .inhibe {
                // ⊣ : uçta dik çubuk
                var cubuk = Path()
                cubuk.move(to: CGPoint(x: taban.x + dik.dx * 7, y: taban.y + dik.dy * 7))
                cubuk.addLine(to: CGPoint(x: taban.x - dik.dx * 7, y: taban.y - dik.dy * 7))
                ctx.stroke(cubuk, with: .color(renk), style: StrokeStyle(lineWidth: kalin ? 3.5 : 2.5, lineCap: .round))
            } else {
                var ok = Path()
                ok.move(to: uc)
                ok.addLine(to: CGPoint(x: taban.x + dik.dx * 4.5, y: taban.y + dik.dy * 4.5))
                ok.addLine(to: CGPoint(x: taban.x - dik.dx * 4.5, y: taban.y - dik.dy * 4.5))
                ok.closeSubpath()
                ctx.fill(ok, with: .color(renk))
            }

            if b.tip == .uyarir && !kalin {
                // ok + "+" rozeti, okun hemen gerisinde
                let merkez = CGPoint(x: uc.x - yon.dx * 16, y: uc.y - yon.dy * 16)
                let daire = Path(ellipseIn: CGRect(x: merkez.x - 6.5, y: merkez.y - 6.5, width: 13, height: 13))
                ctx.fill(daire, with: .color(.white))
                ctx.stroke(daire, with: .color(RenkSeti.yesil.kenar), lineWidth: 1.5)
                ctx.draw(ctx.resolve(Text("+").font(.system(size: 11, weight: .heavy)).foregroundColor(RenkSeti.yesil.kenar)), at: merkez)
            }

            if !b.etiket.isEmpty && !kalin { etiketler.append((b.etiket, r.etiketNoktasi)) }
        }

        // Etiketler çizgilerin üstünde, beyaz hap içinde.
        for (metin, nokta) in etiketler {
            let t = ctx.resolve(Text(metin).font(.system(size: 10, weight: .semibold)).foregroundColor(Tema.ikincil))
            let s = t.measure(in: CGSize(width: 160, height: 40))
            let kutu = CGRect(x: nokta.x - s.width / 2 - 6, y: nokta.y - s.height / 2 - 2, width: s.width + 12, height: s.height + 4)
            let hap = Path(roundedRect: kutu, cornerRadius: kutu.height / 2)
            ctx.fill(hap, with: .color(.white))
            ctx.stroke(hap, with: .color(Tema.kartKenar), lineWidth: 1)
            ctx.draw(t, at: nokta)
        }
    }

    func dugumleriCiz(_ ctx: inout GraphicsContext, katman: Int) {
        let derinlik = derinlikler
        for d in yerlesikler where dugumKatmani(d, derinlik: derinlik) == katman {
            let yol = Path(roundedRect: cerceve(d), cornerRadius: kose(d), style: .continuous)
            ctx.fill(yol, with: .color(d.renk.zemin))
            ctx.stroke(yol, with: .color(d.renk.kenar), lineWidth: 1.5)
        }
    }

    /// TUS'un sevdiği düğüm: 3 px kenarlık.
    func tusCiz(_ ctx: inout GraphicsContext) {
        for d in yerlesikler where d.tus {
            ctx.stroke(Path(roundedRect: cerceve(d), cornerRadius: kose(d), style: .continuous),
                       with: .color(d.renk.kenar), lineWidth: 3)
        }
    }
}

/// Algoritma, yolak ve ağacın ortak tuvali.
struct IzgaraCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let stil: IzgaraStili
    let dokun: (String) -> Void

    var body: some View {
        let g = IzgaraGeometri(cizim: cizim, boyut: boyut, stil: stil)
        let derinlik = g.derinlikler

        ZStack(alignment: .topLeading) {
            if stil == .agac {
                // Ağaçta kenarlar düğümlerle birlikte belirir: 1 = kök + 1. seviye, 2 = alt seviyeler.
                Canvas { ctx, _ in g.baglantilariCiz(&ctx, katman: 1, vurgu: nil) }
                Canvas { ctx, _ in g.baglantilariCiz(&ctx, katman: 2, vurgu: nil) }
                    .katmanda(durum.katman >= 2)
            } else {
                Canvas { ctx, _ in g.baglantilariCiz(&ctx, katman: 2, vurgu: nil) }
                    .katmanda(durum.katman >= 2)
            }
            if !durum.kalinBaglantilar.isEmpty {
                Canvas { ctx, _ in g.baglantilariCiz(&ctx, katman: nil, vurgu: durum.kalinBaglantilar) }
                    .transition(.opacity)
            }
            Canvas { ctx, _ in g.dugumleriCiz(&ctx, katman: 1) }
            Canvas { ctx, _ in g.dugumleriCiz(&ctx, katman: 2) }
                .katmanda(durum.katman >= 2)
            Canvas { ctx, _ in g.tusCiz(&ctx) }
                .katmanda(durum.katman >= 3)

            ForEach(g.yerlesikler) { d in
                let f = g.cerceve(d)
                Button { dokun(d.id) } label: {
                    Text(d.etiket)
                        .font(Sigdir.font(d.etiket, temel: g.punto, genislik: f.width - 14, agirlik: .semibold))
                        .foregroundStyle(d.renk.yazi)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(width: f.width, height: f.height)
                        .overlay(alignment: .topLeading) {
                            if d.sekil == .karar { KararEtiketi(renk: d.renk).offset(x: 6, y: -6) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .katmanda(durum.katman >= g.dugumKatmani(d, derinlik: derinlik))
                .allowsHitTesting(durum.dokunulabilir)
                .position(x: f.midX, y: f.midY)
                .accessibilityLabel(d.etiket)
                .accessibilityValue(d.tus ? "TUS'un sevdiği düğüm" : "")
            }

            DugumUstKatmani(alanlar: g.yerlesikler.map { DugumAlani(id: $0.id, cerceve: g.cerceve($0), kose: g.kose($0)) },
                            durum: durum, boyut: boyut, dokun: dokun)
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.katman)
        .animation(.easeOut(duration: 0.25), value: durum.kalinBaglantilar)
    }
}

struct AlgoritmaCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        IzgaraCanvas(cizim: cizim, durum: durum, boyut: boyut, stil: .algoritma, dokun: dokun)
    }
}
