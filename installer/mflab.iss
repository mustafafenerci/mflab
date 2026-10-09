; MF Lab - Inno Setup betiği
; Derleme: iscc /DMyAppVersion=1.0.0 installer\mflab.iss
; Önce: flutter build windows --release

#ifndef MyAppVersion
  #define MyAppVersion "1.1.8"
#endif

#define MyAppName "MF Lab"
#define MyAppPublisher "Mustafa Fenerci"
#define MyAppURL "https://github.com/mustafafenerci/mflab"
#define MyAppExeName "mflab.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6D1C7A52-3F0B-4B8E-9A47-5E2C1F0A9B31}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\MF Lab
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=MFLab-Setup-v{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Güncelleme sırasında açık (tepsideki) MF Lab'ı kapatıp dosyaları güvenle değiştir.
CloseApplications=force
RestartApplications=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoTextVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Kurulum Programı (v{#MyAppVersion})
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstüne MF Lab kısayolu ekle"; GroupDescription: "Kısayollar:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "MF Lab'i şimdi başlat"; Flags: nowait skipifsilent
; Uygulama içinden yapılan güncelleme sessiz çalışır; bitince MF Lab'ı yeniden aç.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WizardSilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';

// MF Lab'ın bu kullanıcı için kullandığı çalışma klasörü (uygulama yazar).
function MFLabBaseDir(): String;
var
  S: AnsiString;
begin
  Result := '';
  if LoadStringFromFile(ExpandConstant('{userappdata}\MFLab\basedir.txt'), S) then
    Result := Trim(String(S));
end;

// Klasördeki tüm ders yığınlarını (docker compose) durdurur; RemoveVolumes ise veritabanlarını da siler.
procedure StopStacks(Base: String; RemoveVolumes: Boolean);
var
  CourseRec, StackRec: TFindRec;
  StackRoot, Compose, Args: String;
  Code: Integer;
begin
  if FindFirst(Base + '\*', CourseRec) then
  try
    repeat
      if ((CourseRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
         (CourseRec.Name <> '.') and (CourseRec.Name <> '..') then
      begin
        StackRoot := Base + '\' + CourseRec.Name + '\.stack';
        if FindFirst(StackRoot + '\*', StackRec) then
        try
          repeat
            Compose := StackRoot + '\' + StackRec.Name + '\compose.yml';
            if FileExists(Compose) then
            begin
              Args := '/c docker compose -f "' + Compose + '" down';
              if RemoveVolumes then
                Args := Args + ' -v';
              Exec(ExpandConstant('{cmd}'), Args, '', SW_HIDE, ewWaitUntilTerminated, Code);
            end;
          until not FindNext(StackRec);
        finally
          FindClose(StackRec);
        end;
      end;
    until not FindNext(CourseRec);
  finally
    FindClose(CourseRec);
  end;
end;

// Çalışma dosyalarını siler. Ortak kök (C:\MFLab) ise başka kullanıcıların klasörlerine dokunmaz.
procedure DeleteWorkspace(Base: String);
var
  Rec: TFindRec;
  Path: String;
begin
  if CompareText(Base, 'C:\MFLab') <> 0 then
  begin
    DelTree(Base, True, True, True);
    exit;
  end;
  if FindFirst(Base + '\*', Rec) then
  try
    repeat
      Path := Base + '\' + Rec.Name;
      if (Rec.Name = '.') or (Rec.Name = '..') then
        continue;
      if (Rec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
      begin
        // Başka kullanıcıların klasörlerinde kendi settings.json'ları vardır; onları koru.
        if not FileExists(Path + '\settings.json') then
          DelTree(Path, True, True, True);
      end
      else
        DeleteFile(Path);
    until not FindNext(Rec);
  finally
    FindClose(Rec);
  end;
  RemoveDir(Base);
end;

function InitializeUninstall(): Boolean;
var
  Code: Integer;
begin
  // Tepside gizli çalışıyor olabilir; dosyalar silinebilsin diye kapat.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#MyAppExeName} /F', '', SW_HIDE,
       ewWaitUntilTerminated, Code);
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Base: String;
  DeleteData: Boolean;
begin
  if CurUninstallStep <> usUninstall then
    exit;
  RegDeleteValue(HKEY_CURRENT_USER, RunKey, 'MF Lab');
  Base := MFLabBaseDir();
  if (Base = '') or (not DirExists(Base)) then
    exit;
  DeleteData := False;
  if not UninstallSilent then
    DeleteData := MsgBox('MF Lab kaldırılıyor. Çalışan ders servisleri (Docker konteynerleri) durdurulacak.' + #13#10#13#10 +
      'Projelerin, ödevlerin ve veritabanların da SİLİNSİN Mİ?' + #13#10 +
      'Klasör: ' + Base + #13#10#13#10 +
      'Evet: her şey kalıcı olarak silinir (geri alınamaz).' + #13#10 +
      'Hayır: dosyaların ve veritabanların korunur (önerilen).',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  StopStacks(Base, DeleteData);
  if DeleteData then
    DeleteWorkspace(Base);
end;
