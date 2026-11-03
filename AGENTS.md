# RuneScape: Dragonwilds mod geliştirme kuralları

Bu dosya tüm proje için geçerlidir. Kullanıcıyla Türkçe konuş; kodda, dosya adlarında ve teknik kimliklerde İngilizce kullan.

GitHub depo açıklamaları, kullanıcıya yönelik dokümantasyon ve commit mesajları İngilizce olmalıdır.

## Amaç ve mevcut durum

- Bu depo RuneScape: Dragonwilds için bağımsız modlar barındırır. Hedef dağıtım Nexus Mods, hedef kurulum Vortex'tir.
- İlk mod `mods/merchant`, kalıcı teknik kimliği `DragonwildsMerchant` olan tüccar modudur.
- RuneSchema tabanlı NPC/Coin prototipi ve yerel Lua kuralları vardır. Sabit NPC/harita ve canlı Coin ekleme doğrulandı; yeni dinamik mağaza, animasyon ve tezgâh için oyun regresyonu bekleniyor. Doğrulanmayan özellikleri çalışıyor diye sunma.
- Başlangıç tercihi UE4SS + Lua'dır. Blueprint/PAK, RuneSchema veya C++ ihtiyacı oyun araştırmasıyla ortaya çıkarsa gerekçesini belgele. Sırf klasör doldurmak için bağımlılık ekleme.

## Önce oku

1. Kök `README.md` ve ilgili modun `README.md` dosyası.
2. İlgili modun `docs/design.md`, `docs/compatibility.md` ve `docs/testing.md` dosyaları.
3. Değiştirilecek alt dizinde varsa daha dar kapsamlı `AGENTS.md`.

## Dizin sözleşmesi

```text
mods/<slug>/
  mod.json              # Depoya özgü sürüm ve uyumluluk kaydı
  src/<ModId>/          # Kurulacak kaynaklar; çalışma zamanı için tek gerçek kaynak
    assets/*.json       # RuneSchema: ayrı kalıcı Coin kimliği
    npc/*.json          # Sabit NPC ve tezgâh
    vendors/*.json
    ue4ss/<ModId>/Scripts/main.lua
    ue4ss/<ModId>/Data/ # README ve native-sales şablonu; dünya keşifleri çalışma zamanında
  docs/                 # Tasarım, araştırma, kurulum ve test notları
  assets/               # Kaynak görseller; otomatik paketlenmez
  scripts/              # Modun yerel geliştirme/paketleme araçları
  dist/                 # Üretilen ZIP ve SHA256; Git dışında
```

`mod.json` bizim metadata dosyamızdır; UE4SS veya Vortex tarafından otomatik okunduğunu varsayma. `src` ile ayrı bir kopya üzerinde paralel geliştirme yapma. Üretim klasörlerini elle düzenleme.

## Oyun entegrasyonu

- Dragonwilds'e ait sınıf, fonksiyon, asset yolu, item kimliği, hook, offset veya engine sürümü uydurma. Doğrulanan bilgiyi oyun build'i ve kaynak/dump referansıyla `docs/compatibility.md` içine yaz.
- Unreal/UE4SS erişimini `Scripts/merchant/integrations/` içinde tut. Fiyat ve işlem kuralları `services/`, katalog `data/`, sunum `ui/` altında kalır.
- Dünya/oyuncu hazır olmadan oyun nesnesine erişme. Nesne geçerliliğini kontrol et; world değişiminde eski UObject referanslarını taşıma. Oyun mutasyonlarını doğrulanmış game-thread mekanizmasıyla yap.
- Her frame kapsamlı nesne taraması veya sınırsız polling yapma. Hook/timer eklediğinde kapanış, tekrar yükleme ve çift kayıt davranışını düşün.
- Eksik API veya uyumsuz build durumunda mod anlaşılır bir log ile işlemi reddetmeli; yarım alışveriş veya sessiz kayıt değişikliği yapmamalı.
- Kurulu UE4SS build'inde Lua `UDataTable:AddRow(table)` alanları boş kaldı ve detached `FindRow` struct yazımı native çökme üretti. Bu yolu/probu tekrar kullanma. Tüccarın satır ve tarifleri RuneSchema `raw`/`recipes` yükleyicileriyle oluşturulur; Lua yalnızca okur ve keşif kilitlerini yönetir.
- Satın alma/satma için miktar, bakiye, stok, envanter kapasitesi ve çift istek denetimi gerekir. Para ve eşya değişimi atomik olmalı veya güvenilir geri alma sağlamalı.
- Tek oyunculu, host, katılan istemci ve dedicated server ayrı doğrulanır. Envanter/para işlemlerinde otoriteyi host/server belirlemeli; istemcinin gönderdiği fiyat veya bakiyeye güvenme.

