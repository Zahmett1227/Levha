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
        XCTAssertEqual(sonuc.hatalar, [])
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

final class LevhaLintV2Tests: XCTestCase {
    private func paket(_ ad: String) throws -> [String: Any] {
        let kok = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let veri = try Data(contentsOf: kok.appendingPathComponent("SamplePackages/\(ad).json"))
        return try JSONSerialization.jsonObject(with: veri) as! [String: Any]
    }

    private func denetle(_ p: [String: Any]) throws -> LintSonucu {
        LevhaLint.denetle(veri: try JSONSerialization.data(withJSONObject: p))
    }

    func testTumOrnekPaketlerTemiz() throws {
        for ad in ["ped.neo.sarilik", "ped.gelisim.basamaklar", "ped.kvs.konjenital", "ped.genetik.sendromlar"] {
            let s = try denetle(paket(ad))
            XCTAssertEqual(s.hatalar, [], ad)
            // Uyarılar yalnız "sorusuz kazanım" (Ölçüm'de de görünür).
            XCTAssertTrue(s.uyarilar.allSatisfy { $0.mesaj == "sorusuz kazanım" }, ad)
        }
    }

    func testSabotajKurallari() throws {
        var p = try paket("ped.kvs.konjenital")
        var levhalar = p["levhalar"] as! [[String: Any]]
        levhalar[0]["sabotajlar"] = [
            ["tip": "baglanti_ters", "hedef": ["f1", "f9"], "dogrusu": "x"],      // bağlantı yok
            ["tip": "hucre_takas", "hedef": ["f1", "f2"], "dogrusu": "x"],        // tip uygun değil
            ["tip": "renk_degistir", "hedef": ["f1"], "dogrusu": "x"],            // yanlis_renk eksik
            ["tip": "uydurma", "hedef": ["f1"], "dogrusu": "x"],
        ]
        levhalar[1]["sabotajlar"] = []
        p["levhalar"] = levhalar
        let s = try denetle(p)
        XCTAssertFalse(s.engelleyiciVar, "sabotaj hataları içe aktarmayı durdurmaz")
        XCTAssertTrue(s.hatalar.contains { $0.mesaj.contains("arasında bağlantı yok") })
        XCTAssertTrue(s.hatalar.contains { $0.mesaj.contains("uygulanamaz") })
        XCTAssertTrue(s.hatalar.contains { $0.mesaj.contains("yanlis_renk zorunlu") })
        XCTAssertTrue(s.hatalar.contains { $0.mesaj.contains("geçersiz tip") })
        XCTAssertEqual(s.uyarilar.filter { $0.mesaj.contains("üretilmiş ile idare edilir") }.count, 1)
    }

    func testZamanOlayiEksenDisindaVeBilinmeyenSerit() throws {
        var p = try paket("ped.gelisim.basamaklar")
        var levhalar = p["levhalar"] as! [[String: Any]]
        var olaylar = levhalar[0]["olaylar"] as! [[String: Any]]
        olaylar[0]["bas"] = 40
        olaylar[1]["serit"] = "s9"
        olaylar[2]["bit"] = 5
        levhalar[0]["olaylar"] = olaylar
        p["levhalar"] = levhalar
        let h = try denetle(p).hatalar
        XCTAssertTrue(h.contains { $0.yer.hasSuffix("e1.bas") && $0.engelleyici })
        XCTAssertTrue(h.contains { $0.yer.hasSuffix("e2.serit") && $0.engelleyici })
        XCTAssertTrue(h.contains { $0.yer.hasSuffix("e3.bit") && $0.mesaj.contains("küçük olamaz") })
    }

    func testBilinmeyenVucutBolgesiVeBaglantiTipi() throws {
        var p = try paket("ped.genetik.sendromlar")
        var levhalar = p["levhalar"] as! [[String: Any]]
        var bolgeler = levhalar[0]["bolgeler"] as! [[String: Any]]
        bolgeler[0]["bolge"] = "kuyruk"
        levhalar[0]["bolgeler"] = bolgeler
        p["levhalar"] = levhalar
        let s = try denetle(p)
        XCTAssertNil(s.paket)
        XCTAssertTrue(s.bulgular[0].mesaj.contains("kuyruk"))

        var k = try paket("ped.kvs.konjenital")
        var kl = k["levhalar"] as! [[String: Any]]
        var b = kl[0]["baglantilar"] as! [[String: Any]]
        b[0]["tip"] = "zayiflatir"
        kl[0]["baglantilar"] = b
        k["levhalar"] = kl
        XCTAssertTrue(try denetle(k).bulgular[0].yer.contains("baglantilar[0].tip"))
    }
}

final class LevhaLintV3Tests: XCTestCase {
    private func paket(_ ad: String) throws -> [String: Any] {
        let kok = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let veri = try Data(contentsOf: kok.appendingPathComponent("SamplePackages/\(ad).json"))
        return try JSONSerialization.jsonObject(with: veri) as! [String: Any]
    }

    func testKazanimVeAileKurallari() throws {
        var p = try paket("ped.neo.sarilik")
        var k = p["kazanimlar"] as! [[String: Any]]
        k[0]["kalip"] = "uydurma_kalip"
        k[1]["sorulabilirlik"] = 7
        p["kazanimlar"] = k
        var sorular = p["sorular"] as! [[String: Any]]
        sorular[0]["kazanim"] = "k99"
        sorular[1].removeValue(forKey: "kazanim")
        sorular[2]["secenek_aile"] = ["0": "Biliyer atrezi", "1": "Uzaylı sarılığı", "2": "Konjenital hipotiroidi"]
        sorular[3]["kalip"] = "baska_kalip"
        p["sorular"] = sorular
        var levhalar = p["levhalar"] as! [[String: Any]]
        levhalar[0].removeValue(forKey: "insa_sirasi")
        p["levhalar"] = levhalar
        let s = LevhaLint.denetle(veri: try JSONSerialization.data(withJSONObject: p))
        let h = s.hatalar.map(\.description)
        XCTAssertTrue(h.contains { $0.contains("k1") && $0.contains("tanımsız kalıp") }, "\(h)")
        XCTAssertTrue(h.contains { $0.contains("sorulabilirlik") && $0.contains("1–5") })
        XCTAssertTrue(h.contains { $0.contains("tanımsız kazanım \"k99\"") })
        XCTAssertTrue(h.contains { $0.contains("her sorunun kazanımı olmalı") })
        XCTAssertTrue(h.contains { $0.contains("\"Uzaylı sarılığı\" ailede yok") })
        XCTAssertTrue(h.contains { $0.contains("tanımsız kalıp \"baska_kalip\"") })
        let u = s.uyarilar.map(\.description)
        XCTAssertTrue(u.contains { $0.contains("insa_sirasi") }, "\(u)")
        XCTAssertTrue(u.contains { $0.contains("çeldiricinin yalnız") }, "\(u)")
    }
}
