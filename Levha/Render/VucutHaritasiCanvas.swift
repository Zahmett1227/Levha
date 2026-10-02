import SwiftUI

/// Önden, cinsiyetsiz tek bir çocuk silüeti (100 × 200 birimlik kutuda tanımlı).
/// Her bölgenin sabit bir çapa noktası vardır; etiketler sağ/sol kenarda dikey dağıtılır.
/// Keşif katmanları: 1 silüet, 2 işaretler, 3 TUS, 4 notlar.
enum Siluet {
    static let en: CGFloat = 100
    static let boy: CGFloat = 200

    /// Silüet parçaları (aynı renkle doldurulur, kontur yok: birleşimler görünmez).
    static func parcalar(_ donustur: (CGPoint) -> CGPoint, olcek: CGFloat) -> [Path] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { donustur(CGPoint(x: x, y: y)) }
        func daire(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: p(x, y).x - r * olcek, y: p(x, y).y - r * olcek, width: 2 * r * olcek, height: 2 * r * olcek))
        }
        func elips(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            let m = p(x, y)
            return Path(ellipseIn: CGRect(x: m.x - w / 2 * olcek, y: m.y - h / 2 * olcek, width: w * olcek, height: h * olcek))
        }
        func uzuv(_ noktalar: [CGPoint], _ kalinlik: CGFloat) -> Path {
            var yol = Path()
            yol.addLines(noktalar.map { p($0.x, $0.y) })
            return yol.strokedPath(StrokeStyle(lineWidth: kalinlik * olcek, lineCap: .round, lineJoin: .round))
        }
        let govdeUst = p(30, 46), govdeAlt = p(70, 114)
        let govde = Path(roundedRect: CGRect(x: govdeUst.x, y: govdeUst.y, width: govdeAlt.x - govdeUst.x, height: govdeAlt.y - govdeUst.y),
                         cornerRadius: 12 * olcek, style: .continuous)
        return [
            daire(50, 22, 18),                                          // baş
            daire(31.5, 24, 4.5), daire(68.5, 24, 4.5),                 // kulaklar
            uzuv([CGPoint(x: 50, y: 36), CGPoint(x: 50, y: 50)], 12),   // boyun
            govde,
            uzuv([CGPoint(x: 33, y: 52), CGPoint(x: 21, y: 80), CGPoint(x: 15, y: 104)], 11),   // sol kol
            uzuv([CGPoint(x: 67, y: 52), CGPoint(x: 79, y: 80), CGPoint(x: 85, y: 104)], 11),   // sağ kol
            daire(14, 109, 6.5), daire(86, 109, 6.5),                   // eller
            uzuv([CGPoint(x: 41, y: 108), CGPoint(x: 40, y: 150), CGPoint(x: 39, y: 186)], 15), // sol bacak
            uzuv([CGPoint(x: 59, y: 108), CGPoint(x: 60, y: 150), CGPoint(x: 61, y: 186)], 15), // sağ bacak
            elips(36, 192, 18, 9), elips(64, 192, 18, 9),               // ayaklar
        ]
    }

    /// Bölge çapaları (silüet birimleri). Hasta önden bakar: karaciğer izleyenin solunda.
    static func capa(_ b: VucutBolgesi) -> CGPoint {
        switch b {
        case .bas: return CGPoint(x: 50, y: 8)
        case .goz: return CGPoint(x: 43, y: 20)
        case .kulak: return CGPoint(x: 31.5, y: 24)
        case .yuz: return CGPoint(x: 57, y: 25)
        case .agiz: return CGPoint(x: 50, y: 32)
        case .boyun: return CGPoint(x: 50, y: 43)
        case .gogus: return CGPoint(x: 39, y: 58)
        case .kalp: return CGPoint(x: 56, y: 62)
        case .omurga: return CGPoint(x: 50, y: 72)
        case .karaciger: return CGPoint(x: 40, y: 79)
        case .dalak: return CGPoint(x: 61, y: 79)
        case .karin: return CGPoint(x: 50, y: 90)
        case .bobrek: return CGPoint(x: 61, y: 94)
        case .genital: return CGPoint(x: 50, y: 110)
        case .kol: return CGPoint(x: 23, y: 74)
        case .deri: return CGPoint(x: 80, y: 86)
        case .el: return CGPoint(x: 14, y: 109)
        case .bacak: return CGPoint(x: 40, y: 140)
        case .eklem: return CGPoint(x: 60, y: 150)
        case .ayak: return CGPoint(x: 36, y: 192)
        }
    }
}

struct VucutGeometri {
    let cizim: LevhaCizim
    let boyut: CGSize
    let pad: CGFloat = 10
    let kose: CGFloat = 8
    let bosluk: CGFloat = 5

    let siluetKutusu: CGRect
    private(set) var etiketler: [String: CGRect] = [:]
    private(set) var capalar: [String: CGPoint] = [:]
    private(set) var sagda: Set<String> = []

    var olcek: CGFloat { siluetKutusu.width / Siluet.en }

    func donustur(_ p: CGPoint) -> CGPoint {
        CGPoint(x: siluetKutusu.minX + p.x * olcek, y: siluetKutusu.minY + p.y * olcek)
    }

    init(cizim: LevhaCizim, boyut: CGSize) {
        self.cizim = cizim
        self.boyut = boyut
        let h = boyut.height - pad * 2
        let w = min(h * Siluet.en / Siluet.boy, boyut.width * 0.34)
        let sh = w * Siluet.boy / Siluet.en
        siluetKutusu = CGRect(x: (boyut.width - w) / 2, y: (boyut.height - sh) / 2, width: w, height: sh)
        yerlestir()
    }

