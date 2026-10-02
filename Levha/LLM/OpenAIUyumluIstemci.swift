import Foundation

/// OpenAI uyumlu sağlayıcı: `/chat/completions` ya da `/responses`. Ağ katmanı yalnız `URLSession`.
struct OpenAIUyumluIstemci: LLMIstemci {
    let tabanURL: URL
    let anahtar: String
    let model: String
    let bicim: APIBicimi
    /// Görünür yanıt bütçesi; istekte muhakeme payı eklenir.
    let maxCikis: Int
    let sicaklik: Double
    let muhakeme: MuhakemeDuzeyi
    /// Kullanım kaydının amacı; nil → kayıt yok (bağlantı testi).
    let amac: LLMAmac?
    var oturum: URLSession = .shared

    private var yol: String { bicim == .chat ? "chat/completions" : "responses" }

    /// Muhakeme token'ları da çıkış sınırından düşer.
    private var cikisSiniri: Int { maxCikis + muhakeme.pay }

    /// Çıkış sınırı, muhakeme düzeyi ve (yalnız muhakeme yokken) sıcaklık. Responses yanıtı sunucuda saklanmaz.
    private func modelAlanlari(_ g: inout [String: Any]) {
        switch bicim {
        case .chat:
            g["max_completion_tokens"] = cikisSiniri
            g["reasoning_effort"] = muhakeme.rawValue
        case .responses:
            g["max_output_tokens"] = cikisSiniri
            g["reasoning"] = ["effort": muhakeme.rawValue]
            g["store"] = false
        }
        if muhakeme == .yok { g["temperature"] = sicaklik }
    }

    // MARK: - Akış

    func sor(sistem: String, mesajlar: [LLMMesaj]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { devam in
            let gorev = Task {
                do {
                    let (baytlar, _) = try await akisBaglan(akisGovdesi(sistem, mesajlar))
                    var parcaVar = false
                    var kesildi = false
                    satirlar: for try await satir in baytlar.lines {
                        guard satir.hasPrefix("data:") else { continue }
                        let veri = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if veri == "[DONE]" { break }
                        guard let json = (try? JSONSerialization.jsonObject(with: Data(veri.utf8))) as? [String: Any] else { continue }
                        if let hata = json["error"] as? [String: Any] {
                            throw LLMHatasi.reddedildi(0, hata["message"] as? String ?? "akış hatası")
                        }
                        switch bicim {
                        case .chat:
                            if let secim = (json["choices"] as? [[String: Any]])?.first {
                                if let metin = (secim["delta"] as? [String: Any])?["content"] as? String, !metin.isEmpty {
                                    parcaVar = true
                                    devam.yield(metin)
                                }
                                if secim["finish_reason"] as? String == "length" { kesildi = true }
                            }
                            if let u = json["usage"] as? [String: Any] {
                                kullanimKaydet(u["prompt_tokens"], u["completion_tokens"])
                            }
                        case .responses:
                            switch json["type"] as? String {
                            case "response.output_text.delta":
                                if let d = json["delta"] as? String, !d.isEmpty {
                                    parcaVar = true
                                    devam.yield(d)
                                }
                            case "response.completed":
                                let u = (json["response"] as? [String: Any])?["usage"] as? [String: Any]
                                kullanimKaydet(u?["input_tokens"], u?["output_tokens"])
                                break satirlar
                            case "response.incomplete":
                                let u = (json["response"] as? [String: Any])?["usage"] as? [String: Any]
                                kullanimKaydet(u?["input_tokens"], u?["output_tokens"])
                                kesildi = true
                                break satirlar
                            case "response.failed", "error":
                                let r = json["response"] as? [String: Any]
                                let mesaj = ((r?["error"] ?? json["error"]) as? [String: Any])?["message"] as? String
                                throw LLMHatasi.reddedildi(0, mesaj ?? "yanıt başarısız")
                            default:
                                break
                            }
                        }
                    }
                    if !parcaVar && !Task.isCancelled { throw kesildi ? LLMHatasi.sinirDoldu : LLMHatasi.bosYanit }
                    if kesildi { devam.yield("\n\n(yanıt token sınırında kesildi)") }
                    devam.finish()
                } catch {
                    devam.finish(throwing: LLMHatasi.esle(error))
                }
            }
            devam.onTermination = { _ in gorev.cancel() }
        }
    }

