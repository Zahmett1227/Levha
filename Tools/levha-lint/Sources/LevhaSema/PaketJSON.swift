import Foundation

// Şema v3'ün Codable karşılığı (v1–v2 paketler de okunur). Alan adları JSON anahtarlarıyla birebir aynıdır.
// Bu dosya hem levha-lint'te hem de iOS uygulamasında derlenir.

public enum LevhaTipi: String, Codable, CaseIterable {
    case algoritma, matris, sayi_cetveli, zaman_cizelgesi, yolak, agac, vucut_haritasi

    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }

    public var ad: String {
        switch self {
        case .algoritma: return "Algoritma"
        case .matris: return "Matris"
        case .sayi_cetveli: return "Sayı cetveli"
        case .zaman_cizelgesi: return "Zaman çizelgesi"
        case .yolak: return "Yolak"
        case .agac: return "Ağaç"
        case .vucut_haritasi: return "Vücut haritası"
        }
    }

    /// Render motorunun çizebildiği tipler (Part 2'den itibaren hepsi).
    public var cizilebilir: Bool { true }

    /// Düğümleri [sütun, satır] ızgarasına yerleşen tipler; bunlarda düzen sabittir.
    public var izgaraTabanli: Bool { self == .algoritma || self == .yolak || self == .agac }
}

public enum DugumSekli: String, Codable, CaseIterable {
    case durum, karar, surec, madde
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }
}

public enum RenkAdi: String, Codable, CaseIterable {
    case kirmizi, mavi, yesil, sari, gri
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }
}

public enum BaglantiTipi: String, Codable, CaseIterable {
    /// ok
    case normal
    /// uçta ⊣ çubuğu
    case inhibe
    /// ok + "+" rozeti
    case uyarir
    /// kesikli çizgi + ok
    case olasi
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }
}

public enum SabotajTipi: String, Codable, CaseIterable {
    case etiket_takas, deger_kaydir, renk_degistir, baglanti_ters, hucre_takas, sira_boz, bolge_kaydir

    /// `hedef` dizisinde beklenen düğüm sayısı.
    public var hedefSayisi: Int {
        switch self {
        case .etiket_takas, .baglanti_ters, .hucre_takas, .sira_boz: return 2
        case .deger_kaydir, .renk_degistir, .bolge_kaydir: return 1
        }
    }

    public func uygun(_ tip: LevhaTipi) -> Bool {
        switch self {
        case .etiket_takas: return tip != .matris
        case .renk_degistir: return true
        case .baglanti_ters: return tip.izgaraTabanli
        case .hucre_takas: return tip == .matris
        case .deger_kaydir: return tip == .sayi_cetveli || tip == .zaman_cizelgesi
        case .sira_boz: return tip == .zaman_cizelgesi
        case .bolge_kaydir: return tip == .vucut_haritasi
        }
    }
}

/// Vücut haritasındaki sabit bölge listesi.
public enum VucutBolgesi: String, Codable, CaseIterable {
    case bas, yuz, goz, kulak, agiz, boyun, gogus, kalp, karin, karaciger, dalak, bobrek, genital, kol, el, bacak, ayak, deri, eklem, omurga
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }

    public var ad: String {
        switch self {
        case .bas: return "baş"
        case .yuz: return "yüz"
        case .goz: return "göz"
        case .kulak: return "kulak"
        case .agiz: return "ağız"
        case .boyun: return "boyun"
        case .gogus: return "göğüs"
        case .kalp: return "kalp"
        case .karin: return "karın"
        case .karaciger: return "karaciğer"
        case .dalak: return "dalak"
        case .bobrek: return "böbrek"
        case .genital: return "genital"
        case .kol: return "kol"
        case .el: return "el"
        case .bacak: return "bacak"
        case .ayak: return "ayak"
        case .deri: return "deri"
        case .eklem: return "eklem"
        case .omurga: return "omurga"
        }
    }
}

