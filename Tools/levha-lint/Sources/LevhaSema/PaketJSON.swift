import Foundation

// Şema v1'in Codable karşılığı. Alan adları JSON anahtarlarıyla birebir aynıdır.
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

    /// Part 1'de render motorunun çizebildiği tipler.
    public var cizilebilir: Bool { self == .algoritma || self == .matris || self == .sayi_cetveli }
}

public enum DugumSekli: String, Codable, CaseIterable {
    case durum, karar, surec
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }
}

public enum RenkAdi: String, Codable, CaseIterable {
    case kirmizi, mavi, yesil, sari, gri
    public init(from decoder: Decoder) throws { self = try semaEnumCoz(decoder) }
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
}

public struct BaglantiJSON: Codable {
    public var from: String
    public var to: String
    public var etiket: String?
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
    /// Boş bırakılırsa işaret sabit bir sayıya bağlanmaz; "nomograma bağlı" şeridinde çizilir.
    public var deger: Double?
    public var etiket: String
    public var renk: RenkAdi?
    public var tus: Bool?
    public var not: String?
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
    public var sabotajlar: [JSONDeger]?
    // matris
    public var satirlar: [String]?
    public var sutunlar: [String]?
    public var hucreler: [[HucreJSON]]?
    // sayi_cetveli
    public var eksen: EksenJSON?
    public var isaretler: [IsaretJSON]?
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
}

/// Levhaların ham hâlini (Part 2+ tiplerinin bilinmeyen alanları dahil) saklamak için.
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

    public subscript(anahtar: String) -> JSONDeger? {
        if case .nesne(let o) = self { return o[anahtar] }
        return nil
    }

    public var metinDegeri: String? {
        if case .metin(let s) = self { return s }
        return nil
    }

    public var diziDegeri: [JSONDeger]? {
        if case .dizi(let a) = self { return a }
        return nil
    }
}
