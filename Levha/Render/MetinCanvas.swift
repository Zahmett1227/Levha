import SwiftUI

/// A/B deneyinin "metin" grubu: levha düz metin olarak; tek sütun "etiket — not" satırları, bağlantılar
/// "A → B" satırları. Renk ve konum yok. Keşif iki katmandır (başlıklar / notlar); Örtme'de etiket boşluk olur (cloze).
struct MetinCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    struct Satir: Identifiable {
        let id: String
        /// Satır başı bağlam: matriste "satır · sütun", cetvelde değer, zaman çizelgesinde zaman, haritada bölge.
        let on: String?
        let etiket: String
        let not: String
        /// Matriste satır başlığı (grup ilk satırında).
        let grup: String?
    }

    private var notlarAcik: Bool { durum.katman >= 2 }

    private var satirlar: [Satir] {
        let birim = ZamanBirimi(rawValue: cizim.birim)?.ad ?? cizim.birim
        let seritAdi = Dictionary(cizim.seritler.map { ($0.id, $0.ad) }, uniquingKeysWith: { a, _ in a })
        var sonGrup: String?
        return cizim.dugumler.map { d in
            switch cizim.tip {
            case .matris:
                let r = d.satir, c = d.sutun
                let satirAdi = cizim.satirlar.indices.contains(r) ? cizim.satirlar[r] : ""
                let grup = satirAdi != sonGrup ? satirAdi : nil
                sonGrup = satirAdi
                return Satir(id: d.id, on: cizim.sutunlar.indices.contains(c) ? cizim.sutunlar[c] : nil,
                             etiket: d.etiket, not: d.not, grup: grup)
            case .sayi_cetveli:
                return Satir(id: d.id, on: d.deger.map { "\(Bicim.sayi($0)) \(cizim.birim)" } ?? "sabit değil",
                             etiket: d.etiket, not: d.not, grup: nil)
            case .zaman_cizelgesi:
                let zaman = d.bit.map { "\(Bicim.sayi(d.deger ?? 0))–\(Bicim.sayi($0)) \(birim)" } ?? "\(Bicim.sayi(d.deger ?? 0)). \(birim)"
                let serit = d.serit.flatMap { seritAdi[$0] }
                return Satir(id: d.id, on: [serit, zaman].compactMap { $0 }.joined(separator: " · "), etiket: d.etiket, not: d.not, grup: nil)
            case .vucut_haritasi:
                return Satir(id: d.id, on: d.bolge?.ad, etiket: d.etiket, not: d.not, grup: nil)
            default:
                return Satir(id: d.id, on: nil, etiket: d.etiket, not: d.not, grup: nil)
            }
        }
    }

    var body: some View {
        let etiket = Dictionary(cizim.dugumler.map { ($0.id, $0.etiket) }, uniquingKeysWith: { a, _ in a })
        ScrollViewReader { vekil in
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(satirlar) { s in
                    if let g = s.grup, !g.isEmpty {
                        Text(g)
                            .font(.system(size: 13.5, weight: .heavy))
                            .foregroundStyle(Tema.metin)
                            .padding(.top, 4)
                    }
                    satir(s).id(s.id)
                }
                if notlarAcik && !cizim.baglantilar.isEmpty {
                    Text("BAĞLANTILAR")
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(Tema.ikincil)
                        .padding(.top, 6)
                    ForEach(cizim.baglantilar) { b in
                        let kalin = durum.kalinBaglantilar.contains(b.anahtar)
                        Text(baglantiMetni(b, etiket))
                            .font(.system(size: 12.5, weight: kalin ? .bold : .regular))
                            .foregroundStyle(Tema.metin)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        // Açılışta vurgulu (Levhada göster, anlatım referansı) düğüm görünür alana gelir.
        .onAppear {
            guard let hedef = durum.halkalar.keys.sorted().first ?? durum.secili else { return }
            DispatchQueue.main.async { vekil.scrollTo(hedef, anchor: .center) }
        }
        }
        .frame(width: boyut.width, height: boyut.height)
        .animation(.easeOut(duration: 0.25), value: durum.gizli)
        .animation(.easeOut(duration: 0.25), value: durum.halkalar)
    }

    private func baglantiMetni(_ b: CizimBaglantisi, _ etiket: [String: String]) -> String {
        let ok: String
        switch b.tip {
        case .normal: ok = "→"
        case .inhibe: ok = "⊣"
        case .uyarir: ok = "→ (+)"
        case .olasi: ok = "⇢"
        }
        let a = durum.gizli.contains(b.from) ? "____" : (etiket[b.from] ?? b.from)
        let c = durum.gizli.contains(b.to) ? "____" : (etiket[b.to] ?? b.to)
        return "\(a) \(ok) \(c)" + (b.etiket.isEmpty ? "" : " (\(b.etiket))")
    }

    @ViewBuilder
    private func satir(_ s: Satir) -> some View {
        let gizli = durum.gizli.contains(s.id)
        let halka = durum.halkalar[s.id] ?? (durum.secili == s.id ? .koyu : nil)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let on = s.on, !on.isEmpty {
                    Text(on + ":")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.ikincil)
                }
                if gizli {
                    Button { dokun(s.id) } label: {
                        Text(String(repeating: "_", count: max(6, min(16, s.etiket.count))))
                            .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(durum.hataliMaske == s.id ? RenkSeti.kirmizi.yazi : Tema.cizgi)
                            .padding(.horizontal, 4)
                            .background(Tema.maskeZemin, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gizli etiket")
                    .accessibilityHint("Açmak için dokun")
                } else {
                    Text(s.etiket)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                }
            }
            if notlarAcik && !s.not.isEmpty {
                Text(s.not)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tema.ikincil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if let halka {
                RoundedRectangle(cornerRadius: 6).stroke(halka.renk, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if durum.dokunulabilir || gizli { dokun(s.id) } }
    }
}
