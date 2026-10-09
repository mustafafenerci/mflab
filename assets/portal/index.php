<?php
// mflab-portal:2
// MF Lab - Öğrenci Çalışma Portalı. Bu dosya MF Lab'a aittir; yeni sürümde otomatik güncellenir.
// Kendi ana sayfanı yapmak istersen bu ilk satırdaki "mflab-portal" yazısını sil.

const README_TEMPLATE = <<<'MFREADME'
@@README_TEMPLATE@@
MFREADME;

function h($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

function baseUrl() {
    return 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
}

function pmaPort() {
    $map = @json_decode(@file_get_contents(__DIR__ . '/.mflab-ports.json'), true);
    return (is_array($map) && isset($map['6381'])) ? (int)$map['6381'] : 6381;
}

function renderReadme($name) {
    return str_replace(
        ['{{NAME}}', '{{URL}}', '{{PMA}}', '{{DATE}}'],
        [$name, baseUrl() . '/' . $name . '/', 'http://localhost:' . pmaPort(), date('d.m.Y H:i')],
        README_TEMPLATE
    );
}

/** Projenin öğrencinin koduna göre nasıl açılacağını bulur. */
function detectProject($dir) {
    if (is_file("$dir/public/index.php") && is_file("$dir/artisan")) {
        return ['type' => 'Laravel', 'entry' => 'public/', 'files' => [], 'openable' => true];
    }
    foreach (['index.php', 'index.html', 'index.htm'] as $idx) {
        if (is_file("$dir/$idx")) {
            return ['type' => $idx === 'index.php' ? 'PHP' : 'HTML', 'entry' => '', 'files' => [], 'openable' => true];
        }
    }
    $files = [];
    foreach (scandir($dir) as $f) {
        if ($f[0] === '.' || !is_file("$dir/$f")) continue;
        if (preg_match('/\.(php|html?)$/i', $f)) $files[] = $f;
    }
    if ($files) {
        return ['type' => 'index dosyası yok', 'entry' => '', 'files' => array_slice($files, 0, 6), 'openable' => false];
    }
    return ['type' => 'Boş klasör', 'entry' => '', 'files' => [], 'openable' => false];
}

/** README'nin ilk açıklayıcı satırı (başlık, tablo ve kod hariç). */
function readmeSummary($file) {
    $in = false;
    foreach (@file($file, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        $t = trim($line);
        if (strpos($t, '```') === 0) { $in = !$in; continue; }
        if ($in || $t === '' || $t[0] === '#' || $t[0] === '|' || $t[0] === '-' || $t[0] === '*') continue;
        return mb_strimwidth($t, 0, 110, '…');
    }
    return '';
}

/** Küçük, güvenli bir Markdown gösterici. */
function renderMarkdown($md) {
    $out = '';
    $inCode = false;
    $inList = false;
    $inTable = false;
    $inline = function ($s) {
        $s = h($s);
        $s = preg_replace('/`([^`]+)`/', '<code>$1</code>', $s);
        $s = preg_replace('/\*\*([^*]+)\*\*/', '<b>$1</b>', $s);
        return $s;
    };
    foreach (preg_split('/\r?\n/', $md) as $line) {
        if (strpos(trim($line), '```') === 0) {
            if ($inList) { $out .= '</ul>'; $inList = false; }
            $out .= $inCode ? '</code></pre>' : '<pre><code>';
            $inCode = !$inCode;
            continue;
        }
        if ($inCode) { $out .= h($line) . "\n"; continue; }
        $t = trim($line);
        if ($inList && !preg_match('/^[-*] /', $t)) { $out .= '</ul>'; $inList = false; }
        if ($inTable && ($t === '' || $t[0] !== '|')) { $out .= '</table>'; $inTable = false; }
        if ($t === '') continue;
        if (preg_match('/^(#{1,3})\s+(.*)$/', $t, $m)) {
            $n = strlen($m[1]) + 1;
            $out .= "<h$n>" . $inline($m[2]) . "</h$n>";
        } elseif (preg_match('/^[-*] (.*)$/', $t, $m)) {
            if (!$inList) { $out .= '<ul>'; $inList = true; }
            $out .= '<li>' . $inline($m[1]) . '</li>';
        } elseif ($t[0] === '|') {
            if (preg_match('/^\|[\s:|-]+\|$/', $t)) continue;
            if (!$inTable) { $out .= '<table>'; $inTable = true; }
            $cells = array_map('trim', explode('|', trim($t, '|')));
            $out .= '<tr>' . implode('', array_map(fn($c) => '<td>' . $inline($c) . '</td>', $cells)) . '</tr>';
        } else {
            $out .= '<p>' . $inline($t) . '</p>';
        }
    }
    if ($inList) $out .= '</ul>';
    if ($inTable) $out .= '</table>';
    if ($inCode) $out .= '</code></pre>';
    return $out;
}

$dbOk = false;
$dbErr = '';
try {
    new PDO('mysql:host=db;dbname=mflab;charset=utf8mb4', 'root', 'root', [PDO::ATTR_TIMEOUT => 2]);
    $dbOk = true;
} catch (Exception $e) {
    $dbErr = $e->getMessage();
}

$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['folder_name'])) {
    $name = preg_replace('/[^a-zA-Z0-9_\-]/', '_', trim($_POST['folder_name']));
    if ($name !== '' && !is_dir($name)) {
        mkdir($name, 0777, true);
        file_put_contents("$name/index.php", "<?php\n// Proje: $name\n?>\n<!DOCTYPE html>\n<html lang=\"tr\">\n<head>\n  <meta charset=\"UTF-8\">\n  <title>$name</title>\n</head>\n<body>\n  <h1>🚀 $name çalışıyor!</h1>\n  <p>PHP sürümü: <?= phpversion() ?></p>\n  <p><a href=\"../\">← MF Lab Portalına Dön</a></p>\n</body>\n</html>\n");
        file_put_contents("$name/README.md", renderReadme($name));
        header("Location: $name/");
        exit;
    }
    $msg = 'Klasör zaten mevcut veya geçersiz isim!';
}

