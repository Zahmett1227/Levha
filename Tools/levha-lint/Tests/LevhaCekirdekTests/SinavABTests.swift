import XCTest
@testable import LevhaCekirdek

final class TahminPolitikasiTests: XCTestCase {
    func testNet() {
        XCTAssertEqual(TahminPolitikasi.net(dogru: 20, yanlis: 8, ceza: 0.25), 18)
        XCTAssertEqual(TahminPolitikasi.net(dogru: 5, yanlis: 0, ceza: 0.25), 5)
    }

    func testSansDuzeyindeTahminNetiDegistirmez() {
        // 1/4 cezada şans düzeyi (0,2) tahminin beklenen değeri tam 0'dır.
        let d = TahminPolitikasi.bosBeklenenDegisim(bosSayisi: 10, dogruluk: 0.2, ceza: 0.25)
        XCTAssertEqual(d.beklenen, 0, accuracy: 1e-12)
        XCTAssertEqual(d.ss, 1.25 * (10 * 0.2 * 0.8).squareRoot(), accuracy: 1e-12)
    }

    func testIyiTahminciKazanirKotuKaybeder() {
        let iyi = TahminPolitikasi.bosBeklenenDegisim(bosSayisi: 10, dogruluk: 0.5, ceza: 0.25)
        XCTAssertEqual(iyi.beklenen, 3.75, accuracy: 1e-12)
        XCTAssertEqual(iyi.ss, 1.25 * 2.5.squareRoot(), accuracy: 1e-12)
        XCTAssertLessThan(TahminPolitikasi.bosBeklenenDegisim(bosSayisi: 8, dogruluk: 0.1, ceza: 0.25).beklenen, 0)
        XCTAssertEqual(TahminPolitikasi.bosBeklenenDegisim(bosSayisi: 0, dogruluk: 0.9, ceza: 0.25).beklenen, 0)
    }

    func testDogrulukSansaBuzulur() {
        XCTAssertEqual(TahminPolitikasi.dogruluk(dogru: 0, toplam: 0), 0.2, accuracy: 1e-12)
        XCTAssertEqual(TahminPolitikasi.dogruluk(dogru: 3, toplam: 3), 4.0 / 8.0, accuracy: 1e-12)
        XCTAssertEqual(TahminPolitikasi.dogruluk(dogru: 60, toplam: 100), 61.0 / 105.0, accuracy: 1e-12)
    }
}

final class ABTestiTests: XCTestCase {
    func testIkiOranZ() throws {
        let k = try XCTUnwrap(ABTesti.ikiOran(d1: 60, n1: 100, d2: 45, n2: 100))
        XCTAssertEqual(k.fark, 0.15, accuracy: 1e-12)
        XCTAssertEqual(k.z, 2.1239, accuracy: 1e-3)
        XCTAssertEqual(k.pDegeri, 0.0337, accuracy: 1e-3)
        XCTAssertFalse(k.yetersiz)
    }

    func testEsitOranlarVeUcDurumlar() throws {
        let e = try XCTUnwrap(ABTesti.ikiOran(d1: 15, n1: 30, d2: 20, n2: 40))
        XCTAssertEqual(e.z, 0, accuracy: 1e-12)
        XCTAssertEqual(e.pDegeri, 1, accuracy: 1e-12)
        XCTAssertNil(ABTesti.ikiOran(d1: 0, n1: 0, d2: 3, n2: 10))
        let hepsi = try XCTUnwrap(ABTesti.ikiOran(d1: 10, n1: 10, d2: 12, n2: 12))
        XCTAssertEqual(hepsi.pDegeri, 1, "varyans 0 → fark yok sayılır")
        XCTAssertTrue(try XCTUnwrap(ABTesti.ikiOran(d1: 5, n1: 29, d2: 20, n2: 40)).yetersiz)
    }
}
