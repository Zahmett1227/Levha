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
}

enum HalkaTuru: Equatable {
    case koyu, sari, yesil

    var renk: Color {
        switch self {
        case .koyu: return Tema.metin
        case .sari: return RenkSeti.sari.kenar
        case .yesil: return RenkSeti.yesil.kenar
        }
    }
}

/// Levhanın o anki görünüm durumu: hangi katman, ne seçili, ne gizli, ne vurgulu.
struct LevhaGorunumDurumu: Equatable {
    var mod: LevhaModu = .kesif
    var katman: Int = 1
    var secili: String?
    var gizli: Set<String> = []
    /// Ek halkalar (Levhada göster, Sabotaj).
    var halkalar: [String: HalkaTuru] = [:]
    /// Kalın çizilecek bağlantılar: "from>to".
    var kalinBaglantilar: Set<String> = []
    /// Düğüm butonları dokunuş alır mı (Keşif'te katman 4, Sabotaj'da arama sürerken).
    var dokunulabilir: Bool = false

    static let katmanSayisi = 4
}

// MARK: - Çizim modeli (SwiftData'dan bir kez okunur, sonra değer tipi olarak dolaşır)

struct CizimDugumu: Identifiable, Equatable {
    let id: String
    var etiket: String
    var not: String
    var sekil: DugumSekli
    var renkAdi: String
    var konum: [Int]
    var tus: Bool
    /// Cetvel değeri / zaman olayının başlangıcı.
    var deger: Double?
    var bit: Double?
    var serit: String?
    var bolge: VucutBolgesi?

    var renk: RenkSeti { RenkSeti.ad(renkAdi) }
    var sutun: Int { konum.count == 2 ? konum[0] : 0 }
    var satir: Int { konum.count == 2 ? konum[1] : 0 }
}

struct CizimBaglantisi: Identifiable, Equatable {
    let id: Int
    var from: String
    var to: String
    var etiket: String
    var tip: BaglantiTipi

    var anahtar: String { "\(from)>\(to)" }
}

struct LevhaCizim: Equatable {
    let levhaId: String
    let tip: LevhaTipi?
    var sutun: Int
    var satir: Int
    var dugumler: [CizimDugumu]
    var baglantilar: [CizimBaglantisi]
    var satirlar: [String]
    var sutunlar: [String]
    var eksenMin: Double
    var eksenMax: Double
    var birim: String
    var seritler: [(id: String, ad: String)]

    init(_ l: Levha) {
        levhaId = l.id
        tip = l.levhaTipi
        sutun = max(1, l.izgara.first ?? 1)
        satir = max(1, l.izgara.count > 1 ? l.izgara[1] : 1)
        dugumler = l.siraliDugumler.map {
            CizimDugumu(id: $0.id, etiket: $0.etiket, not: $0.not, sekil: DugumSekli(rawValue: $0.sekil) ?? .durum,
                        renkAdi: $0.renk, konum: $0.konum, tus: $0.tus, deger: $0.deger, bit: $0.bit,
                        serit: $0.serit, bolge: $0.bolge.flatMap(VucutBolgesi.init(rawValue:)))
        }
        baglantilar = l.siraliBaglantilar.enumerated().map {
            CizimBaglantisi(id: $0.offset, from: $0.element.from, to: $0.element.to, etiket: $0.element.etiket,
                            tip: $0.element.tip.flatMap(BaglantiTipi.init(rawValue:)) ?? .normal)
        }
        satirlar = l.satirlar
        sutunlar = l.sutunlar
        eksenMin = l.eksenMin
        eksenMax = l.eksenMax
        birim = l.eksenBirim
        seritler = zip(l.seritIdleri ?? [], l.seritAdlari ?? []).map { (id: $0, ad: $1) }
    }

    static func == (a: LevhaCizim, b: LevhaCizim) -> Bool {
        a.levhaId == b.levhaId && a.dugumler == b.dugumler && a.baglantilar == b.baglantilar
            && a.eksenMin == b.eksenMin && a.eksenMax == b.eksenMax
    }

    func dugum(_ id: String) -> CizimDugumu? { dugumler.first { $0.id == id } }
    func indeks(_ id: String) -> Int? { dugumler.firstIndex { $0.id == id } }
}

// MARK: - Giriş noktası

struct LevhaView: View {
    let levha: Levha
    let mode: LevhaGorunumDurumu
    /// Sabotaj gibi durumlarda levhanın değiştirilmiş hâli.
    var cizim: LevhaCizim?
    var dokun: (String) -> Void = { _ in }

    var body: some View {
        let cizim = self.cizim ?? LevhaCizim(levha)
        GeometryReader { geo in
            switch cizim.tip {
            case .algoritma:
                AlgoritmaCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .yolak:
                YolakCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .agac:
                AgacCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .matris:
                MatrisCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .sayi_cetveli:
                SayiCetveliCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .zaman_cizelgesi:
                ZamanCizelgesiCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .vucut_haritasi:
                VucutHaritasiCanvas(cizim: cizim, durum: mode, boyut: geo.size, dokun: dokun)
            case .none:
                ContentUnavailableView("Bilinmeyen levha tipi", systemImage: "questionmark.square.dashed",
                                       description: Text(levha.tip))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Ortak üst katman: örtme maskeleri ve halkalar

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

    private var halkalar: [(alan: DugumAlani, tur: HalkaTuru)] {
        var sonuc: [(DugumAlani, HalkaTuru)] = []
        for a in alanlar {
            if let t = durum.halkalar[a.id] { sonuc.append((a, t)) }
            else if durum.secili == a.id { sonuc.append((a, .koyu)) }
        }
        return sonuc
    }

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
            ForEach(halkalar, id: \.alan.id) { h in
                RoundedRectangle(cornerRadius: h.alan.kose + 4, style: .continuous)
                    .stroke(h.tur.renk, lineWidth: 3)
                    .frame(width: h.alan.cerceve.width + 8, height: h.alan.cerceve.height + 8)
                    .position(x: h.alan.cerceve.midX, y: h.alan.cerceve.midY)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
            }
        }
        .frame(width: boyut.width, height: boyut.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: durum.gizli)
        .animation(.easeOut(duration: 0.25), value: durum.secili)
        .animation(.easeOut(duration: 0.25), value: durum.halkalar)
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
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.cizgi)
                    .minimumScaleFactor(0.5)
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

/// Eksen tik aralığı: zaman birimlerinde takvime uygun adımlar.
enum EksenAdimi {
    static func hesapla(aralik: Double, birim: String) -> Double {
        let adaylar: [Double]
        switch ZamanBirimi(rawValue: birim) {
        case .ay: adaylar = [1, 2, 3, 6, 12, 24]
        case .gun: adaylar = [1, 2, 3, 7, 14, 30, 60, 90, 180, 365]
        case .hafta: adaylar = [1, 2, 4, 8, 13, 26, 52]
        case .yil: adaylar = [1, 2, 5, 10, 20]
        case .none: adaylar = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000]
        }
        return adaylar.first { aralik / $0 <= 8 } ?? aralik / 5
    }

    static func cizgiler(min: Double, max: Double, birim: String) -> [Double] {
        let adim = hesapla(aralik: max - min, birim: birim)
        var sonuc: [Double] = []
        var v = (min / adim).rounded(.up) * adim
        while v <= max + adim * 0.001 {
            sonuc.append(v)
            v += adim
        }
        return sonuc
    }
}