// README'si eksik olan her projeye otomatik ekle.
$projects = [];
foreach (scandir('.') as $item) {
    if ($item[0] === '.' || !is_dir($item)) continue;
    $readme = "$item/README.md";
    if (!is_file($readme)) @file_put_contents($readme, renderReadme($item));
    $projects[] = detectProject($item) + [
        'name' => $item,
        'mtime' => filemtime($item),
        'summary' => readmeSummary($readme),
    ];
}
usort($projects, fn($a, $b) => $b['mtime'] <=> $a['mtime']);

// README görüntüleme
$readmeName = $_GET['readme'] ?? '';
$readmeHtml = null;
if ($readmeName !== '' && preg_match('/^[a-zA-Z0-9_\-]+$/', $readmeName) && is_file("$readmeName/README.md")) {
    $readmeHtml = renderMarkdown(file_get_contents("$readmeName/README.md"));
}
$pma = pmaPort();
?>
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MF Lab - Öğrenci Portalı</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; padding: 30px 20px; line-height: 1.5; }
    .container { max-width: 960px; margin: 0 auto; }
    header { background: linear-gradient(135deg, #1e293b, #334155); padding: 28px; border-radius: 16px; border: 1px solid #475569; margin-bottom: 24px; }
    h1 { font-size: 26px; color: #38bdf8; margin-bottom: 8px; }
    .status-bar { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 14px; font-size: 13px; }
    .badge { padding: 4px 10px; border-radius: 8px; background: #1e293b; border: 1px solid #475569; }
    .badge.success { border-color: #10b981; color: #34d399; }
    .badge.warn { border-color: #f59e0b; color: #fbbf24; }
    .badge a { color: inherit; text-decoration: none; font-weight: 600; }
    .create-card { background: #1e293b; border: 1px solid #334155; padding: 20px; border-radius: 14px; margin-bottom: 24px; }
    .create-card h2 { font-size: 17px; margin-bottom: 12px; color: #94a3b8; }
    .form-row { display: flex; gap: 10px; }
    input[type="text"] { flex: 1; padding: 10px 14px; border-radius: 8px; border: 1px solid #475569; background: #0f172a; color: #fff; font-size: 14px; }
    button { background: #0284c7; color: #fff; border: none; padding: 10px 18px; border-radius: 8px; font-weight: 600; cursor: pointer; }
    button:hover { background: #0369a1; }
    .section-title { font-size: 18px; margin-bottom: 14px; color: #cbd5e1; display: flex; justify-content: space-between; align-items: center; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; }
    .card { background: #1e293b; border: 1px solid #334155; padding: 18px; border-radius: 12px; display: flex; flex-direction: column; justify-content: space-between; gap: 14px; }
    .card:hover { border-color: #38bdf8; }
    .name { font-size: 17px; font-weight: 600; color: #f1f5f9; word-break: break-all; }
    .meta { font-size: 12px; color: #64748b; margin-top: 2px; }
    .tag { display: inline-block; font-size: 11px; font-weight: 700; padding: 1px 8px; border-radius: 10px; background: #334155; color: #38bdf8; margin-left: 6px; }
    .tag.laravel { color: #f43f5e; }
    .tag.warn { color: #fbbf24; }
    .summary { font-size: 13px; color: #94a3b8; margin-top: 8px; }
    .files { font-size: 12px; margin-top: 8px; color: #94a3b8; }
    .files a { color: #38bdf8; margin-right: 8px; }
    .actions { display: flex; gap: 8px; flex-wrap: wrap; }
    .btn { display: inline-block; text-align: center; background: #334155; color: #38bdf8; text-decoration: none; padding: 7px 14px; border-radius: 8px; font-size: 13px; font-weight: 600; border: 1px solid #475569; }
    .btn:hover { background: #38bdf8; color: #0f172a; }
    .btn.off { opacity: .45; pointer-events: none; }
    .empty-state { text-align: center; padding: 40px; background: #1e293b; border-radius: 12px; border: 1px dashed #475569; color: #94a3b8; }
    .doc { background: #1e293b; border: 1px solid #334155; border-radius: 14px; padding: 24px 28px; }
    .doc h2, .doc h3, .doc h4 { color: #38bdf8; margin: 18px 0 8px; }
    .doc h2:first-child { margin-top: 0; }
    .doc p, .doc li { color: #cbd5e1; font-size: 14px; margin: 6px 0; }
    .doc ul { padding-left: 22px; }
    .doc code { background: #0f172a; padding: 1px 6px; border-radius: 5px; color: #7ee787; }
    .doc pre { background: #0f172a; padding: 12px; border-radius: 8px; overflow-x: auto; margin: 10px 0; }
    .doc pre code { padding: 0; }
    .doc table { border-collapse: collapse; margin: 10px 0; }
    .doc td { border: 1px solid #334155; padding: 6px 12px; font-size: 14px; color: #cbd5e1; }
  </style>
</head>
<body>
<div class="container">
  <header>
    <h1>🎓 MF Lab Öğrenci Portalı</h1>
    <p style="color: #94a3b8; font-size: 14px;">Çalışma alanındaki projelerin ve haftalık ödevlerin aşağıda listelenir. Her projenin kendi alt klasörü ve README'si vardır.</p>
    <div class="status-bar">
      <span class="badge success">✔ PHP <?= h(phpversion()) ?></span>
      <span class="badge <?= $dbOk ? 'success' : 'warn' ?>"><?= $dbOk ? '✔ MariaDB bağlı' : '⚠️ MariaDB: ' . h($dbErr) ?></span>
      <span class="badge"><a href="http://localhost:<?= $pma ?>" target="_blank">🐬 phpMyAdmin aç (<?= $pma ?>) ↗</a></span>
      <span class="badge">📁 htdocs</span>
    </div>
  </header>

<?php if ($readmeHtml !== null): ?>
  <div class="section-title">
    <span>📖 <?= h($readmeName) ?> / README.md</span>
    <a class="btn" href="./">← Projelerime dön</a>
  </div>
  <div class="doc"><?= $readmeHtml ?></div>
<?php else: ?>
  <details class="create-card" <?= empty($projects) ? 'open' : '' ?>>
    <summary style="cursor:pointer; font-weight:600; color:#94a3b8;">ℹ️ Bu ortam nasıl çalışıyor? (ne yaptık, nasıl kuruldu, nasıl olmalı)</summary>
    <div class="doc" style="border:0; padding:12px 0 0;">
      <h3>Ne yaptık?</h3>
      <p>Bilgisayarında bir web sitesi çalıştırabilmen için Apache (web sunucusu), PHP ve MariaDB (veritabanı) gerekir. MF Lab bunları Docker ile senin için hazırladı; bilgisayarını kirletmez, istediğinde kaldırabilirsin.</p>
      <h3>Nasıl kuruldu?</h3>
      <ul>
        <li><b>web</b> konteyneri: Apache + PHP. Şu an gördüğün sayfa bunun içinden geliyor.</li>
        <li><b>db</b> konteyneri: MariaDB. PHP'den bağlanırken sunucu adı <code>db</code> olur (localhost değil).</li>
        <li><b>phpmyadmin</b> konteyneri: veritabanını tarayıcıdan yönetmek için → <a href="http://localhost:<?= $pma ?>" target="_blank" style="color:#38bdf8;">localhost:<?= $pma ?></a></li>
        <li>Bilgisayarındaki <code>htdocs</code> klasörü, web konteynerinin içindeki <code>/var/www/html</code> klasörüne bağlıdır. VS Code'da kaydettiğin dosyayı tarayıcıda yenilemen yeterli.</li>
      </ul>
      <h3>Nasıl olmalı?</h3>
      <ul>
        <li>Her hafta / ödev için aşağıdan <b>ayrı bir proje klasörü</b> ekle. Proje adresi proje adıyla biter: <code><?= h(baseUrl()) ?>/hafta1/</code></li>
        <li>Projenin ana dosyası <code>index.php</code> (veya <code>index.html</code>) olmalı.</li>
        <li>Yolları göreli yaz: <code>style.css</code>, <code>giris.php</code>. Başına <code>/</code> koyarsan projen değil bu portal açılır.</li>
        <li>Her projenin içinde bir <b>README.md</b> vardır: adresi, veritabanı bilgisini ve bu kuralları orada da bulursun. 📖 düğmesiyle buradan da okuyabilirsin.</li>
      </ul>
    </div>
  </details>

  <div class="create-card">
    <h2>➕ Yeni hafta / proje klasörü ekle</h2>
    <form method="POST" class="form-row">
      <input type="text" name="folder_name" placeholder="Örn: hafta1_giris veya odev2" required pattern="[a-zA-Z0-9_\-]+" title="Boşluksuz harf, rakam ve alt çizgi kullanın">
      <button type="submit">Oluştur ve aç</button>
    </form>
    <?php if ($msg): ?><p style="color:#ef4444; font-size:13px; margin-top:8px;"><?= h($msg) ?></p><?php endif; ?>
  </div>

  <div class="section-title">
    <span>📁 Projelerin (<?= count($projects) ?>)</span>
    <span style="font-size: 12px; color: #64748b;">Projeyi açmak için tıkla</span>
  </div>

  <?php if (empty($projects)): ?>
    <div class="empty-state">
      <p style="font-size: 16px; margin-bottom: 8px;">Henüz bir proje veya hafta klasörü eklenmedi.</p>
      <p style="font-size: 13px;">Yukarıdaki alana <b>hafta1</b> gibi bir isim yazarak ilk projeni başlatabilirsin.</p>
    </div>
  <?php else: ?>
    <div class="grid">
      <?php foreach ($projects as $p): $n = rawurlencode($p['name']); ?>
        <div class="card">
          <div>
            <div class="name">📁 <?= h($p['name']) ?><span class="tag <?= $p['type'] === 'Laravel' ? 'laravel' : ($p['openable'] ? '' : 'warn') ?>"><?= h($p['type']) ?></span></div>
            <div class="meta">Güncelleme: <?= date('d.m.Y H:i', $p['mtime']) ?> · /<?= h($p['name']) ?>/<?= h($p['entry']) ?></div>
            <?php if ($p['summary']): ?><div class="summary"><?= h($p['summary']) ?></div><?php endif; ?>
            <?php if ($p['files']): ?>
              <div class="files">Dosyalar:
                <?php foreach ($p['files'] as $f): ?><a href="<?= $n ?>/<?= rawurlencode($f) ?>"><?= h($f) ?></a><?php endforeach; ?>
              </div>
            <?php endif; ?>
          </div>
          <div class="actions">
            <a class="btn <?= $p['openable'] ? '' : 'off' ?>" href="<?= $n ?>/<?= h($p['entry']) ?>">Projeyi çalıştır ↗</a>
            <a class="btn" href="?readme=<?= $n ?>">📖 README</a>
          </div>
        </div>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>
<?php endif; ?>
</div>
</body>
</html>
