; CastSprint Windows Inno Setup Script
; Generates CastSprint_Setup_v0.2.0_Beta_x64.exe

#define MyAppName "CastSprint"
#define MyAppVersion "0.2.0-beta"
#define MyAppPublisher "CastSprint Project"
#define MyAppURL "https://github.com/CastSprint/CastSprint"
#define MyAppExeName "castsprint_receiver.exe"

[Setup]
AppId={{D1A2E3B4-C5F6-4A7B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\docs\PRIVACY.md
OutputDir=..\build\installer
OutputBaseFilename=CastSprint_Setup_v0.2.0_Beta_x64
SetupIconFile=..\apps\windows\resources\app.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "firewall"; Description: "Add Windows Defender Firewall rule for port 27183"; GroupDescription: "Network Configuration"

[Files]
Source: "..\build\windows\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\OBS_GUIDE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\USB_CONNECTION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\WIFI_CONNECTION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\TROUBLESHOOTING.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\OBS Streaming Guide"; Filename: "{app}\OBS_GUIDE.md"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""CastSprint Receiver"" dir=in action=allow protocol=TCP localport=27183 profile=private"; Flags: runhidden; Tasks: firewall
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""CastSprint Receiver"""; Flags: runhidden