    /// Taraf: çapa ortanın solundaysa sol, sağındaysa sağ; orta hattakiler az dolu tarafa (eşitse sağa).
    /// Her tarafta sıra = `bolgeler` sırası; kutular çapa yüksekliğine yakın, üst üste binmeden dizilir.
    private mutating func yerlestir() {
        var sol: [(id: String, y: CGFloat)] = []
        var sag: [(id: String, y: CGFloat)] = []
        for d in cizim.dugumler {
            guard let b = d.bolge else { continue }
            let c = donustur(Siluet.capa(b))
            capalar[d.id] = c
            let goreli = Siluet.capa(b).x
            if goreli < 47 || (goreli <= 53 && sol.count < sag.count) {
                sol.append((d.id, c.y))
            } else {
                sag.append((d.id, c.y))
                sagda.insert(d.id)
            }
        }
        let kutuW = max(60, siluetKutusu.minX - pad - 14)
        let enFazla = max(sol.count, sag.count)
        let kutuH = min(40, max(24, (boyut.height - pad * 2 - CGFloat(max(0, enFazla - 1)) * bosluk) / CGFloat(max(1, enFazla))))
        for (taraf, x) in [(sol, pad), (sag, boyut.width - pad - kutuW)] {
            var ylar = taraf.map { $0.y - kutuH / 2 }
            // Aşağı doğru it, sonra taşanı yukarı geri it.
            for i in ylar.indices {
                ylar[i] = max(ylar[i], pad, i > 0 ? ylar[i - 1] + kutuH + bosluk : pad)
            }
            var alt = boyut.height - pad - kutuH
            for i in ylar.indices.reversed() {
                ylar[i] = min(ylar[i], alt)
                alt = ylar[i] - kutuH - bosluk
            }
            for (i, t) in taraf.enumerated() {
                etiketler[t.id] = CGRect(x: x, y: ylar[i], width: kutuW, height: kutuH)
            }
        }
    }

    func siluetCiz(_ ctx: inout GraphicsContext) {
        for parca in Siluet.parcalar(donustur, olcek: olcek) {
            ctx.fill(parca, with: .color(Color(hex: 0xE3E8EE)))
        }
    }

    /// Katman 2: çapa noktaları ve etikete giden ince çizgiler, etiket zeminleri.
    func isaretleriCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler {
            guard let c = capalar[d.id], let e = etiketler[d.id] else { continue }
            let kenar = sagda.contains(d.id) ? CGPoint(x: e.minX, y: e.midY) : CGPoint(x: e.maxX, y: e.midY)
            var cizgi = Path()
            cizgi.move(to: c)
            cizgi.addLine(to: kenar)
            ctx.stroke(cizgi, with: .color(d.renk.kenar.opacity(0.8)), lineWidth: 1)
        }
        for d in cizim.dugumler {
            guard let c = capalar[d.id] else { continue }
            let nokta = Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
            ctx.fill(nokta, with: .color(d.renk.kenar))
            ctx.stroke(nokta, with: .color(.white), lineWidth: 1.5)
        }
        for d in cizim.dugumler {
            guard let e = etiketler[d.id] else { continue }
            let yol = Path(roundedRect: e, cornerRadius: kose, style: .continuous)
            ctx.fill(yol, with: .color(d.renk.zemin))
            ctx.stroke(yol, with: .color(d.renk.kenar), lineWidth: 1.5)
        }
    }

    func tusCiz(_ ctx: inout GraphicsContext) {
        for d in cizim.dugumler where d.tus {
            guard let e = etiketler[d.id] else { continue }
            ctx.stroke(Path(roundedRect: e, cornerRadius: kose, style: .continuous), with: .color(d.renk.kenar), lineWidth: 3)
        }
    }
}

struct VucutHaritasiCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        let g = VucutGeometri(cizim: cizim, boyut: boyut)

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in g.siluetCiz(&ctx) }
            Canvas { ctx, _ in g.isaretleriCiz(&ctx) }
                .katmanda(durum.katman >= 2)
            Canvas { ctx, _ in g.tusCiz(&ctx) }
                .katmanda(durum.katman >= 3)

            ForEach(cizim.dugumler) { d in
                if let e = g.etiketler[d.id] {
                    Button { dokun(d.id) } label: {
                        Text(d.etiket)
                            .font(Sigdir.font(d.etiket, temel: 10.5, genislik: e.width - 10, agirlik: .semibold))
                            .foregroundStyle(d.renk.yazi)
                            .multilineTextAlignment(g.sagda.contains(d.id) ? .leading : .trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 5)
                            .frame(width: e.width, height: e.height, alignment: g.sagda.contains(d.id) ? .leading : .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .katmanda(durum.katman >= 2)
                    .allowsHitTesting(durum.dokunulabilir)
                    .position(x: e.midX, y: e.midY)
                    .accessibilityLabel(d.etiket)
                    .accessibilityValue(d.bolge?.ad ?? "")
                }
            }

            DugumUstKatmani(alanlar: cizim.dugumler.compactMap { d in g.etiketler[d.id].map { DugumAlani(id: d.id, cerceve: $0, kose: g.kose) } },
                            durum: durum, boyut: boyut, dokun: dokun)
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.katman)
    }
}
