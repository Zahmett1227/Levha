import SwiftUI

enum LevhaModu: String, CaseIterable, Identifiable {
    case kesif, ortme, sabotaj
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .kesif: return "Keşif"
        case .ortme: return "Örtme"
        case .sabotaj: return "Sabotaj"
        }
    }

    /// Sabotaj Part 2'de açılır.
    var aktif: Bool { self != .sabotaj }
}

/// Levhanın o anki görünüm durumu: hangi mod, hangi katman, ne seçili, ne gizli.
struct LevhaGorunumDurumu: Equatable {
    var mod: LevhaModu = .kesif
    var katman: Int = 1
    var secili: String?
    var gizli: Set<String> = []

    static let katmanSayisi = 4
    var dugumlerDokunulabilir: Bool { mod == .kesif && katman >= Self.katmanSayisi }
}

// MARK: - Çizim modeli (SwiftData'dan bir kez okunur, sonra değer tipi olarak dolaşır)

struct CizimDugumu: Identifiable {
    let id: String
    let etiket: String
    let not: String
    let sekil: DugumSekli
    let renk: RenkSeti
    let konum: [Int]
    let tus: Bool
    let deger: Double?

    var sutun: Int { konum.count == 2 ? konum[0] : 0 }
    var satir: Int { konum.count == 2 ? konum[1] : 0 }
}

struct CizimBaglantisi: Identifiable {
    let id: Int
    let from: String
    let to: String
    let etiket: String
}

struct LevhaCizim {
    let tip: LevhaTipi?
    let sutun: Int
    let satir: Int
    let dugumler: [CizimDugumu]
    let baglantilar: [CizimBaglantisi]
    let satirlar: [String]
    let sutunlar: [String]
    let eksenMin: Double
    let eksenMax: Double
    let birim: String
    private let indeks: [String: Int]

    init(_ l: Levha) {
        tip = l.levhaTipi
        sutun = max(1, l.izgara.first ?? 1)
        satir = max(1, l.izgara.count > 1 ? l.izgara[1] : 1)
        dugumler = l.siraliDugumler.map {
            CizimDugumu(id: $0.id, etiket: $0.etiket, not: $0.not, sekil: DugumSekli(rawValue: $0.sekil) ?? .durum,
                        renk: RenkSeti.ad($0.renk), konum: $0.konum, tus: $0.tus, deger: $0.deger)
        }
        baglantilar = l.siraliBaglantilar.enumerated().map {
            CizimBaglantisi(id: $0.offset, from: $0.element.from, to: $0.element.to, etiket: $0.element.etiket)
        }
        satirlar = l.satirlar
        sutunlar = l.sutunlar
        eksenMin = l.eksenMin
        eksenMax = l.eksenMax
        birim = l.eksenBirim
        indeks = Dictionary(dugumler.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
    }

    func dugum(_ id: String) -> CizimDugumu? { indeks[id].map { dugumler[$0] } }
}

// MARK: - Giriş noktası

struct LevhaView: View {
    let levha: Levha
    let mode: LevhaGorunumDurumu
    var dokun: (String) -> Void = { _ in }

    var body: some View {
        let cizim = LevhaCizim(levha)
        GeometryReader { geo in
            switch cizim.tip {
            case .algoritma:
                AlgoritmaCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .matris:
                MatrisCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .sayi_cetveli:
                SayiCetveliCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            default:
                ContentUnavailableView {
                    Label("Bu tip Part 2'de", systemImage: "hammer")
                } description: {
                    Text("\(levha.tipAdi) levhası içe aktarıldı; çizimi Part 2'de gelecek.")
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Ortak üst katman: örtme maskeleri ve seçim halkası

struct DugumAlani: Identifiable {
    let id: String
    let cerceve: CGRect
    let kose: CGFloat
}

struct DugumUstKatmani: View {
    let alanlar: [DugumAlani]
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(alanlar.filter { durum.gizli.contains($0.id) }) { a in
                Button { dokun(a.id) } label: {
                    OrtmeMaskesi(kose: a.kose)
                }
                .buttonStyle(.plain)
                .frame(width: a.cerceve.width + 4, height: a.cerceve.height + 4)
                .position(x: a.cerceve.midX, y: a.cerceve.midY)
                .transition(.opacity.combined(with: .scale(scale: 1.06)))
                .accessibilityLabel("Gizli düğüm")
                .accessibilityHint("Açmak için dokun")
            }
            if let s = durum.secili, let a = alanlar.first(where: { $0.id == s }) {
                RoundedRectangle(cornerRadius: a.kose + 4, style: .continuous)
                    .stroke(Tema.metin, lineWidth: 3)
                    .frame(width: a.cerceve.width + 8, height: a.cerceve.height + 8)
                    .position(x: a.cerceve.midX, y: a.cerceve.midY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.gizli)
        .animation(.easeOut(duration: 0.25), value: durum.secili)
    }
}

struct OrtmeMaskesi: View {
    let kose: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: kose, style: .continuous)
            .fill(Tema.maskeZemin)
            .overlay(
                RoundedRectangle(cornerRadius: kose, style: .continuous)
                    .strokeBorder(Tema.cizgi, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .overlay(
                Text("?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.cizgi)
            )
            .contentShape(Rectangle())
    }
}

/// Karar düğümlerinin üst kenarına oturan küçük etiket.
struct KararEtiketi: View {
    let renk: RenkSeti

    var body: some View {
        Text("KARAR")
            .font(.system(size: 7.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(renk.yazi)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(renk.kenar, lineWidth: 1))
            .fixedSize()
    }
}

extension View {
    /// Katman göstergesi: görünmezken de yer kaplar, böylece düzen hiç oynamaz.
    func katmanda(_ gorunur: Bool) -> some View { opacity(gorunur ? 1 : 0) }
}
