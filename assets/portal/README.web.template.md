# {{NAME}}

Bu proje MF Lab çalışma alanındaki `proje/{{NAME}}` klasöründe durur.

- **Oluşturulma:** {{DATE}}
- **Klasör:** `{{PATH}}`

## 🧩 Ne yaptık?

- `proje` klasörünün içinde **{{NAME}}** adında ayrı bir klasör (proje) oluşturduk.
- İçine başlangıç için üç dosya koyduk: `index.html` (sayfa), `style.css` (görünüm) ve `script.js` (davranış).
- Her ödev veya hafta için ayrı proje açarsan dosyaların birbirine karışmaz.

## 🛠️ Nasıl çalışıyor?

Web sayfaları için sunucu kurmana gerek yok; tarayıcı HTML, CSS ve JavaScript'i kendisi çalıştırır.
Sayfanı iki yoldan görebilirsin:

| Yol | Nasıl? |
|---|---|
| **MF Lab canlı önizleme** | MF Lab → Projelerim → projenin yanındaki 🌐 **Canlı önizle** düğmesi. Tarayıcıda açılır; dosyayı kaydedince sayfa kendiliğinden yenilenir. |
| **VS Code içinde (Live Preview)** | VS Code'da `index.html` dosyasını aç, sağ üstteki 🔍 **Show Preview** (Önizlemeyi Göster) simgesine tıkla. Sayfa VS Code'un yanında açılır. |

## ✅ Nasıl olmalı?

```
proje/
└── {{NAME}}/
    ├── index.html     ← ana sayfa (adı tam olarak index.html olmalı)
    ├── style.css
    ├── script.js
    ├── img/           ← resimlerini buraya koy
    └── README.md      ← bu dosya
```

- Ana sayfanın adı **index.html** olmalı; önizleme ilk olarak bu dosyayı açar.
- Bağlantıları **göreli** yaz: `href="style.css"`, `src="img/logo.png"`, `href="iletisim.html"`.
- Başına `/` koyma veya `C:\...` gibi tam yol yazma; projeyi başka bilgisayara taşıyınca bozulur.
- Dosya ve klasör adlarında Türkçe karakter ve boşluk kullanma: `iletisim.html` ✅, `İletişim Sayfası.html` ❌

## 📝 Notlarım

(Buraya projenle ilgili notlarını yazabilirsin.)
