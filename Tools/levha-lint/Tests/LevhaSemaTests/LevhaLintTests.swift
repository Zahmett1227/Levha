import XCTest
@testable import LevhaSema

final class LevhaLintTests: XCTestCase {
    private func ornekVeri() throws -> Data {
        let kok = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: kok.appendingPathComponent("SamplePackages/ped.neo.sarilik.json"))
    }

    /// Örnek paketi JSON nesnesi olarak açıp değiştirir, sonra lint'ten geçirir.
    private func bozulmus(_ degistir: (inout [String: Any]) -> Void) throws -> [LintBulgusu] {
        var kok = try JSONSerialization.jsonObject(with: ornekVeri()) as! [String: Any]
        degistir(&kok)
        return LevhaLint.denetle(veri: try JSONSerialization.data(withJSONObject: kok)).bulgular
    }

    private func levha(_ kok: inout [String: Any], _ i: Int, _ degistir: (inout [String: Any]) -> Void) {
        var levhalar = kok["levhalar"] as! [[String: Any]]
        degistir(&levhalar[i])
        kok["levhalar"] = levhalar
    }

    func testOrnekPaketTemiz() throws {
        let sonuc = LevhaLint.denetle(veri: try ornekVeri())
        XCTAssertNotNil(sonuc.paket)
        XCTAssertEqual(sonuc.bulgular, [])
    }

    func testIzgaraDisiVeCakisanKonum() throws {
        let b = try bozulmus { kok in
            levha(&kok, 0) { l in
                var d = l["dugumler"] as! [[String: Any]]
                d[0]["konum"] = [5, 0]
                d[1]["konum"] = [1, 1]   // n3 ile çakışır
                l["dugumler"] = d
            }
        }
        XCTAssertTrue(b.contains { $0.mesaj.contains("ızgaranın") })
        XCTAssertTrue(b.contains { $0.mesaj.contains("çakışıyor") })
    }

    func testGecersizBaglantiVeSoruReferansi() throws {
        let b = try bozulmus { kok in
            levha(&kok, 0) { l in
                var bag = l["baglantilar"] as! [[String: Any]]
                bag[0]["to"] = "n99"
                l["baglantilar"] = bag
            }
            var sorular = kok["sorular"] as! [[String: Any]]
            sorular[0]["dugumler"] = ["yok"]
            sorular[0]["dogru"] = 7
            sorular[0]["secenekler"] = ["a", "b"]
            kok["sorular"] = sorular
        }
        XCTAssertTrue(b.contains { $0.mesaj.contains("n99") && $0.engelleyici })
        XCTAssertTrue(b.contains { $0.mesaj.contains("\"yok\"") })
        XCTAssertTrue(b.contains { $0.yer.hasSuffix("dogru") })
        XCTAssertTrue(b.contains { $0.mesaj.contains("5 seçenek") })
    }

    func testUzunEtiketVeDugumSayisi() throws {
        let b = try bozulmus { kok in
            levha(&kok, 0) { l in
                var d = l["dugumler"] as! [[String: Any]]
                d[0]["etiket"] = String(repeating: "x", count: 29)
                l["dugumler"] = Array(d.prefix(5))
                l["baglantilar"] = []
                l["ortme_sirasi"] = ["n1", "n2", "n3"]
            }
            kok["sorular"] = []
        }
        XCTAssertTrue(b.contains { $0.mesaj.contains("29 karakter") && !$0.engelleyici })
        XCTAssertTrue(b.contains { $0.mesaj.contains("düğüm sayısı 6–20") })
    }

    func testMatrisBoyutUyumsuzlugu() throws {
        let b = try bozulmus { kok in
            levha(&kok, 1) { l in
                var h = l["hucreler"] as! [[Any]]
                h[2].removeLast()
                l["hucreler"] = h
                l["ortme_sirasi"] = ["r0c0", "r0c1", "r0c2"]
            }
            kok["sorular"] = []
        }
        XCTAssertTrue(b.contains { $0.yer.contains("hucreler[2]") && $0.engelleyici })
    }

    func testDecodeHatasiYeriniGosterir() throws {
        let b = try bozulmus { kok in
            levha(&kok, 1) { l in
                var h = l["hucreler"] as! [[[String: Any]]]
                h[0][1]["renk"] = "mor"
                l["hucreler"] = h
            }
        }
        XCTAssertEqual(b.count, 1)
        XCTAssertTrue(b[0].yer.contains("«ped.neo.sarilik.matris»"), b[0].yer)
        XCTAssertTrue(b[0].yer.contains("hucreler[0][1].renk"), b[0].yer)
        XCTAssertTrue(b[0].mesaj.contains("mor"))
    }

    func testBozukJSON() {
        let s = LevhaLint.denetle(veri: Data("{\"sema_surumu\": 1,".utf8))
        XCTAssertNil(s.paket)
        XCTAssertTrue(s.bulgular[0].mesaj.hasPrefix("geçersiz JSON"))
    }

    func testCetvelDegerEksenDisinda() throws {
        let b = try bozulmus { kok in
            levha(&kok, 2) { l in
                var m = l["isaretler"] as! [[String: Any]]
                m[0]["deger"] = 40
                l["isaretler"] = m
            }
        }
        XCTAssertTrue(b.contains { $0.yer.hasSuffix("m1.deger") && $0.engelleyici })
    }
}
