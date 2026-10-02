import Foundation
import Compression

/// En küçük zip okuyucu/yazıcı (DEFLATE ya da saklama; tek disk; zip64 yok). Yedek dosyası için yeterli.
enum ZipArsiv {
    struct Giris {
        let ad: String
        let veri: Data
    }

    enum Hata: LocalizedError {
        case bozuk(String)
        var errorDescription: String? {
            if case .bozuk(let m) = self { return "Yedek dosyası okunamadı: \(m)" }
            return nil
        }
    }

    // MARK: - Yazma

    static func yaz(_ girisler: [Giris]) -> Data {
        var cikti = Data()
        var merkez = Data()
        for g in girisler {
            let ad = Data(g.ad.utf8)
            let crc = crc32(g.veri)
            let sikisik = sikistir(g.veri)
            let (yontem, govde): (UInt16, Data) = sikisik.map { $0.count < g.veri.count ? (8, $0) : (0, g.veri) } ?? (0, g.veri)
            let ofset = UInt32(cikti.count)
            // Yerel başlık
            cikti.le32(0x04034b50); cikti.le16(20); cikti.le16(0x0800); cikti.le16(yontem)
            cikti.le16(0); cikti.le16(0x21)                   // saat, tarih (1980-01-01)
            cikti.le32(crc); cikti.le32(UInt32(govde.count)); cikti.le32(UInt32(g.veri.count))
            cikti.le16(UInt16(ad.count)); cikti.le16(0)
            cikti.append(ad)
            cikti.append(govde)
            // Merkez dizin kaydı
            merkez.le32(0x02014b50); merkez.le16(20); merkez.le16(20); merkez.le16(0x0800); merkez.le16(yontem)
            merkez.le16(0); merkez.le16(0x21)
            merkez.le32(crc); merkez.le32(UInt32(govde.count)); merkez.le32(UInt32(g.veri.count))
            merkez.le16(UInt16(ad.count)); merkez.le16(0); merkez.le16(0); merkez.le16(0); merkez.le16(0)
            merkez.le32(0); merkez.le32(ofset)
            merkez.append(ad)
        }
        let merkezOfset = UInt32(cikti.count)
        cikti.append(merkez)
        cikti.le32(0x06054b50); cikti.le16(0); cikti.le16(0)
        cikti.le16(UInt16(girisler.count)); cikti.le16(UInt16(girisler.count))
        cikti.le32(UInt32(merkez.count)); cikti.le32(merkezOfset); cikti.le16(0)
        return cikti
    }

    // MARK: - Okuma

    static func oku(_ veri: Data) throws -> [Giris] {
        let b = [UInt8](veri)
        guard b.count >= 22 else { throw Hata.bozuk("çok kısa") }
        var son = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65_557) {
            if b.u32(i) == 0x06054b50 { son = i; break }
            i -= 1
        }
        guard son >= 0 else { throw Hata.bozuk("zip dizini yok") }
        let adet = Int(b.u16(son + 10))
        var p = Int(b.u32(son + 16))
        var sonuc: [Giris] = []
        for _ in 0..<adet {
            guard p + 46 <= b.count, b.u32(p) == 0x02014b50 else { throw Hata.bozuk("merkez dizin") }
            let yontem = b.u16(p + 10)
            let crc = b.u32(p + 16)
            let sikisik = Int(b.u32(p + 20)), acik = Int(b.u32(p + 24))
            let adU = Int(b.u16(p + 28)), ekU = Int(b.u16(p + 30)), yorumU = Int(b.u16(p + 32))
            let yerel = Int(b.u32(p + 42))
            let ad = String(decoding: b[(p + 46)..<(p + 46 + adU)], as: UTF8.self)
            p += 46 + adU + ekU + yorumU
            guard yerel + 30 <= b.count, b.u32(yerel) == 0x04034b50 else { throw Hata.bozuk("yerel başlık") }
            let bas = yerel + 30 + Int(b.u16(yerel + 26)) + Int(b.u16(yerel + 28))
            guard bas + sikisik <= b.count else { throw Hata.bozuk("kısa veri") }
            let govde = Data(b[bas..<(bas + sikisik)])
            let icerik: Data
            switch yontem {
            case 0: icerik = govde
            case 8: icerik = try ac(govde, boyut: acik)
            default: throw Hata.bozuk("desteklenmeyen sıkıştırma \(yontem)")
            }
            guard crc32(icerik) == crc else { throw Hata.bozuk("CRC uyuşmuyor (\(ad))") }
            sonuc.append(Giris(ad: ad, veri: icerik))
        }
        return sonuc
    }

    // MARK: - DEFLATE (Compression: COMPRESSION_ZLIB = başlıksız ham DEFLATE)

    private static func sikistir(_ veri: Data) -> Data? {
        guard !veri.isEmpty else { return nil }
        let kapasite = veri.count + 1024
        var hedef = [UInt8](repeating: 0, count: kapasite)
        let n = veri.withUnsafeBytes { kaynak in
            compression_encode_buffer(&hedef, kapasite, kaynak.bindMemory(to: UInt8.self).baseAddress!, veri.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(hedef[0..<n]) : nil
    }

    private static func ac(_ veri: Data, boyut: Int) throws -> Data {
        guard boyut > 0 else { return Data() }
        var hedef = [UInt8](repeating: 0, count: boyut)
        let n = veri.withUnsafeBytes { kaynak in
            compression_decode_buffer(&hedef, boyut, kaynak.bindMemory(to: UInt8.self).baseAddress!, veri.count, nil, COMPRESSION_ZLIB)
        }
        guard n == boyut else { throw Hata.bozuk("açılamadı") }
        return Data(hedef)
    }

    // MARK: - CRC32

    private static let tablo: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ veri: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in veri { c = tablo[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}

private extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24 }
}