    private func akisGovdesi(_ sistem: String, _ mesajlar: [LLMMesaj]) -> [String: Any] {
        let liste = mesajlar.map { ["role": $0.rol, "content": $0.icerik] }
        var g: [String: Any]
        switch bicim {
        case .chat:
            g = ["model": model, "messages": [["role": "system", "content": sistem]] + liste, "stream": true,
                 "stream_options": ["include_usage": true]]
        case .responses:
            g = ["model": model, "instructions": sistem, "input": liste, "stream": true]
        }
        modelAlanlari(&g)
        return g
    }

    // MARK: - JSON

    func jsonUret(sistem: String, istem: String) async throws -> Data {
        var govde: [String: Any]
        switch bicim {
        case .chat:
            govde = ["model": model, "messages": [["role": "system", "content": sistem], ["role": "user", "content": istem]],
                     "response_format": ["type": "json_object"]]
        case .responses:
            govde = ["model": model, "instructions": sistem, "input": istem, "text": ["format": ["type": "json_object"]]]
        }
        modelAlanlari(&govde)
        do {
            let json = try await gonder(govde)
            // Yarım kalan JSON işe yaramaz.
            if Self.kesildiMi(json, bicim) { throw LLMHatasi.sinirDoldu }
            guard let metin = Self.yanitMetni(json, bicim), !metin.isEmpty else { throw LLMHatasi.bosYanit }
            return IstemSablonlari.jsonAyikla(Data(metin.utf8))
        } catch {
            throw LLMHatasi.esle(error)
        }
    }

    /// Muhakemesiz, 16 token'lık "ok" isteği; başarıda sağlayıcının bildirdiği model adıyla kısa bir özet döner.
    func baglantiTesti() async throws -> String {
        let govde: [String: Any] = bicim == .chat
            ? ["model": model, "messages": [["role": "user", "content": "ok"]], "max_completion_tokens": 16, "reasoning_effort": "none"]
            : ["model": model, "input": "ok", "max_output_tokens": 16, "reasoning": ["effort": "none"], "store": false]
        let bas = Date.now
        let json: [String: Any]
        do {
            json = try await gonder(govde)
        } catch {
            throw LLMHatasi.esle(error)
        }
        return "Bağlantı tamam · \(json["model"] as? String ?? model) · \(Int(Date.now.timeIntervalSince(bas) * 1000)) ms"
    }

    /// Yanıt çıkış sınırında kesildi mi (chat `finish_reason: length`, responses `status: incomplete`)?
    static func kesildiMi(_ json: [String: Any], _ bicim: APIBicimi) -> Bool {
        switch bicim {
        case .chat: return ((json["choices"] as? [[String: Any]])?.first)?["finish_reason"] as? String == "length"
        case .responses: return json["status"] as? String == "incomplete"
        }
    }

