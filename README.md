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
- **OpenAI uyumlu:** `/responses` (varsayılan) ya da `/chat/completions` konuşan her sağlayıcı. Alanlar:
  API taban URL (`https://api.openai.com/v1`), API anahtarı (yalnız bu cihazın Keychain'inde), model adı
  (varsayılan `gpt-5.6-luna`), muhakeme (Yok · **Düşük** · Orta · Yüksek · Çok yüksek · En yüksek →
  `reasoning.effort` / `reasoning_effort`), max çıkış token (800), sıcaklık (0,3).
  - Muhakeme token'ları çıkış sınırından düşer: istekte sınır = max çıkış + düzey payı (Düşük +4.000, Orta +12.000,
    Yüksek +25.000…); sınır yine dolarsa "Token sınırı doldu" uyarısı çıkar. Ödenen yalnız gerçekten üretilen token'dır.
  - Sıcaklık yalnız muhakeme **Yok** iken gönderilir (GPT-5.6 öbür düzeylerde reddeder).
  - Responses istekleri `store: false` gider. **Bağlantı testi** muhakemesiz 16 token'lık bir istek gönderir ve
    sağlayıcının döndürdüğü model adını gösterir.
  - Sağlayıcı bir alanı reddederse alan atılır ya da eşdeğerine çevrilir (`max_completion_tokens` ↔ `max_tokens`;
    muhakemesiz modelde `reasoning_effort` atılır) ve bir kez yeniden denenir.

Anahtar yoksa sağlayıcı kendiliğinden Sahte'ye döner (Ayarlar'da sarı uyarı). Harcanan token Ölçüm › Kullanım'da
("Bu ay: N çağrı, X giriş / Y çıkış token"). Kitap sayfası "Modele sor" yalnız okunan metni ve levha başlıklarını
gönderir; fotoğraf cihazdan çıkmaz.

## Paketler nereye konur

- iCloud açıksa: **Dosyalar › iCloud Drive › Levha › Paketler**
- iCloud kapalıysa: **Dosyalar › Bu iPhone'da › Levha › Paketler**

Uygulamada **İçerik** sekmesi klasördeki tüm `.json` dosyalarını listeler (hatalı olanlar kırmızı, hangi
levha/hangi alan olduğu yazar); konu paketleri ve soru paketleri ayrı listededir. **Hepsini içe aktar** ikisini de
alır (önce konu paketleri, sonra soru paketleri) ya da **Dosya seç…**. `SamplePackages/` içindeki örnek paketler
uygulamayla gelir; yeni ya da değişmiş olanlar açılışta otomatik yüklenir.

Aynı `id`'li levha yeniden içe aktarılınca **düzen korunur** (konumlar ve taslaktan eklenen düğümler değişmez);
etiket, not ve sorular güncellenir. Paketteki levhanın `revizyon`'u depodakinden büyükse **paket kazanır**:
konumlar JSON'dan gelir, yerel eklemeler silinir. Kendi notların (Notum) hiçbir durumda silinmez.

**Kitap sayfası (Bugün):** Simülatörde kamera yoktur: `xcrun simctl addmedia booted SamplePackages/test-sayfa.jpg`
ile test sayfasını galeriye ekle ya da ekrandaki **Örnek sayfayla dene**'ye dokun.

## Yedekleme

İçerik › **Yedek**:

- **Yedekle:** tek `.levhayedek` dosyası (zip içinde `yedek.json`) → paylaşım sayfası. İçinde: tüm olaylar
  (Örtme, soru, sabotaj, İnşa, İpucu avı, Editör, Mini sınav, model kullanımı), levha durumları, düğüm ve bağımsız soru zayıflıkları,
  Notum'lar, "Modele sor" geçmişi, taslaklar, Yazdıklarım soruları, taslaktan eklenen yerel düğümler, A/B grupları
  ve ayarlar. **API anahtarı ve paket içeriği girmez.**
- **Geri yükle…:** dosyayı seç → özet ("53 olay, 1 not, 2 yazılmış soru…") → **Birleştir** (aynı kayıtlar atlanır)
  ya da **Üzerine yaz** (uygulamanın ürettiği her şey silinip yedekten yazılır). Kayıtlar `globalId` / `levhaId` /
  `dugumId` ile eşlenir; levhası henüz içe aktarılmamış yerel düğümler bekleme listesine alınır, paket içe aktarılınca
  bağlanır.
- **Otomatik:** her gün 04:00 dönüşünden sonraki ilk açılışta `Levha/Yedek/` klasörüne tarihli yedek; son 7 gün tutulur.

## Konu anlatımı (v5)

Konu paketine isteğe bağlı `"anlatim": "<markdown>"` eklenir (2.000–6.000 kelime; `##` başlıklar, `**kalın**` terimler,
`|` tablolar, `>` TUS notu kutusu, `-` / `1.` listeler).

- **Oku:** Levha sayfasında kırıntının (`Neonatoloji · Levha 1/3 · Algoritma`) yanındaki düğme. Tam ekran okuma,
  İçindekiler, yazı boyutu (A− / A+); kalınan yer paket başına hatırlanır.
- **Referanslar:** `[[n2]]` paketteki düğüm, `[[algoritma]]` ya da `[[ped.neo.sarilik.algoritma]]` levha,
  `[[levha_id#n2]]` belirli levhanın düğümü; `[[n2|ilk 24 saatte]]` görünen metni değiştirir. Dokununca levha Keşif'te
  açılır, düğüm koyu halkayla vurgulanır ve notu görünür.
