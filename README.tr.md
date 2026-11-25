# SyHost

[English](README.md) · **Türkçe** · [日本語](README.ja.md)

**Modlu Minecraft sunucusunu tek tıkla kur, aç, yönet.**
Bir Modrinth paketi (`.mrpack`) seç; Java, mod yükleyici, modlar ve ayarlar kendiliğinden kurulsun.
Arkadaşların internetten bağlansın, sen de her şeyi şık, animasyonlu bir terminal ekranından yönet.

> Windows 10 / 11 · NeoForge · Forge · Fabric · English, Türkçe, 日本語 · Yapımcı: **sykait**

---

## ✨ Neler yapar?

- **Tek tıkla sunucu kurulumu:** `.mrpack` dosyasını seç, gerisini SyHost halleder
  (doğru Java sürümü, NeoForge/Forge/Fabric, sunucuda çalışan modlar, ayar dosyaları, hazır dünya).
- **Birden fazla sunucu:** hepsi bir listede, istediğini seçip Enter'a basarsın.
- **Arkadaşların için bağlantı:** [playit.gg](https://playit.gg) ile bedava, sabit bir adres
  (çoğu ev internetindeki CGNAT sorununu aşar). playit sadece SyHost açıkken çalışır.
- **Canlı durum ekranı:** sunucu açılıyor / açık / kapanıyor şeridi, oyuncular, RAM ve CPU kullanımı.
- **Sade konsol:** sadece önemli olaylar (giriş, çıkış, sohbet, hatalar). İstersen tüm kayıtlar.
- **Performans paketleri:** Düşük / Normal / Yüksek. Bilgisayarının RAM'ine göre kendiliğinden ayarlanır.
- **Otomatik yedek:** 3 saatte bir dünyanın yedeği alınır, son 10 yedek saklanır.
- **Güvenli kapatma:** F10 → dünya kaydedilir, sunucu kapanır, arkada hiçbir şey kalmaz.
- **Küçük mod:** ekranın köşesinde duran mini durum penceresi (Ctrl+Alt+K).
- **Gizle/göster:** oyun oynarken bile Ctrl+Alt+G ile.
- **3 dil:** English, Türkçe, 日本語 (ana menüde **L** tuşu).

---

## 📥 Kurulum

### Yöntem 1 — tek satır (en kolayı)

Başlat menüsüne **PowerShell** yaz, aç, aşağıdaki satırı yapıştır ve Enter'a bas:

```powershell
irm https://raw.githubusercontent.com/sykait/SyHost/main/install.ps1 | iex
```

Bu komut SyHost'u indirir ve kurulumu başlatır. Aynı komut ileride **güncellemek** için de kullanılır
(sunucuların ve ayarların silinmez).

### Yöntem 2 — zip ile

1. Bu sayfada yeşil **Code** düğmesine bas → **Download ZIP**.
2. Zip'i bir klasöre çıkar (ör. `Belgeler\SyHost`).
3. **`Setup.bat`**'a çift tıkla.
   - Windows "bilgisayarınız korundu" derse: **Ek bilgi → Yine de çalıştır**.

### Kurulum ne yapar?

| Adım | Ne olur |
|---|---|
| 0 | Dil seçersin (English / Türkçe / 日本語) |
| 1 | Windows ve winget kontrol edilir |
| 2 | Java 21 yoksa kurulur |
| 3 | İstersen playit.gg kurulur ve tarayıcıdan hesabına bağlanır |
| 4 | Cascadia Mono yazı tipi kurulur (animasyonların düzgün görünmesi için) |
| 5 | Masaüstüne ve Başlat menüsüne **SyHost** kısayolu eklenir |

Windows bir veya iki kez izin isteyebilir, **Evet** demen yeterli.

---

## 🎮 İlk sunucunu kur

1. **SyHost**'u aç.
2. **Yeni sunucu ekle**'yi seç (ya da `+` tuşuna bas).
3. [Modrinth](https://modrinth.com/modpacks)'ten indirdiğin `.mrpack` dosyasını seç.
4. Sunucuya bir isim ver → (pakette dünya varsa) dünyayı seç → **Enter** ile kur.
5. Kurulum bitince **Enter** → sunucu açılır. Üstteki şerit **SUNUCU AÇIK** olunca hazırdır.

## 👥 Arkadaşlarını davet et

1. Sunucu ekranında `kopyala` yaz, Enter → adres panoya kopyalanır.
2. Discord'dan arkadaşına yapıştır.
3. Arkadaşın aynı modpack'i (aynı sürüm!) Modrinth App ya da Prism Launcher ile açar →
   **Çok Oyunculu → Sunucu Ekle** → adresi yapıştırır.

---

## ⌨️ Kısayollar

| Tuş | Ne yapar |
|---|---|
| **F1** | Nasıl kullanılır (yardım) |
| **F2** | Gizle — sunucu arka planda çalışmaya devam eder |
| **F3** | Performans paketi seç |
| **F4** | Küçük / büyük mod |
| **F5** | Sade / detaylı konsol |
| **F6** | Küçük modu her zaman üstte tut |
| **F10** | Kapat (dünya kaydedilir) |
| **L** | Dili değiştir (ana menü) |
| **Ctrl+Alt+K** | Küçük / büyük mod — her yerden, oyundayken bile |
| **Ctrl+Alt+G** | Gizle / göster — her yerden |

## 💬 Komutlar

| Komut | Ne yapar |
|---|---|
| `baslat` / `durdur` / `yeniden` | Sunucuyu aç / kapat / yeniden başlat |
| `paket normal` | Performans paketini değiştir (`dusuk`, `normal`, `yuksek`) |
| `yedek` | Dünyanın yedeğini al |
| `oyuncular` | Kimler oyunda |
| `kopyala` | Arkadaş adresini panoya kopyala |
| `klasor` | Sunucu klasörünü aç |
| `menu` / `cikis` | Ana menüye dön / SyHost'u kapat |

Bunların dışında yazdığın her şey doğrudan Minecraft'a gider: `op isim`, `kick isim`, `say merhaba`, `time set day`...
(İngilizce komutlar da çalışır: `start`, `stop`, `backup`...)

---

## ❓ Sık sorulanlar

**playit zorunlu mu?**
Hayır. Kurulumda "hayır" dersen sunucuya bu bilgisayardan (`localhost`) ve aynı evdeki ağdan girilebilir.
İnternetten arkadaşların bağlanacaksa ve internetin CGNAT arkasındaysa (Türkiye'de çok yaygın) playit gerekir.

**Bilgisayarımı yavaşlatır mı?**
SyHost'un kendisi çok hafiftir. Sunucunun kullanacağı RAM'i ve çekirdekleri paketlerden (F3) sen seçersin.

**Ayarlarım ve sunucularım nerede?**
- Ayarlar ve sunucu listesi: `%LOCALAPPDATA%\SyHost` (program klasöründe değil)
- Sunucular: varsayılan olarak `%USERPROFILE%\SyHost Sunuculari`
- Yedekler: her sunucunun kendi `yedekler` klasöründe

**Mac / Linux?**
Şimdilik sadece Windows 10 ve 11.

---

## 📜 Lisans ve kredi

SyHost **kaynak görünür** bir projedir: kodu görebilir, indirebilir ve kişisel olarak kullanabilirsin.
**Bu projeyi kullanarak bir şey yapıp paylaşırsan kredi vermek zorunludur:**

> Bu proje **SyHost** (yapımcı: **sykait**) projesine dayanmaktadır — https://github.com/sykait/SyHost

Satış ve ticari kullanım yazılı izin olmadan yasaktır. Ayrıntılar: [LICENSE.md](LICENSE.md)

Minecraft, Mojang Studios'un ticari markasıdır. SyHost, Mojang veya Microsoft ile bağlantılı değildir.