    static func yanitMetni(_ json: [String: Any], _ bicim: APIBicimi) -> String? {
        switch bicim {
        case .chat:
            let mesaj = ((json["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any]
            return mesaj?["content"] as? String
        case .responses:
            if let t = json["output_text"] as? String { return t }
            let parcalar = (json["output"] as? [[String: Any]] ?? [])
                .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                .filter { ($0["type"] as? String) == "output_text" }
                .compactMap { $0["text"] as? String }
            return parcalar.isEmpty ? nil : parcalar.joined()
        }
    }

    // MARK: - Bağlantı

    private func istek(_ govde: [String: Any], akis: Bool) throws -> URLRequest {
        var r = URLRequest(url: tabanURL.appending(path: yol))
        r.httpMethod = "POST"
        r.timeoutInterval = 90
        r.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if akis { r.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        r.httpBody = try JSONSerialization.data(withJSONObject: govde)
        return r
    }

    /// Akışsız istek; 400'de reddedilen alanı atıp yeniden dener (her alan bir kez).
    private func gonder(_ ilk: [String: Any]) async throws -> [String: Any] {
        var govde = ilk
        var uyarlanan = Set<String>()
        while true {
            let (veri, yanit) = try await oturum.data(for: try istek(govde, akis: false))
            let kod = (yanit as? HTTPURLResponse)?.statusCode ?? 0
            let metin = String(data: veri, encoding: .utf8) ?? ""
            if (200..<300).contains(kod) {
                let json = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any] ?? [:]
                if bicim == .chat, let u = json["usage"] as? [String: Any] {
                    kullanimKaydet(u["prompt_tokens"], u["completion_tokens"])
                } else if let u = json["usage"] as? [String: Any] {
                    kullanimKaydet(u["input_tokens"], u["output_tokens"])
                }
                return json
            }
            if kod == 400, let yeni = Self.uyarla(govde, hata: metin, yapilan: &uyarlanan) {
                govde = yeni
                continue
            }
            throw LLMHatasi.http(kod, Self.hataMesaji(metin))
        }
    }

    private func akisBaglan(_ ilk: [String: Any]) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var govde = ilk
        var uyarlanan = Set<String>()
        while true {
            let (baytlar, yanit) = try await oturum.bytes(for: try istek(govde, akis: true))
            let http = yanit as? HTTPURLResponse
            let kod = http?.statusCode ?? 0
            if (200..<300).contains(kod), let http { return (baytlar, http) }
            var veri = Data()
            for try await b in baytlar {
                veri.append(b)
                if veri.count > 65_536 { break }
            }
            let metin = String(data: veri, encoding: .utf8) ?? ""
            if kod == 400, let yeni = Self.uyarla(govde, hata: metin, yapilan: &uyarlanan) {
                govde = yeni
                continue
            }
            throw LLMHatasi.http(kod, Self.hataMesaji(metin))
        }
    }

    /// Sağlayıcı bir alanı reddederse hata metninde adı geçen alan atılır ya da eşdeğerine çevrilir
    /// (`max_tokens` ↔ `max_completion_tokens`; muhakemesiz modelde `reasoning_effort`/`reasoning` atılır).
    /// Alan adı geçmiyorsa bir kez sıcaklık atılır.
    static func uyarla(_ g: [String: Any], hata: String, yapilan: inout Set<String>) -> [String: Any]? {
        var g = g
        let m = hata.lowercased()
        func alan(_ ad: String) -> Bool { g[ad] != nil && !yapilan.contains(ad) && m.contains(ad) }
        if alan("temperature") {
            g["temperature"] = nil
            yapilan.insert("temperature")
            return g
        }
        if alan("max_tokens") {
            g["max_completion_tokens"] = g["max_tokens"]
            g["max_tokens"] = nil
            yapilan.insert("max_tokens")
            return g
        }
        if alan("max_completion_tokens") {
            g["max_tokens"] = g["max_completion_tokens"]
            g["max_completion_tokens"] = nil
            yapilan.formUnion(["max_completion_tokens", "max_tokens"])
            return g
        }
        for ad in ["reasoning_effort", "reasoning", "store", "max_output_tokens", "stream_options", "response_format"] where alan(ad) {
            g[ad] = nil
            yapilan.insert(ad)
            return g
        }
        if !yapilan.contains("genel"), g["temperature"] != nil {
            g["temperature"] = nil
            yapilan.insert("genel")
            return g
        }
        return nil
    }

    static func hataMesaji(_ govde: String) -> String {
        let json = (try? JSONSerialization.jsonObject(with: Data(govde.utf8))) as? [String: Any]
        if let m = (json?["error"] as? [String: Any])?["message"] as? String { return m }
        if let m = json?["message"] as? String { return m }
        return String(govde.prefix(200))
    }

    private func kullanimKaydet(_ giris: Any?, _ cikis: Any?) {
        guard let amac else { return }
        let g = (giris as? Int) ?? (giris as? NSNumber)?.intValue ?? 0
        let c = (cikis as? Int) ?? (cikis as? NSNumber)?.intValue ?? 0
        guard g + c > 0 else { return }
        Task { @MainActor in LLMKullanimDefteri.kaydet(giris: g, cikis: c, amac: amac) }
    }
}

/// Token kullanımını depoya yazar.
@MainActor
enum LLMKullanimDefteri {
    static func kaydet(giris: Int, cikis: Int, amac: LLMAmac) {
        let ctx = Depo.container.mainContext
        ctx.insert(LLMKullanim(tarih: .now, giris: giris, cikis: cikis, amac: amac.rawValue))
        try? ctx.save()
        OlayDefteri.degisti()
    }
}