/// Soru kalıpları (sabit, 12).
public enum KalipTipi: String, Codable, CaseIterable {
    case en_sik, ilk_adim, en_olasi_tani, mekanizma, istisna, esik_sayi, ayirici_cift, kesin_tani, patognomonik, yas_sira, ilac, esleme
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }

    public var ad: String {
        switch self {
        case .en_sik: return "En sık"
        case .ilk_adim: return "İlk adım"
        case .en_olasi_tani: return "En olası tanı"
        case .mekanizma: return "Mekanizma"
        case .istisna: return "İstisna"
        case .esik_sayi: return "Eşik / sayı"
        case .ayirici_cift: return "Ayırıcı çift"
        case .kesin_tani: return "Kesin tanı"
        case .patognomonik: return "Patognomonik"
        case .yas_sira: return "Yaş / sıra"
        case .ilac: return "İlaç"
        case .esleme: return "Eşleme"
        }
    }
}

public enum ZamanBirimi: String, CaseIterable {
    case gun, hafta, ay, yil
    public var ad: String {
        switch self {
        case .gun: return "gün"
        case .hafta: return "hafta"
        case .ay: return "ay"
        case .yil: return "yıl"
        }
    }
}

func semaEnumCoz<T: RawRepresentable & CaseIterable>(_ decoder: Decoder) throws -> T where T.RawValue == String {
    let kap = try decoder.singleValueContainer()
    let metin = try kap.decode(String.self)
    if let deger = T(rawValue: metin) { return deger }
    let izinli = T.allCases.map { $0.rawValue }.joined(separator: ", ")
    throw DecodingError.dataCorruptedError(in: kap, debugDescription: "geçersiz değer \"\(metin)\" (izinli: \(izinli))")
}

public struct PaketJSON: Codable {
    public var sema_surumu: Int
    public var paket_id: String
    public var ders: String
    public var bolum: String
    public var alt_konu: String
    public var levhalar: [LevhaJSON]
    public var sorular: [SoruJSON]?
    // v3
    public var kazanimlar: [KazanimJSON]?
    public var aileler: [AileJSON]?
}

public struct KazanimJSON: Codable {
    public var id: String
    public var metin: String
    /// Ham metin: tanımsız kalıp lint'te hata olarak raporlanır, decode'u bozmaz.
    public var kalip: String
    public var dugumler: [String]?
    /// 1–5: TUS'ta sorulma olasılığı.
    public var sorulabilirlik: Int
    public var aile: String?
    public var anahtar_ipucu: String?
}

public struct AileJSON: Codable {
    public var id: String
    public var ad: String
    public var uyeler: [String]
    /// "Üye A|Üye B" → ayırıcı ipucu.
    public var ayirici: [String: String]?

    public func ayiriciIpucu(_ a: String, _ b: String) -> String? {
        ayirici?["\(a)|\(b)"] ?? ayirici?["\(b)|\(a)"]
    }
}

public struct KaynakJSON: Codable {
    public var kitap: String
    public var sayfa: [Int]?
}

public struct DuzenJSON: Codable {
    public var izgara: [Int]
    public var sabit: Bool?
}

public struct DugumJSON: Codable {
    public var id: String
    public var etiket: String
    public var sekil: DugumSekli?
    public var renk: RenkAdi?
    public var konum: [Int]?
    public var tus: Bool?
    public var not: String?
    /// ağaç: bağlantı verilmezse kenarlar bu alandan çizilir.
    public var ebeveyn: String?
}

public struct BaglantiJSON: Codable {
    public var from: String
    public var to: String
    public var etiket: String?
    public var tip: BaglantiTipi?
}

public struct HucreJSON: Codable {
    public var metin: String
    public var renk: RenkAdi?
    public var tus: Bool?
    public var not: String?
}

public struct EksenJSON: Codable {
    public var min: Double
    public var max: Double
    public var birim: String
}

public struct IsaretJSON: Codable {
    public var id: String
    /// Boş bırakılırsa işaret sabit bir sayıya bağlanmaz; "sabit sayı yok" şeridinde çizilir.
    public var deger: Double?
    public var etiket: String
    public var renk: RenkAdi?
    public var tus: Bool?
    public var not: String?
}

public struct SeritJSON: Codable {
    public var id: String
    public var ad: String
}

