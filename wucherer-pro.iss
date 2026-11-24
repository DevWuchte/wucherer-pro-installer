; Wucherer-Pro Installer: installiert RustDesk still, setzt Server + zufälliges Dauerpasswort + Auto-Update.
; rustdesk.exe (offizieller Windows-Installer) muss neben dieser Datei liegen (macht die GitHub Action).
; Revalia-Regular.ttf (Google Font, für den "Wucherer.Pro"-Schriftzug) ebenfalls (macht die GitHub Action).

[Setup]
AppId={{6F1B7C3A-2D4E-4B8A-9E5C-1A7D3F0B9C42}
AppName=Wucherer.Pro Remote Support
AppVersion=1.0
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=Wucherer-Pro
Compression=lzma2
SolidCompression=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
WizardStyle=modern

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
SetupWindowTitle=Wucherer.Pro Remote Support – %1

[Files]
Source: "rustdesk.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "Revalia-Regular.ttf"; DestDir: "{tmp}"; Flags: dontcopy

[Code]
const
  { In RustDesk: Einstellungen > Netzwerk > "Server-Konfiguration exportieren" }
  ServerConfig = '\==Qfi0DMQFGV5ZTQJVVM1lWO01keaVUcZNWVthFaVVTVX5GWNFWT0QTZhRUdUlnNiojI5V2aiwiIiojIpBXYiwiIiojI5FGblJnIsIybyBnLyVmclh2Y1dlLlR3btVmUiojI0N3boJye';
  ApiBaseUrl = 'https://admin.wucherer.pro';
  FR_PRIVATE = 16;

var
  FontFilePath: String;
  InfoPage: TWizardPage;
  ChkInstall: TNewCheckBox;
  ChkUnattended: TNewCheckBox;
  InstallSummary: String;
  InstallSucceeded: Boolean;

function AddFontResourceExW(lpszFilename: String; fl: Longint; pdv: Longint): Longint;
  external 'AddFontResourceExW@gdi32.dll stdcall';
function RemoveFontResourceExW(lpszFilename: String; fl: Longint; pdv: Longint): Longint;
  external 'RemoveFontResourceExW@gdi32.dll stdcall';

{ Kryptografisch sicherer Zufall von Windows (RtlGenRandom) }
function SystemFunction036(var Buffer: Cardinal; BufferLength: Cardinal): Integer;
  external 'SystemFunction036@advapi32.dll stdcall';

function SecureRandom(Range: Integer): Integer;
var
  Buf: Cardinal;
begin
  Buf := 0;
  if (SystemFunction036(Buf, 4) and $FF) = 0 then
    RaiseException('Zufallsgenerator nicht verfuegbar');
  { Die geringe Modulo-Verzerrung ist bei den hier verwendeten Bereichen klein. }
  Result := Integer(Buf mod Cardinal(Range));
end;

function RunHidden(const FileName, Params: String): Integer;
var
  RC: Integer;
begin
  if not Exec(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, RC) then
    RC := -1;
  Result := RC;
end;

procedure ToggleChkInstall(Sender: TObject);
begin
  ChkInstall.Checked := not ChkInstall.Checked;
end;

procedure ToggleChkUnattended(Sender: TObject);
begin
  ChkUnattended.Checked := not ChkUnattended.Checked;
end;

function JsonEscape(const Value: String): String;
var
  i: Integer;
  c: String;
begin
  Result := '';
  for i := 1 to Length(Value) do
  begin
    c := Value[i];
    if c = '\' then Result := Result + '\\'
    else if c = '"' then Result := Result + '\"'
    else if c = #13 then Result := Result + '\r'
    else if c = #10 then Result := Result + '\n'
    else Result := Result + c;
  end;
end;

function MakePassword: String;
var
  i: Integer;
  letters, digits: String;
begin
  letters := 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  digits := '23456789';
  Result := letters[SecureRandom(Length(letters)) + 1] + digits[SecureRandom(Length(digits)) + 1];
  for i := 1 to 18 do
  begin
    if SecureRandom(2) = 0 then Result := Result + letters[SecureRandom(Length(letters)) + 1]
    else Result := Result + digits[SecureRandom(Length(digits)) + 1];
  end;
end;

function Hex32(Value: Cardinal): String;
var
  I, Digit: Integer;
  HexDigits: String;
begin
  HexDigits := '0123456789abcdef';
  Result := '';
  for I := 1 to 8 do
  begin
    Digit := Integer(Value mod 16);
    Result := HexDigits[Digit + 1] + Result;
    Value := Value div 16;
  end;
end;

function MakeDeviceKey: String;
var
  I: Integer;
  Buf: Cardinal;
begin
  Result := '';
  for I := 1 to 8 do
  begin
    Buf := 0;
    if (SystemFunction036(Buf, 4) and $FF) = 0 then
      RaiseException('Zufallsgenerator nicht verfuegbar');
    Result := Result + Hex32(Buf);
  end;
end;

function GetOrCreateDeviceKey: String;
begin
  if not RegQueryStringValue(HKLM64, 'Software\Wucherer.Pro', 'DeviceKey', Result) then
  begin
    Result := MakeDeviceKey();
    if not RegWriteStringValue(HKLM64, 'Software\Wucherer.Pro', 'DeviceKey', Result) then
      RaiseException('Geraeteschluessel konnte nicht gespeichert werden');
  end;
end;

function GetEnrollmentToken: String;
var
  SourceName, Prefix: String;
  I: Integer;
begin
  SourceName := ExtractFileName(ExpandConstant('{srcexe}'));
  Prefix := 'Wucherer.Pro-Client-';
  if Pos(Prefix, SourceName) <> 1 then Prefix := 'Wucherer-Pro-';
  if (Pos(Prefix, SourceName) = 1) and (ExtractFileExt(SourceName) = '.exe') then
    Result := Copy(SourceName, Length(Prefix) + 1, Length(SourceName) - Length(Prefix) - Length('.exe'))
  else
    Result := '';
  { Browser-downloads may add " (1)" when the same file is downloaded again. }
  for I := 1 to Length(Result) do
    if not (((Result[I] >= 'A') and (Result[I] <= 'Z')) or ((Result[I] >= 'a') and (Result[I] <= 'z')) or
      ((Result[I] >= '0') and (Result[I] <= '9')) or (Result[I] = '-') or (Result[I] = '_')) then
    begin
      Result := Copy(Result, 1, I - 1);
      Break;
    end;
end;

function IsValidEnrollmentToken(const Token: String): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := (Length(Token) >= 40) and (Length(Token) <= 60);
  if not Result then Exit;
  for I := 1 to Length(Token) do
  begin
    C := Token[I];
    if not (((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
      ((C >= '0') and (C <= '9')) or (C = '-') or (C = '_')) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function InitializeSetup(): Boolean;
var
  Token: String;
begin
  Token := GetEnrollmentToken();
  Result := IsValidEnrollmentToken(Token);
  if not Result then
    MsgBox('Dieser Installer kann nur über deinen persönlichen Einladungslink gestartet werden. Öffne bitte den Link aus der E-Mail und lade den Installer dort herunter.', mbError, MB_OK);
end;

function RegisterDevice(const Token, DeviceId, DeviceName, DeviceKey, Password: String; var ErrorMessage: String): Boolean;
var
  Request: Variant;
  Payload: String;
begin
  Result := False;
  ErrorMessage := '';
  if not IsValidEnrollmentToken(Token) then begin ErrorMessage := 'Der persönliche Installationslink ist ungültig oder abgelaufen.'; Exit; end;
  if (DeviceId = '') or (DeviceId = '(nicht lesbar)') then begin ErrorMessage := 'Die RustDesk-ID konnte nach der Installation nicht ausgelesen werden.'; Exit; end;
  Payload := '{"enrollmentToken":"' + JsonEscape(Token) + '","rustdeskId":"' + JsonEscape(DeviceId) + '","deviceKey":"' + JsonEscape(DeviceKey) + '","name":"' + JsonEscape(DeviceName) + '","platform":"Windows","publicKey":null,"credential":"' + JsonEscape(Password) + '"}';
  try
    Request := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Request.SetTimeouts(10000, 10000, 30000, 30000);
    Request.Open('POST', ApiBaseUrl + '/v1/devices/register', False);
    Request.SetRequestHeader('Content-Type', 'application/json');
    Request.Send(Payload);
    Result := (Request.Status = 200) or (Request.Status = 201);
    if not Result then ErrorMessage := 'Die Geräteanmeldung wurde vom Server abgelehnt (' + IntToStr(Request.Status) + ').';
  except
    ErrorMessage := 'Der Server konnte nicht erreicht werden.';
  end;
end;

procedure InitializeWizard;
var
  TitleLbl, BodyLbl, LblInstall, LblUnattended: TNewStaticText;
  Margin, IndentLeft: Integer;
begin
  { Schriftart (Revalia) nur für diesen Installer laden, nicht systemweit installieren.
    FR_PRIVATE = nur für diesen Prozess sichtbar, wird beim Beenden automatisch entfernt. }
  ExtractTemporaryFile('Revalia-Regular.ttf');
  FontFilePath := ExpandConstant('{tmp}\Revalia-Regular.ttf');
  AddFontResourceExW(FontFilePath, FR_PRIVATE, 0);

  InfoPage := CreateCustomPage(wpWelcome, 'Wucherer.Pro Remote Support',
    'Bitte bestätigen Sie die folgenden Punkte, um die Einrichtung fortzusetzen.');

  { ScaleX/ScaleY: an die Windows-Skalierung (100%/125%/150% …) anpassen,
    sonst wirken die Kästchen bei höherer Skalierung abgeschnitten. }
  Margin := ScaleX(4);
  IndentLeft := Margin + ScaleX(28);

  TitleLbl := TNewStaticText.Create(InfoPage);
  TitleLbl.Parent := InfoPage.Surface;
  TitleLbl.AutoSize := True;
  TitleLbl.Left := Margin;
  TitleLbl.Top := 0;
  TitleLbl.Font.Name := 'Revalia';
  TitleLbl.Font.Size := 26;
  TitleLbl.Caption := 'Wucherer.Pro';

  BodyLbl := TNewStaticText.Create(InfoPage);
  BodyLbl.Parent := InfoPage.Surface;
  BodyLbl.Left := Margin;
  BodyLbl.Top := TitleLbl.Top + TitleLbl.Height + ScaleY(18);
  BodyLbl.Width := InfoPage.SurfaceWidth - Margin;
  BodyLbl.WordWrap := True;
  BodyLbl.Caption :=
    'Wucherer.Pro Remote Support richtet Ihren gesicherten Fernwartungszugang ' +
    'vollautomatisch ein. Nach Abschluss arbeitet die Software dauerhaft im ' +
    'Hintergrund – eine weitere Einrichtung durch Sie ist nicht erforderlich.';
  BodyLbl.AdjustHeight;

  ChkInstall := TNewCheckBox.Create(InfoPage);
  ChkInstall.Parent := InfoPage.Surface;
  ChkInstall.Caption := '';
  ChkInstall.Left := Margin;
  ChkInstall.Top := BodyLbl.Top + BodyLbl.Height + ScaleY(22);
  ChkInstall.Width := ScaleX(24);
  ChkInstall.Height := ScaleY(24);

  LblInstall := TNewStaticText.Create(InfoPage);
  LblInstall.Parent := InfoPage.Surface;
  LblInstall.Left := IndentLeft;
  LblInstall.Top := ChkInstall.Top;
  LblInstall.Width := InfoPage.SurfaceWidth - IndentLeft;
  LblInstall.WordWrap := True;
  LblInstall.OnClick := @ToggleChkInstall;
  LblInstall.Caption :=
    'Ich bestätige, dass Wucherer.Pro Remote Support installiert wird, dauerhaft im ' +
    'Hintergrund läuft und keine weitere Konfiguration durch mich erfordert.';
  LblInstall.AdjustHeight;

  ChkUnattended := TNewCheckBox.Create(InfoPage);
  ChkUnattended.Parent := InfoPage.Surface;
  ChkUnattended.Caption := '';
  ChkUnattended.Left := Margin;
  ChkUnattended.Top := LblInstall.Top + LblInstall.Height + ScaleY(18);
  ChkUnattended.Width := ScaleX(24);
  ChkUnattended.Height := ScaleY(24);

  LblUnattended := TNewStaticText.Create(InfoPage);
  LblUnattended.Parent := InfoPage.Surface;
  LblUnattended.Left := IndentLeft;
  LblUnattended.Top := ChkUnattended.Top;
  LblUnattended.Width := InfoPage.SurfaceWidth - IndentLeft;
  LblUnattended.WordWrap := True;
  LblUnattended.OnClick := @ToggleChkUnattended;
  LblUnattended.Caption :=
    'Ich bin damit einverstanden, dass Wucherer.Pro diesen PC für das besprochene ' +
    'Anliegen fernwartet. Mir ist bekannt, dass ein Zugriff mit dem eingerichteten ' +
    'Zugangspasswort auch möglich ist, wenn gerade niemand am PC sitzt.';
  LblUnattended.AdjustHeight;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (InfoPage <> nil) and (CurPageID = InfoPage.ID) then
  begin
    if not (ChkInstall.Checked and ChkUnattended.Checked) then
    begin
      MsgBox('Bitte bestätigen Sie beide Punkte, um mit der Einrichtung fortzufahren.',
        mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure DeinitializeSetup;
begin
  if FontFilePath <> '' then
    RemoveFontResourceExW(FontFilePath, FR_PRIVATE, 0);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  i: Integer;
  Exe, Pw, Id, IdFile, Token, HostName, DeviceKey, RegistrationError: String;
  Registered: Boolean;
  S: AnsiString;
begin
  if CurStep <> ssPostInstall then
    Exit;

  InstallSummary := '';
  InstallSucceeded := False;

  Exe := ExpandConstant('{commonpf64}\RustDesk\rustdesk.exe');
  Pw := MakePassword;
  Token := GetEnrollmentToken;
  HostName := GetEnv('COMPUTERNAME');
  if HostName = '' then HostName := 'Windows-Gerät';

  { 1. Still installieren (als Dienst) }
  RunHidden(ExpandConstant('{tmp}\rustdesk.exe'), '--silent-install');
  for i := 1 to 30 do
  begin
    if FileExists(Exe) then
      Break;
    Sleep(2000);
  end;
  Sleep(10000);

  { Desktop-Verknüpfung entfernen, die --silent-install automatisch anlegt }
  DeleteFile(ExpandConstant('{commondesktop}\RustDesk.lnk'));
  DeleteFile(ExpandConstant('{userdesktop}\RustDesk.lnk'));

  { 2. Server-Konfiguration, Dauerpasswort und Einstellungen setzen }
  RunHidden(Exe, '--config "' + ServerConfig + '"');
  RunHidden(Exe, '--password ' + Pw);
  RunHidden(Exe, '--option allow-auto-update Y');
  RunHidden(Exe, '--option verification-method use-permanent-password');
  RunHidden(Exe, '--option approve-mode password');
  RunHidden(Exe, '--option allow-remote-config-modification N');
  RunHidden(Exe, '--option enable-keyboard Y');
  RunHidden(Exe, '--option enable-clipboard Y');
  RunHidden(Exe, '--option enable-file-transfer Y');
  { Ungetestet: ob sich das Verbindungsfenster so verstecken lässt, ist unklar.
    Diese Option gehört normalerweise zum kostenpflichtigen Custom Client Generator. }
  RunHidden(Exe, '--option allow-hide-cm N');

  { 3. Dienst neu starten, damit die Konfiguration greift }
  RunHidden(ExpandConstant('{sys}\net.exe'), 'stop RustDesk');
  Sleep(3000);
  RunHidden(ExpandConstant('{sys}\net.exe'), 'start RustDesk');
  Sleep(8000);

  { 4. ID auslesen (ohne "more", das sonst hängen bleiben kann) }
  IdFile := ExpandConstant('{tmp}\rid.txt');
  RunHidden(ExpandConstant('{cmd}'), '/c ""' + Exe + '" --get-id > "' + IdFile + '" 2>&1"');
  if LoadStringFromFile(IdFile, S) then
    Id := Trim(String(S))
  else
    Id := '(nicht lesbar)';

  { 5. Einladung einlösen und Zugangsdaten an die Admin-API melden. }
  if (Id = '') or (Id = '(nicht lesbar)') then
  begin
    Registered := False;
    RegistrationError := 'Die RustDesk-ID konnte nach der Installation nicht ausgelesen werden.';
  end
  else
  begin
    DeviceKey := GetOrCreateDeviceKey();
    Registered := RegisterDevice(Token, Id, HostName, DeviceKey, Pw, RegistrationError);
  end;
  InstallSucceeded := Registered;
  if Registered then
    InstallSummary := 'Das Gerät wurde automatisch Ihrem Kundenkonto zugeordnet.' + #13#10#13#10 +
      'RustDesk-ID: ' + Id + #13#10#13#10 +
      'Ihr Administrator findet die ID und das automatisch eingerichtete Passwort in der Admin-Oberfläche unter „Geräte“ → „Passwort anzeigen“.'
  else if Token <> '' then
    InstallSummary := 'Die Installation ist abgeschlossen, aber die automatische Anmeldung an die Verwaltung ist fehlgeschlagen.' + #13#10 +
      RegistrationError + #13#10#13#10 +
      'RustDesk-ID: ' + Id + #13#10#13#10 +
      'Bitte wenden Sie sich an Ihren Administrator, bevor die Fernwartung beginnt.'
  else
    InstallSummary := 'Die Installation ist abgeschlossen.' + #13#10#13#10 +
      'RustDesk-ID: ' + Id + #13#10 +
      'Zugangspasswort: ' + Pw + #13#10#13#10 +
      'Bitte teilen Sie die Verbindungsdaten nur direkt mit Ihrem Administrator.';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    if InstallSucceeded then
      WizardForm.FinishedHeadingLabel.Caption := 'Wucherer.Pro Remote Support ist eingerichtet'
    else
      WizardForm.FinishedHeadingLabel.Caption := 'Einrichtung abgeschlossen – Anmeldung prüfen';
    WizardForm.FinishedLabel.Caption := InstallSummary;
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
  end;
end;