## Kod ve kapsam

- Küçük, anlaşılır Lua modülleri kullan. `main.lua` yalnızca başlatmayı koordine etsin. Global namespace'i kirletme; yerel değişkenleri ve mod adına özgü modül yollarını kullan.
- Kullanıcı ayarları `Scripts/merchant/config.lua` içinde, güvenli varsayılanlarla tutulur. Katalogda doğrulanmamış gerçek eşya kimlikleri kullanma.
- Oyun içi metinler eklendiğinde Türkçe/İngilizce yerelleştirmeye uygun olsun. Loglar `[DragonwildsMerchant]` öneki taşısın.
- İstenen işe odaklan; gereksiz framework, örnek içerik, test veya bağımlılık ekleme. İşlem mantığı geliştiğinde ekonomi/geri alma davranışlarına anlamlı otomatik testler ekle.
- Oyun dosyaları, çıkarılmış telifli assetler, dump'lar, kayıtlar, UE4SS DLL'leri, yerel kurulum yolları ve erişim anahtarları depoya veya ZIP'e girmez. Üçüncü taraf içeriğin lisansını doğrula.

## Nexus Mods / Vortex paketleme

- Saf Lua modları için kök `<ModId>/Scripts/main.lua` olur. Tüccar 0.2.0-dev.1 itibarıyla belgelenmiş RuneSchema istisnasıdır: ZIP kökü `DragonwildsMerchant/`, içinde JSON içerik ve `ue4ss/DragonwildsMerchant/Scripts/main.lua` bulunur. Hedef `RuneSchema/mods/DragonwildsMerchant/` dizinidir; ikinci bir üst düzey UE4SS kopyası kurma. Gerekçe ve geçiş `mods/merchant/docs/compatibility.md` içindedir.
- Modun klasör adı kalıcıdır; mevcut kullanıcıları etkileyecek yeniden adlandırmayı bir geçiş olarak ele al.
- UE4SS ortak `mods.txt`, `mods.json`, loader DLL'leri veya global ayarları paketleme ve üzerine yazma.
- `enabled.txt` UE4SS'nin otomatik yükleme yöntemidir ve `mods.txt` kapatma tercihinin önüne geçebilir. İleride yükleme sırası bağımlılığı eklenirse bu kararı tekrar değerlendir.
- Blueprint varlıkları gerekirse Lua paketini olduğu gibi genişletme: güncel Vortex kurallarına göre `LogicMods`/combo paket biçimini ayrıca tasarla ve test et.
- Her mod kendi paketleme komutunu, bağımlılıklarını, manuel kurulumunu ve kaldırma adımlarını belgelendirir. Kullanıcı ayarlarının güncellemede korunmasını açıkça tasarla.
- `dist` çıktısı yalnızca dağıtılacak dosyaları içermeli. ZIP içeriğini ve SHA256 değerini doğrula. Kaynak kod ZIP'i ile mod kurulum ZIP'ini karıştırma.

## Doğrulama ve teslim

1. Değişikliğe uygun yerel kontrolü ve paketleme komutunu çalıştır.
2. ZIP içindeki yolları incele; birden fazla üst klasör, yanlış mod kimliği veya loader dosyası olmamalı.
3. Oyun erişimi varsa temiz profilde Vortex kurulum/deploy, UE4SS logu, oyun davranışı, güncelleme ve kaldırmayı doğrula.
4. Oyun build'i, mağaza, UE4SS ve Vortex eklenti sürümünü test kaydına yaz. Boş alanı tahminle doldurma.
5. Yapılmayan testleri açıkça söyle. Paket biçiminin kontrol edilmesi oyun içinde çalışma veya Vortex'te denenmiş olma anlamına gelmez.
6. Davranış değişikliklerinde modun `CHANGELOG.md` ve ilgili dokümanlarını güncelle. Kullanıcı istemedikçe Nexus'a yükleme/yayımlama yapma.

## Güncel başvuru kaynakları

- [Dragonwilds Vortex eklentisi ve paket kuralları](https://www.nexusmods.com/site/mods/1273)
- [Dragonwilds için UE4SS](https://www.nexusmods.com/runescapedragonwilds/mods/4)
- [UE4SS Lua mod rehberi](https://docs.ue4ss.com/dev/guides/creating-a-lua-mod)
- [UE4SS kaynak kodu](https://github.com/UE4SS-RE/RE-UE4SS)

Mod loader ve oyun güncellenebilir. Sürüm veya API kararlarında güncel birincil kaynağı kontrol et; araştırma tarihini kaydet.
