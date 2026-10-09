# {{NAME}}

Bu proje MF Lab çalışma alanındaki `htdocs/{{NAME}}` klasöründe durur.

- **Tarayıcıda aç:** {{URL}}
- **phpMyAdmin:** {{PMA}}
- **Oluşturulma:** {{DATE}}
- **Portala dön:** `../` (ana sayfada tüm projelerin listelenir)

## 🧩 Ne yaptık?

- `htdocs` klasörünün içinde **{{NAME}}** adında bir alt klasör (proje) oluşturduk.
- İçine başlangıç dosyası olarak `index.php` ve bu `README.md` dosyasını koyduk.
- Tarayıcıda {{URL}} adresini açınca Apache, `index.php` dosyanı çalıştırır.
- Başka bir proje açmak istersen ana sayfadan (portal) yeni klasör ekleyebilirsin. Her proje kendi alt klasöründe durur, birbirini bozmaz.

## 🛠️ Nasıl kuruldu?

MF Lab bilgisayarına Apache, PHP ve MariaDB'yi **tek tek kurmaz**. Bunun yerine Docker'da 3 küçük "kutu" (konteyner) çalıştırır:

| Konteyner | Ne işe yarar? | Adres |
|---|---|---|
| `web` | Apache + PHP 8.3 + Composer. PHP kodunu çalıştırır. | {{URL}} |
| `db` | MariaDB veritabanı. Verilerini burada saklarsın. | sunucu adı: `db` |
| `phpmyadmin` | Veritabanını tarayıcıdan yönetirsin. | {{PMA}} |

Bilgisayarındaki `htdocs` klasörü, `web` konteynerinin içindeki `/var/www/html` klasörüne **bağlıdır**.
Yani VS Code'da `htdocs/{{NAME}}/index.php` dosyasını kaydedince, tarayıcıda sayfayı yenilemen yeterli — ekstra bir şey yapmana gerek yok.

## ✅ Nasıl olmalı?

Projen bir **alt klasörde** durur ve adresi proje adıyla biter: `{{URL}}`.
Tipik bir proje şöyle görünür:

```
htdocs/
├── index.php              ← MF Lab portalı (dokunma)
└── {{NAME}}/
    ├── index.php          ← projenin ana sayfası (zorunlu)
    ├── baglanti.php       ← veritabanı bağlantısı
    ├── style.css
    └── README.md          ← bu dosya
```

Bu yüzden kod yazarken şunlara dikkat et:

- Bağlantı ve dosya yollarını **göreli** yaz: `style.css`, `giris.php`, `img/logo.png`.
- Başında `/` olan yollar (`/style.css`, `/giris.php`) projeni değil **MF Lab portalını** gösterir. ❌ `href="/giris.php"` → ✅ `href="giris.php"`
- Yönlendirme: ❌ `header('Location: /giris.php');` → ✅ `header('Location: giris.php');`
- PHP'de dosya eklerken: ✅ `require __DIR__ . '/baglanti.php';`
- Bir üst klasöre (portala) dönmek için: `../`
- Laravel kullanıyorsan adres `{{URL}}public/` olur.
- Ana sayfan her zaman `index.php` (veya `index.html`) olmalı; yoksa tarayıcı klasörü açamaz.

## 🗄️ Veritabanı bağlantısı

| Alan | Değer |
|---|---|
| Sunucu (host) | `db`  (**localhost değil!** Çünkü PHP, `web` konteynerinin içinde çalışır; veritabanı ise başka bir konteynerdedir) |
| Kullanıcı | `root` |
| Şifre | `root` |
| Veritabanı | `mflab` |

```php
$pdo = new PDO('mysql:host=db;dbname=mflab;charset=utf8mb4', 'root', 'root');
```

Tüm projeler aynı `mflab` veritabanını paylaşır. Tabloların çakışmaması için projenin adını ön ek yap: `{{NAME}}_ogrenciler` gibi.

## 📦 Ödev teslimi

MF Lab uygulamasında **Yönet → Ödevi Paketle (.zip)** ile bu projeyi ve veritabanını tek dosyada Masaüstüne paketleyebilirsin.

## 📝 Notlarım

(Buraya projenle ilgili notlarını yazabilirsin.)