public struct OlayJSON: Codable {
    public var id: String
    public var serit: String
    public var bas: Double
    /// Doluysa aralık çubuğu, boşsa nokta işareti.
    public var bit: Double?
    public var etiket: String
    public var renk: RenkAdi?
    public var tus: Bool?
    public var not: String?
}

public struct BolgeJSON: Codable {
    public var id: String
    public var bolge: VucutBolgesi
    public var etiket: String
    public var renk: RenkAdi?
    public var tus: Bool?
    public var not: String?
}

/// Tipli sabotaj. Çözümleme gevşektir (v1 paketler bozulmasın); kuralları levha-lint denetler.
public struct SabotajJSON: Codable, Equatable {
    public var tip: String
    public var hedef: [String]?
    public var dogrusu: String?
    public var yanlis_deger: Double?
    public var yanlis_renk: String?
    public var yanlis_bolge: String?

    public init(tip: String, hedef: [String]?, dogrusu: String?, yanlis_deger: Double? = nil, yanlis_renk: String? = nil, yanlis_bolge: String? = nil) {
        self.tip = tip
        self.hedef = hedef
        self.dogrusu = dogrusu
        self.yanlis_deger = yanlis_deger
        self.yanlis_renk = yanlis_renk
        self.yanlis_bolge = yanlis_bolge
    }

    public var sabotajTipi: SabotajTipi? { SabotajTipi(rawValue: tip) }
}

public struct LevhaJSON: Codable {
    public var id: String
    public var tip: LevhaTipi
    public var baslik: String
    public var akilda_kalan: String
    public var duzen: DuzenJSON?
    public var dugumler: [DugumJSON]?
    public var baglantilar: [BaglantiJSON]?
    public var ortme_sirasi: [String]?
    public var sabotajlar: [SabotajJSON]?
    // matris
    public var satirlar: [String]?
    public var sutunlar: [String]?
    public var hucreler: [[HucreJSON]]?
    // sayi_cetveli, zaman_cizelgesi
    public var eksen: EksenJSON?
    public var isaretler: [IsaretJSON]?
    // zaman_cizelgesi
    public var seritler: [SeritJSON]?
    public var olaylar: [OlayJSON]?
    // vucut_haritasi
    public var bolgeler: [BolgeJSON]?
    // v3
    public var insa_sirasi: [String]?
    public var kaynak: KaynakJSON?
}

public struct SoruJSON: Codable {
    public var id: String
    public var levha: String
    public var dugumler: [String]?
    public var kok: String
    public var secenekler: [String]
    public var dogru: Int
    public var aciklama: String
    public var aciklama_yolu: [String]?
    public var celdirici_dugum: [String: String]?
    // v3
    public var kazanim: String?
    public var kalip: String?
    /// 1–3
    public var zorluk: Int?
    /// Şık indeksi → aile üyesi (doğru şık dahil).
    public var secenek_aile: [String: String]?
}

/// Levhaların ham hâlini saklamak için.
public struct HamPaketJSON: Codable {
    public var levhalar: [JSONDeger]
}

public enum JSONDeger: Codable, Equatable {
    case yok
    case mantiksal(Bool)
    case sayi(Double)
    case metin(String)
    case dizi([JSONDeger])
    case nesne([String: JSONDeger])

    public init(from decoder: Decoder) throws {
        let kap = try decoder.singleValueContainer()
        if kap.decodeNil() { self = .yok }
        else if let b = try? kap.decode(Bool.self) { self = .mantiksal(b) }
        else if let n = try? kap.decode(Double.self) { self = .sayi(n) }
        else if let s = try? kap.decode(String.self) { self = .metin(s) }
        else if let a = try? kap.decode([JSONDeger].self) { self = .dizi(a) }
        else { self = .nesne(try kap.decode([String: JSONDeger].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var kap = encoder.singleValueContainer()
        switch self {
        case .yok: try kap.encodeNil()
        case .mantiksal(let b): try kap.encode(b)
        case .sayi(let n): try kap.encode(n)
        case .metin(let s): try kap.encode(s)
        case .dizi(let a): try kap.encode(a)
        case .nesne(let o): try kap.encode(o)
        }
    }
}
