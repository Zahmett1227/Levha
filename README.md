# Levha

Kişisel TUS çalışma uygulaması (iOS 17+, SwiftUI + SwiftData, yalnız iPhone).

## Kurulum

1. `Levha.xcodeproj`'u Xcode 16+ ile aç.
2. *Signing & Capabilities* → Team: kendi Apple ID'n. Bundle id gerekirse değiştir (`tr.kisisel.levha`).
3. iPhone'u bağla, **Run**.

**iCloud ve App Group:** Proje iCloud Drive (iCloud Documents) ve App Group (`group.tr.kisisel.levha`,
widget için) yetkileriyle gelir; ikisi de ücretli geliştirici hesabı ister. Ücretsiz Apple ID ile kuruyorsan
*Signing & Capabilities*'ten **iCloud** ve **App Groups**'u (uygulama ve LevhaWidget hedeflerinde) kaldır.
Uygulama o zaman yerel klasöre ve yerel depoya düşer; widget boş görünür, başka bir şey değişmez.
Bundle id'yi değiştirirsen `project.yml`'deki `iCloud.tr.kisisel.levha` ve `group.tr.kisisel.levha` geçen
yerleri ve `Ortak/WidgetAnligi.swift`'teki grup adını da güncelle.

**Widget:** Ana ekranda uzun bas › + › "Levha": orta boy (maskeli levha, dokununca Örtme'de açar) ve
küçük boy (bugünün turu). Kısayollar uygulamasında "Levha turu" eylemi uygulamayı Bugün'de açar.

Projeye dosya eklersen: `xcodegen generate` (proje `project.yml`'den üretilir).

## Model sağlayıcı

Ölçüm › ⚙︎ Ayarlar › **Model sağlayıcı**:

- **Sahte (çevrimdışı):** ağ çağrısı yok; "Modele sor", levha genişletme, Editör değerlendirmesi ve kitap
  sayfası önerisi hazır yanıtlarla çalışır.
- **OpenAI uyumlu:** `/chat/completions` (varsayılan) ya da `/responses` konuşan her sağlayıcı. Alanlar:
  API taban URL (`https://api.openai.com/v1`), API anahtarı (yalnız bu cihazın Keychain'inde), model adı
  (varsayılan `chatgpt 5.6 luna`), max çıkış token (800), sıcaklık (0,3). **Bağlantı testi** 1 token'lık bir istek
  gönderir. Model `temperature`/`max_tokens` reddederse alan atılıp bir kez yeniden denenir.

Anahtar yoksa sağlayıcı kendiliğinden Sahte'ye döner (Ayarlar'da sarı uyarı). Harcanan token Ölçüm › Kullanım'da
("Bu ay: N çağrı, X giriş / Y çıkış token"). Kitap sayfası "Modele sor" yalnız okunan metni ve levha başlıklarını
gönderir; fotoğraf cihazdan çıkmaz.

## Paketler nereye konur

- iCloud açıksa: **Dosyalar › iCloud Drive › Levha › Paketler**
- iCloud kapalıysa: **Dosyalar › Bu iPhone'da › Levha › Paketler**

Uygulamada **İçerik** sekmesi klasördeki tüm `.json` dosyalarını listeler (hatalı olanlar kırmızı, hangi
levha/hangi alan olduğu yazar). **Hepsini içe aktar** ya da **Dosya seç…**. `SamplePackages/` içindeki örnek
paketler uygulamayla gelir; yeni ya da değişmiş olanlar açılışta otomatik yüklenir.

Aynı `id`'li levha yeniden içe aktarılınca **düzen korunur** (konumlar ve taslaktan eklenen düğümler değişmez);
etiket, not ve sorular güncellenir. Paketteki levhanın `revizyon`'u depodakinden büyükse **paket kazanır**:
konumlar JSON'dan gelir, yerel eklemeler silinir. Kendi notların (Notum) hiçbir durumda silinmez.

**Kitap sayfası (Bugün):** Simülatörde kamera yoktur: `xcrun simctl addmedia booted SamplePackages/test-sayfa.jpg`
ile test sayfasını galeriye ekle ya da ekrandaki **Örnek sayfayla dene**'ye dokun.

## Yedekleme

İçerik › **Yedek**:

- **Yedekle:** tek `.levhayedek` dosyası (zip içinde `yedek.json`) → paylaşım sayfası. İçinde: tüm olaylar
  (Örtme, soru, sabotaj, İnşa, İpucu avı, Editör, Mini sınav, model kullanımı), levha durumları, düğüm zayıflıkları,
  Notum'lar, "Modele sor" geçmişi, taslaklar, Yazdıklarım soruları, taslaktan eklenen yerel düğümler, A/B grupları
  ve ayarlar. **API anahtarı ve paket içeriği girmez.**
- **Geri yükle…:** dosyayı seç → özet ("53 olay, 1 not, 2 yazılmış soru…") → **Birleştir** (aynı kayıtlar atlanır)
  ya da **Üzerine yaz** (uygulamanın ürettiği her şey silinip yedekten yazılır). Kayıtlar `globalId` / `levhaId` /
  `dugumId` ile eşlenir; levhası henüz içe aktarılmamış yerel düğümler bekleme listesine alınır, paket içe aktarılınca
  bağlanır.
- **Otomatik:** her gün 04:00 dönüşünden sonraki ilk açılışta `Levha/Yedek/` klasörüne tarihli yedek; son 7 gün tutulur.

## Şema v4 özeti

Tam şema: `Levha/Schema/levha.schema.json`. Sürüm 1–3 paketler okunmaya devam eder.

- **Paket:** `sema_surumu`, `paket_id`, `ders`, `bolum`, `alt_konu`, `levhalar`, `sorular`, `kazanimlar`, `aileler`.
- **Levha:** `id`, `tip` (algoritma · matris · sayi_cetveli · zaman_cizelgesi · yolak · agac · vucut_haritasi),
  `baslik`, `akilda_kalan`, tipine göre düğümler/hücreler/işaretler/olaylar/bölgeler, `ortme_sirasi`, `insa_sirasi`,
  `sabotajlar`, `kaynak` (`kitap`, `sayfa`, `baski`, `anahtar_kelimeler`), `revizyon`.
- **Kazanım:** `id`, `metin`, `kalip` (12 kalıptan biri), `dugumler`, `sorulabilirlik` 1–5, `aile`, `anahtar_ipucu`.
- **Aile:** `id`, `ad`, `uyeler`, `ayirici` (`"A|B"` → ayırıcı ipucu).
- **Soru:** `id`, `levha`, `kok`, 5 `secenekler`, `dogru` 0–4, `aciklama`, `aciklama_yolu`, `celdirici_dugum`,
  `kazanim`, `kalip`, `zorluk` 1–3, `secenek_aile`, `ipucu_sirasi` (`metin`, `dugum`, `tur`, `agirlik` 0–3,
  `yaniltici`), `kirilimlar` (`ipucu`, `yeni_metin`, `yeni_dogru`, `aciklama`).

## İçerik üretim kuralları

Paket yazarken (insan ya da model) uyulacak 10 kural:

1. **Sayı uydurma.** Emin olmadığın eşik, oran ya da yaşı yazma; düğüm notuna "kaynağa bak" / "nomograma bak" yaz.
   Sabit değeri olmayan cetvel işaretinde `deger` boş kalır.
2. **Tek ekran.** Levha başına 6–20 düğüm (matriste 6–24 hücre, 2–4 sütun × 2–6 satır); etiket en fazla 28 karakter.
   Ayrıntı nota gider, etikete değil.
3. **Renk anlam taşır.** Aynı anlam her pakette aynı renkle; `tus: true` yalnız TUS'ta gerçekten sorulan düğümde.
4. **Her kazanıma soru.** Kazanımın `kalip`'i 12 kalıptan biri, `sorulabilirlik` 1–5; sorusuz kazanım bırakma.
5. **TUS biçimi.** Vaka kökü 50–80 kelime, üçüncü tekil, resmî dil; soru "…aşağıdakilerden hangisidir?" ile biter;
   ondalıkta virgül; mutlak ifade (her zaman, asla, sadece) yok.
6. **Şıklar dengeli.** 5 farklı şık; doğru şık en uzun çeldiriciden 15+ karakter uzun olmasın; tek savunulabilir doğru.
7. **Çeldiriciler aileden.** `secenek_aile` ile en az 3 çeldirici aynı aileden; her çeldirici `celdirici_dugum` ile
   levhadaki karşılığına bağlı; `aciklama_yolu` doğru cevabın düğüm yolu.
8. **İpucu sırası birebir.** Vaka sorularının çoğunda 3–6 ipucu; her `metin` kökte harfi harfine geçen alt metin;
   en az biri `yaniltici: true` (kökte gerçekten bulunan, tıbben önemsiz ama aklı çelen ayrıntı); `agirlik` 0–3.
9. **Kırılım tartışmasız olmalı.** Tek ipucu değişince başka bir şık açıkça doğru olmuyorsa kırılım yazma.
10. **Lint'ten geçir.** Her levhada `ortme_sirasi` (≥3), `insa_sirasi`, `kaynak.anahtar_kelimeler` (4–6) ve
    düzen değiştiyse artırılmış `revizyon`; göndermeden `swift run levha-lint paket.json` → `OK`.

## Lint

```bash
swift run levha-lint SamplePackages/ped.neo.sarilik.json
```

Birden fazla dosya verilebilir (`swift run levha-lint SamplePackages/*.json`). Çıktı satır satır hata,
sonda `OK` ya da `N hata`; uyarılar (sorusuz kazanım, ipucu sırası olmayan vaka sorusu, anahtar kelimesi olmayan
levha...) listelenir ama hata sayılmaz. Lint ve saf fonksiyon testleri (zamanlayıcı, öncelik, tahmini net, ipucu
puanı, sayfa eşleme, tahmin politikası, A/B z-testi): `cd Tools/levha-lint && swift test`.