- **Önce oku (5 dk):** Bugün › Kitapsız modda Yeni bloğunun başında; Yeni levhalarından birinin alt konusunun
  anlatımı varsa çıkar, okununca tiklenir.
- **`anlatim_baslik`:** Soruya yazılan başlık; cevaptan sonra "Anlatımda oku" o başlıktan açar.

## Soru paketleri (v5)

`"tur": "soru_paketi"` olan dosya levhasızdır: `paket_id`, `ders`, `bolum`, `alt_konu`, `sorular[]` (isteğe bağlı
`kazanimlar`, `aileler`). Sorularda `levha` ve `dugumler` isteğe bağlıdır:

- `levha` yazılırsa soru o levhaya bağlanır; levha başka paketteyse tam id (`ped.neo.sarilik.algoritma`). Levhanın
  paketi sonradan içe aktarılırsa bağlantı o zaman kurulur; paket silinirse soru bağımsız kalır.
- `levha` yoksa soru **bağımsızdır**: Soru modunda, Mini sınavda, Günlük Tur Soru bloğunda ve İpucu avında normal
  çıkar. "Levhada göster" yerine açıklama ve (varsa) `anlatim_baslik` bağlantısı görünür. Başlık; bağlı levhanın,
  sonra aynı ders/alt konunun konu paketinin anlatımında aranır.
- **Zayıflık:** Bağımsız sorunun cevabı `kazanim` üzerinden sayılır (kazanımın düğümleri levhalarda varsa Örtme'de öne
  alınır); kazanımı yoksa alt konu düzeyinde (Ölçüm › Soru › "Bağımsız sorularda zayıf noktalar"). `kazanim` paketin
  kendi kazanımı, `paket_id.k3` tam yolu ya da aynı alt konunun konu paketindeki kazanım olabilir.
- Soru Konu seç listesinde ayrı görünür; aynı ders/alt konuyu seçince konu paketinin sorularıyla birlikte de gelir.

## Şema v5 özeti

Tam şema: `Levha/Schema/levha.schema.json`. Sürüm 1–4 paketler okunmaya devam eder.

- **Paket:** `sema_surumu`, `paket_id`, `ders`, `bolum`, `alt_konu`, `levhalar`, `sorular`, `kazanimlar`, `aileler`,
  `anlatim` (v5), `tur` (v5: yoksa konu paketi; `"soru_paketi"` → levhasız).
- **Levha:** `id`, `tip` (algoritma · matris · sayi_cetveli · zaman_cizelgesi · yolak · agac · vucut_haritasi),
  `baslik`, `akilda_kalan`, tipine göre düğümler/hücreler/işaretler/olaylar/bölgeler, `ortme_sirasi`, `insa_sirasi`,
  `sabotajlar`, `kaynak` (`kitap`, `sayfa`, `baski`, `anahtar_kelimeler`), `revizyon`.
- **Kazanım:** `id`, `metin`, `kalip` (12 kalıptan biri), `dugumler`, `sorulabilirlik` 1–5, `aile`, `anahtar_ipucu`.
- **Aile:** `id`, `ad`, `uyeler`, `ayirici` (`"A|B"` → ayırıcı ipucu).
- **Soru:** `id`, `levha` (soru paketinde isteğe bağlı), `kok`, 5 `secenekler`, `dogru` 0–4, `aciklama`, `aciklama_yolu`,
  `celdirici_dugum`, `kazanim`, `kalip`, `zorluk` 1–3, `secenek_aile`, `ipucu_sirasi` (`metin`, `dugum`, `tur`,
  `agirlik` 0–3, `yaniltici`), `kirilimlar` (`ipucu`, `yeni_metin`, `yeni_dogru`, `aciklama`), `anlatim_baslik` (v5).

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

Anlatım ve soru paketi için ek olarak:

- **Anlatım levhayı tekrar etmez, bağlar.** Düğümde geçen terimi `[[düğüm|doğal metin]]` ile bağla; sayılar levha
  notlarındakiyle aynı olsun, eşik ve doz için "kaynağa bak" / "nomograma bak" kuralı burada da geçerli.
- **Her soruya `anlatim_baslik`.** Başlık anlatımda birebir bulunmalı (büyük/küçük harf ve aksan önemsiz).
- **Soru paketinde 5 şık, `dogru` ve `aciklama` zorunlu;** kalıp ve kazanım önerilir (yoksa uyarı). Tarihle değişen
  bilgi (aşı takvimi gibi) açıklamada tarih ve kaynakla yazılır.

## Lint

```bash
swift run levha-lint SamplePackages/ped.neo.sarilik.json
```

Birden fazla dosya verilebilir (`swift run levha-lint SamplePackages/*.json`). Çıktı satır satır hata,
sonda `OK` ya da `N hata`; uyarılar (sorusuz kazanım, ipucu sırası olmayan vaka sorusu, anahtar kelimesi olmayan
levha...) listelenir ama hata sayılmaz. v5'te ayrıca: anlatımdaki her `[[...]]` paketteki bir düğüm ya da levha
olmalı (hata; başka paketin tam levha id'si uyarı), `anlatim_baslik` anlatımda bulunmalı (hata), anlatım
2.000–6.000 kelime ve `##` başlıklı olmalı (uyarı); soru paketinde 5 şık, `dogru`, `aciklama` zorunlu (hata), kalıp
ve kazanım yoksa uyarı, levhası olmayan soruda düğüm alanı hata. Lint ve saf fonksiyon testleri (zamanlayıcı, öncelik, tahmini net, ipucu
puanı, sayfa eşleme, tahmin politikası, A/B z-testi): `cd Tools/levha-lint && swift test`.
