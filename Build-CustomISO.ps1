<#
.SYNOPSIS
  Builds a debloated, privacy-hardened, fully unattended Windows 11 ISO.

.DESCRIPTION
  Run from an ELEVATED PowerShell:
      Set-ExecutionPolicy -Scope Process Bypass -Force
      cd D:\win11Cus
      .\Build-CustomISO.ps1
  It asks for the source ISO and where to save the result (Enter = default shown), or pass
  them directly:  .\Build-CustomISO.ps1 -SourceIso 'E:\Win11.iso' -OutputIso 'F:\ISOs\Custom.iso'
  (uses wallpaper-light.jpg and wallpaper-dark.jpg from this folder; or pass -Wallpaper / -WallpaperDark)

  What it does:
    1. Copies the source ISO, keeps ONLY the edition you choose (smaller image, no edition picker).
    2. Removes bloat apps (Copilot, Xbox, Bing, Teams, Outlook, Clipchamp, Widgets, Phone Link, ...),
       Recall, OneDrive auto-install, and some legacy optional capabilities.
    3. Bakes privacy policies into the image: telemetry/diagnostics off, location + location
       services off, advertising ID off, activity history off, Start/lock-screen ads and
       "suggestions" off, web/Bing search off, Copilot/Recall off, error reporting off,
       inking/typing collection off, Delivery Optimization P2P off, Edge tracking/telemetry off,
       BitLocker auto-encryption off (recovery key would otherwise go to a Microsoft account).
    4. Disables telemetry/location services and telemetry scheduled tasks.
    5. Deletes ALL stock wallpapers, lock screens and extra themes. Installs .\wallpapers\light.jpg
       (Light theme), dark.jpg (Dark theme + lock screen), and every other image in .\wallpapers
       as its own theme. Replaces EVERY Windows sound (event *.wav incl. dark-mode copies and
       navigation *.raw) with the generated set in .\sounds\set and removes any stock sound left
       over. The startup sound is replaced inside Windows itself (WAVE 5080 in
       SystemResources\imageres.dll.mun) and Windows' own startup sound is switched on, so the
       new sound plays at the normal moment (boot logo -> lock screen), Fast Startup untouched.
       Regenerate with tools\wallgen.py / tools\recreate_sounds.py.
    5b. Lightweight/faster: disables SysMain, Search indexer, diagnostics and other idle services,
       blocks background Store apps, turns off animations/transparency, removes startup delay,
       shrinks the hibernation file (Fast Startup kept), 7 GB reserved storage, and shrinks
       WinSxS with /ResetBase.
    6. Writes autounattend.xml: no EULA, no edition/key page, no region/keyboard pages, no
       network page, no Microsoft-account page, no privacy page. A LOCAL admin account is
       created automatically. The only screen you see is "Where do you want to install
       Windows?" (unless you pass -AutoWipeDisk0).
    7. Rebuilds a bootable (BIOS + UEFI) ISO with oscdimg.

  Windows Update, Defender and SmartScreen are intentionally KEPT for security.

.PARAMETER UnattendOnly
  Only writes autounattend.xml to -OutputUnattend (no admin needed). Useful for testing.
#>
[CmdletBinding()]
param(
    [string]$SourceIso    = (Join-Path $PSScriptRoot 'Windows11_Client_x64_en-us_26300_9457.iso'),
    [string]$OutputIso    = (Join-Path $PSScriptRoot 'Win11_Custom_x64.iso'),
    [string]$WorkDir      = (Join-Path $PSScriptRoot 'work'),
    [string]$Wallpaper    = '',          # Light theme wallpaper; defaults to wallpaper-light.jpg next to this script
    [string]$WallpaperDark = '',         # Dark theme wallpaper;  defaults to wallpaper-dark.jpg next to this script
    [string]$LockScreen   = '',          # defaults to the dark wallpaper
    [string]$Edition      = '',          # e.g. 'Windows 11 Pro'. Empty = choose from a list
    [string]$UserName     = '',          # empty = prompt
    [string]$Password     = $null,       # $null = prompt (blank allowed)
    [string]$ComputerName = '*',         # '*' = random name
    [string]$TimeZone     = (Get-TimeZone).Id,
    [string]$UserLocale   = (Get-Culture).Name,
    [string]$SystemLocale = (Get-WinSystemLocale).Name,
    [string]$InputLocale  = '',          # e.g. '0409:00000409'; empty = this PC's keyboard
    [switch]$AutoWipeDisk0,              # DANGER: erases disk 0 with no prompt
    [switch]$UnattendOnly,
    [string]$EditionId    = 'Professional',  # only used with -UnattendOnly
    [string]$OutputUnattend = (Join-Path $PSScriptRoot 'autounattend.xml')
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------------------------
# Configuration lists - edit freely
# ----------------------------------------------------------------------------------------------

# Provisioned Store apps to remove (exact DisplayName). Calculator, Notepad, Paint, Photos,
# Terminal, Snipping Tool, Media Player, Store, App Installer (winget) and codecs are kept.
$RemoveApps = @(
    'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10', 'Microsoft.BingNews', 'Microsoft.BingSearch',
    'Microsoft.BingWeather', 'Microsoft.BingTranslator', 'Microsoft.Copilot', 'Microsoft.Edge.GameAssist',
    'Microsoft.GamingApp', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Messaging',
    'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.MixedReality.Portal', 'Microsoft.MSPaint', 'Microsoft.News', 'Microsoft.Office.OneNote',
    'Microsoft.Office.Sway', 'Microsoft.OutlookForWindows', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop',
    'Microsoft.Print3D', 'Microsoft.SkypeApp', 'Microsoft.Todos', 'Microsoft.Wallet',
    'Microsoft.Windows.Ai.Copilot.Provider', 'Microsoft.Windows.DevHome', 'Microsoft.WindowsCommunicationsApps',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WidgetsPlatformRuntime',
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone',
    'Microsoft.ZuneVideo', 'MicrosoftCorporationII.MicrosoftFamily', 'MicrosoftCorporationII.QuickAssist',
    'MicrosoftTeams', 'MSTeams', 'MicrosoftWindows.Client.WebExperience', 'MicrosoftWindows.CrossDevice',
    # extra apps removed for a lighter system
    'Microsoft.WindowsAlarms', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.WindowsSoundRecorder',
    'Microsoft.MicrosoftJournal', 'Microsoft.OneDriveSync', 'Microsoft.MicrosoftPCManager'
)

# Optional capabilities to remove (name prefix match)
$RemoveCapabilities = @(
    'App.StepsRecorder', 'App.Support.QuickAssist', 'Browser.InternetExplorer', 'MathRecognizer',
    'Microsoft.Windows.WordPad', 'OneCoreUAP.OneSync', 'Microsoft.Wallpapers.Extended',
    'Media.WindowsMediaPlayer', 'Print.Fax.Scan', 'Microsoft.Windows.PowerShell.ISE',
    'Language.Handwriting', 'Language.Speech'
)

# Optional features to disable and remove
$RemoveFeatures = @(
    'Recall', 'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2', 'WorkFolders-Client',
    'Printing-XPSServices-Features', 'SMB1Protocol'
)

# Services to disable (Start=4) - only touched if they exist in the image
$DisableServices = @(
    'DiagTrack', 'dmwappushservice', 'diagnosticshub.standardcollector.service', 'lfsvc', 'MapsBroker',
    'WerSvc', 'wercplsupport', 'RetailDemo', 'tzautoupdate', 'WpcMonSvc', 'XblAuthManager', 'XblGameSave',
    'XboxNetApiSvc', 'XboxGipSvc',
    # performance / lightweight
    'SysMain',            # Superfetch: constant background disk/RAM use, pointless on SSDs
    'WSearch',            # Search indexer: Start search still finds apps & settings
    'DPS', 'WdiServiceHost', 'WdiSystemHost',   # Diagnostic policy / resource usage tracking
    'PcaSvc',             # Program Compatibility Assistant
    'TrkWks',             # Distributed Link Tracking
    'CscService',         # Offline Files
    'AJRouter', 'Fax', 'WalletService', 'SEMgrSvc', 'RemoteRegistry', 'WMPNetworkSvc',
    'SharedRealitySvc', 'spectrum', 'perceptionsimulation'
)

# Scheduled tasks disabled at first logon
$DisableTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Location\Notifications',
    '\Microsoft\Windows\Location\WindowsActionDialog',
    '\Microsoft\Windows\Maps\MapsToastTask',
    '\Microsoft\Windows\Maps\MapsUpdateTask',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\PI\Sqm-Tasks',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)

# Registry: hive alias | key | value | type | data.   S = HKLM\SOFTWARE, Y = HKLM\SYSTEM\ControlSet001,
# U = default user profile (applies to every new account).
$RegSettings = @(
    # --- Telemetry / diagnostics ---
    'S|Policies\Microsoft\Windows\DataCollection|AllowTelemetry|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\DataCollection|MaxTelemetryAllowed|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\DataCollection|DoNotShowFeedbackNotifications|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\DataCollection|DisableOneSettingsDownloads|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\DataCollection|LimitDiagnosticLogCollection|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\DataCollection|LimitDumpCollection|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\DataCollection|AllowDeviceNameInTelemetry|REG_DWORD|0'
    'S|Microsoft\Windows\CurrentVersion\Policies\DataCollection|AllowTelemetry|REG_DWORD|0'
    'S|Microsoft\Windows\CurrentVersion\Policies\DataCollection|MaxTelemetryAllowed|REG_DWORD|0'
    'S|Policies\Microsoft\SQMClient\Windows|CEIPEnable|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\AppCompat|AITEnable|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\AppCompat|DisableInventory|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\AppCompat|DisableUAR|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\Windows Error Reporting|Disabled|REG_DWORD|1'
    'S|Microsoft\Windows\Windows Error Reporting|Disabled|REG_DWORD|1'
    'S|Policies\Microsoft\MRT|DontReportInfectionInformation|REG_DWORD|1'
    'S|Microsoft\Windows NT\CurrentVersion\Software Protection Platform|NoGenTicket|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\OOBE|DisablePrivacyExperience|REG_DWORD|1'
    'Y|Control\WMI\Autologger\AutoLogger-Diagtrack-Listener|Start|REG_DWORD|0'
    'Y|Control\WMI\Autologger\SQMLogger|Start|REG_DWORD|0'
    # --- Location ---
    'S|Policies\Microsoft\Windows\LocationAndSensors|DisableLocation|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\LocationAndSensors|DisableLocationScripting|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\LocationAndSensors|DisableWindowsLocationProvider|REG_DWORD|1'
    'S|Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location|Value|REG_SZ|Deny'
    'S|Policies\Microsoft\Windows\AppPrivacy|LetAppsAccessLocation|REG_DWORD|2'
    'S|Policies\Microsoft\FindMyDevice|AllowFindMyDevice|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Maps|AutoDownloadAndUpdateMapData|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Maps|AllowUntriggeredNetworkTrafficOnSettingsPage|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Windows Search|AllowSearchToUseLocation|REG_DWORD|0'
    # --- Ads, suggestions, consumer content ---
    'S|Policies\Microsoft\Windows\AdvertisingInfo|DisabledByGroupPolicy|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\CloudContent|DisableWindowsConsumerFeatures|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\CloudContent|DisableCloudOptimizedContent|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\CloudContent|DisableConsumerAccountStateContent|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\CloudContent|DisableSoftLanding|REG_DWORD|1'
    'S|Policies\Microsoft\PushToInstall|DisablePushToInstall|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\Explorer|HideRecommendedSection|REG_DWORD|1'
    'S|Policies\Microsoft\Dsh|AllowNewsAndInterests|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Windows Chat|ChatIcon|REG_DWORD|3'
    'S|Microsoft\Windows\CurrentVersion\Communications|ConfigureChatAutoInstall|REG_DWORD|0'
    # --- Activity history / cloud sync / cross-device ---
    'S|Policies\Microsoft\Windows\System|EnableActivityFeed|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\System|PublishUserActivities|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\System|UploadUserActivities|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\System|AllowCrossDeviceClipboard|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\SettingSync|DisableSettingSync|REG_DWORD|2'
    'S|Policies\Microsoft\Windows\SettingSync|DisableSettingSyncUserOverride|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\Messaging|AllowMessageSync|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\OneDrive|DisableFileSyncNGSC|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\AppPrivacy|LetAppsGetDiagnosticInfo|REG_DWORD|2'
    'S|Policies\Microsoft\Windows\AppPrivacy|LetAppsActivateWithVoice|REG_DWORD|2'
    # --- Copilot / Recall / AI ---
    'S|Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\WindowsAI|AllowRecallEnablement|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\WindowsAI|TurnOffSavingSnapshots|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\WindowsAI|DisableClickToDo|REG_DWORD|1'
    # --- Search: local only ---
    'S|Policies\Microsoft\Windows\Windows Search|AllowCortana|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Windows Search|DisableWebSearch|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\Windows Search|ConnectedSearchUseWeb|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\Windows Search|AllowCloudSearch|REG_DWORD|0'
    # --- Typing / inking / speech ---
    'S|Policies\Microsoft\InputPersonalization|AllowInputPersonalization|REG_DWORD|0'
    'S|Policies\Microsoft\InputPersonalization|RestrictImplicitInkCollection|REG_DWORD|1'
    'S|Policies\Microsoft\InputPersonalization|RestrictImplicitTextCollection|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\TextInput|AllowLinguisticDataCollection|REG_DWORD|0'
    'S|Policies\Microsoft\Windows\TabletPC|PreventHandwritingDataSharing|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\HandwritingErrorReports|PreventHandwritingErrorReports|REG_DWORD|1'
    'S|Policies\Microsoft\Speech|AllowSpeechModelUpdate|REG_DWORD|0'
    # --- Network / updates ---
    'S|Policies\Microsoft\Windows\DeliveryOptimization|DODownloadMode|REG_DWORD|0'
    'S|Microsoft\WcmSvc\wifinetworkmanager\config|AutoConnectAllowedOEM|REG_DWORD|0'
    'S|Microsoft\Windows\CurrentVersion\OOBE|BypassNRO|REG_DWORD|1'
    'S|Policies\Microsoft\Windows\GameDVR|AllowGameDVR|REG_DWORD|0'
    # --- BitLocker: don't silently auto-encrypt (recovery key would be escrowed to Microsoft) ---
    'Y|Control\BitLocker|PreventDeviceEncryption|REG_DWORD|1'
    # --- Microsoft Edge (kept installed; telemetry and junk off) ---
    'S|Policies\Microsoft\Edge|HideFirstRunExperience|REG_DWORD|1'
    'S|Policies\Microsoft\Edge|DiagnosticData|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|PersonalizationReportingEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|UserFeedbackAllowed|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|ConfigureDoNotTrack|REG_DWORD|1'
    'S|Policies\Microsoft\Edge|TrackingPrevention|REG_DWORD|2'
    'S|Policies\Microsoft\Edge|EdgeShoppingAssistantEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|ShowRecommendationsEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|SpotlightExperiencesAndRecommendationsEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|ShowMicrosoftRewards|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|HubsSidebarEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|NewTabPageContentEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|StartupBoostEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|BackgroundModeEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|AlternateErrorPagesEnabled|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|ResolveNavigationErrorsUseWebService|REG_DWORD|0'
    'S|Policies\Microsoft\Edge|NetworkPredictionOptions|REG_DWORD|2'
    # --- Per-user defaults (every new account) ---
    'U|Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo|Enabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Privacy|TailoredExperiencesWithDiagnosticDataEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Siuf\Rules|NumberOfSIUFInPeriod|REG_DWORD|0'
    'U|Software\Microsoft\Siuf\Rules|PeriodInNanoSeconds|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Search|BingSearchEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Search|CortanaConsent|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\SearchSettings|IsDynamicSearchBoxEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\SearchSettings|IsMSACloudSearchEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\SearchSettings|IsAADCloudSearchEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\SearchSettings|IsDeviceSearchHistoryEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement|ScoobeSystemSettingEnabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_IrisRecommendations|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_AccountNotifications|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_TrackProgs|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowSyncProviderNotifications|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowCopilotButton|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarDa|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarMn|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested|Enabled|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Mobility|OptedIn|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\CDP|CdpSessionUserAuthzPolicy|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\CDP|RomeSdkChannelUserAuthzPolicy|REG_DWORD|0'
    'U|Software\Microsoft\InputPersonalization|RestrictImplicitInkCollection|REG_DWORD|1'
    'U|Software\Microsoft\InputPersonalization|RestrictImplicitTextCollection|REG_DWORD|1'
    'U|Software\Microsoft\InputPersonalization\TrainedDataStore|HarvestContacts|REG_DWORD|0'
    'U|Software\Microsoft\Personalization\Settings|AcceptedPrivacyPolicy|REG_DWORD|0'
    'U|Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy|HasAccepted|REG_DWORD|0'
    'U|Control Panel\International\User Profile|HttpAcceptLanguageOptOut|REG_DWORD|1'
    'U|System\GameConfigStore|GameDVR_Enabled|REG_DWORD|0'
    'U|Software\Policies\Microsoft\Windows\CloudContent|DisableWindowsSpotlightFeatures|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\CloudContent|DisableTailoredExperiencesWithDiagnosticData|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\CloudContent|DisableThirdPartySuggestions|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\CloudContent|DisableSpotlightCollectionOnDesktop|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|REG_DWORD|1'
    'U|Software\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|REG_DWORD|1'
    # --- Performance / lightweight ---
    'S|Policies\Microsoft\Windows\AppPrivacy|LetAppsRunInBackground|REG_DWORD|2'      # no Store apps in background
    'S|Microsoft\Windows\CurrentVersion\ReserveManager|ShippedWithReserves|REG_DWORD|0'  # no 7 GB reserved storage
    'S|Policies\Microsoft\Windows\Windows Search|AllowIndexingEncryptedStoresOrItems|REG_DWORD|0'
    'Y|Control\FileSystem|NtfsDisableLastAccessUpdate|REG_DWORD|2147483649'            # fewer disk writes
    'U|Control Panel\Desktop|UserPreferencesMask|REG_BINARY|9012038010000000'          # "best performance" effects
    'U|Control Panel\Desktop|MenuShowDelay|REG_SZ|0'
    'U|Control Panel\Desktop|DragFullWindows|REG_SZ|1'
    'U|Control Panel\Desktop|FontSmoothing|REG_SZ|2'
    'U|Control Panel\Desktop\WindowMetrics|MinAnimate|REG_SZ|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects|VisualFXSetting|REG_DWORD|3'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarAnimations|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ListviewShadow|REG_DWORD|0'
    'U|Software\Microsoft\Windows\DWM|EnableAeroPeek|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize|StartupDelayInMSec|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize|WaitForIdleState|REG_DWORD|0'
    'U|Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications|GlobalUserDisabled|REG_DWORD|1'
    'U|Software\Microsoft\Windows\CurrentVersion\Search|BackgroundAppGlobalToggle|REG_DWORD|0'
)
# Content Delivery Manager (silent app installs, Start/lock-screen/Settings ads) - all off
foreach ($v in 'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
               'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled',
               'SoftLandingEnabled','SystemPaneSuggestionsEnabled','RotatingLockScreenEnabled',
               'RotatingLockScreenOverlayEnabled','SubscribedContentEnabled',
               'SubscribedContent-310093Enabled','SubscribedContent-338387Enabled',
               'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled',
               'SubscribedContent-338393Enabled','SubscribedContent-353694Enabled',
               'SubscribedContent-353696Enabled','SubscribedContent-353698Enabled',
               'SubscribedContent-88000326Enabled') {
    $RegSettings += "U|Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|$v|REG_DWORD|0"
}

# Generic (non-activating) setup keys - only used to skip the key/edition page.
# Windows still activates with your real license / firmware key afterwards.
$GenericKeys = @{
    'Core'='YTMG3-N6DKC-DKB77-7M9GH-8HVX7'; 'CoreN'='4CPRK-NM3K3-X6XXQ-RXX86-WXCHW'
    'CoreSingleLanguage'='BT79Q-G7N6G-PGBYW-4YWX6-6F4BT'
    'Education'='YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY'; 'EducationN'='84NGF-MHBT6-FXBX8-QWJK7-DRR8H'
    'Professional'='VK7JG-NPHTM-C97JM-9MPGT-3V66T'; 'ProfessionalN'='2B87N-8KFHP-DKV6R-Y2C8J-PKCKT'
    'ProfessionalEducation'='8PTT6-RNW4C-6V7J2-C2D3X-MHBPB'; 'ProfessionalEducationN'='GJTYN-HDMQY-FRR76-HVGC7-QPF8P'
    'ProfessionalWorkstation'='DXG7C-N36C4-C4HTG-X4T3X-2YV77'; 'ProfessionalWorkstationN'='WYPNQ-8C467-V2W6J-TX4WX-WT2RQ'
}

# ----------------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------------
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

function Set-WaveResource {
    # Replace a WAVE resource in a PE file (e.g. the startup sound, WAVE 5080 in
    # imageres.dll.mun) for every language it exists in, then read it back and verify.
    param([string]$File, [int]$Id, [string]$WavPath)
    if (-not ('ResEdit.Win32' -as [type])) {
        Add-Type -Namespace ResEdit -Name Win32 -MemberDefinition @'
[DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint fl);
[DllImport("kernel32")] public static extern bool FreeLibrary(IntPtr h);
public delegate bool EnumLangProc(IntPtr m, IntPtr type, IntPtr name, ushort lang, IntPtr l);
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern bool EnumResourceLanguages(IntPtr m, string type, IntPtr name, EnumLangProc cb, IntPtr l);
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr FindResourceEx(IntPtr m, string type, IntPtr name, ushort lang);
[DllImport("kernel32")] public static extern IntPtr LoadResource(IntPtr m, IntPtr r);
[DllImport("kernel32")] public static extern IntPtr LockResource(IntPtr r);
[DllImport("kernel32")] public static extern uint SizeofResource(IntPtr m, IntPtr r);
[DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr BeginUpdateResource(string f, bool deleteExisting);
[DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool UpdateResource(IntPtr h, string type, IntPtr name, ushort lang, byte[] data, uint size);
[DllImport("kernel32", SetLastError=true)] public static extern bool EndUpdateResource(IntPtr h, bool discard);
'@
    }
    $wav = [IO.File]::ReadAllBytes($WavPath)
    # 1) which languages does the resource exist in?
    $m = [ResEdit.Win32]::LoadLibraryEx($File, [IntPtr]::Zero, 0x22)
    if ($m -eq [IntPtr]::Zero) { throw "Cannot open $File for reading resources" }
    $langs = New-Object System.Collections.Generic.List[uint16]
    [void][ResEdit.Win32]::EnumResourceLanguages($m, 'WAVE', [IntPtr]$Id,
        [ResEdit.Win32+EnumLangProc]{ param($a, $b, $n, $l, $c) $langs.Add($l); $true }, [IntPtr]::Zero)
    [void][ResEdit.Win32]::FreeLibrary($m)
    if ($langs.Count -eq 0) { throw "WAVE $Id not found in $File" }
    # 2) replace it in place for each language
    $h = [ResEdit.Win32]::BeginUpdateResource($File, $false)
    if ($h -eq [IntPtr]::Zero) { throw "BeginUpdateResource failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
    foreach ($l in $langs) {
        if (-not [ResEdit.Win32]::UpdateResource($h, 'WAVE', [IntPtr]$Id, $l, $wav, [uint32]$wav.Length)) {
            [void][ResEdit.Win32]::EndUpdateResource($h, $true)
            throw "UpdateResource failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
        }
    }
    if (-not [ResEdit.Win32]::EndUpdateResource($h, $false)) {
        throw "EndUpdateResource failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
    # 3) verify: read every language back and compare with the new sound
    $m = [ResEdit.Win32]::LoadLibraryEx($File, [IntPtr]::Zero, 0x22)
    try {
        foreach ($l in $langs) {
            $r = [ResEdit.Win32]::FindResourceEx($m, 'WAVE', [IntPtr]$Id, $l)
            $size = [ResEdit.Win32]::SizeofResource($m, $r)
            $buf = New-Object byte[] $size
            [Runtime.InteropServices.Marshal]::Copy([ResEdit.Win32]::LockResource([ResEdit.Win32]::LoadResource($m, $r)), $buf, 0, $size)
            if ($size -ne $wav.Length -or -not [Linq.Enumerable]::SequenceEqual($buf, $wav)) {
                throw "Verification failed: WAVE $Id (lang $l) does not match $WavPath"
            }
        }
    } finally { [void][ResEdit.Win32]::FreeLibrary($m) }
    return $langs | ForEach-Object { '0x{0:X4}' -f $_ }
}

function Invoke-Quiet {
    # Run a native tool whose failures are acceptable (e.g. deleting a value that doesn't
    # exist). In Windows PowerShell, redirected stderr becomes a terminating error under
    # ErrorActionPreference=Stop, so relax it just for this call.
    param([string]$Exe, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments 2>&1 | Out-Null } finally { $ErrorActionPreference = $old }
}
function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}

function New-UnattendXml {
    param($EditionId, $UserName, $Password, $ComputerName, $TimeZone, $UserLocale, $SystemLocale,
          $InputLocale, [bool]$WipeDisk0)

    $arch = 'processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'
    $key  = $GenericKeys[$EditionId]
    $keyXml = ''
    if ($key) {
        $keyXml = "<ProductKey><Key>$key</Key><WillShowUI>OnError</WillShowUI></ProductKey>"
    }

    if ($WipeDisk0) {
        $diskXml = @"
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
"@
        $installTo = '<InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>'
    } else {
        $diskXml = ''
        $installTo = ''   # no InstallTo => Setup shows the disk picker (the only screen you will see)
    }

    $u = Esc $UserName
    $p = Esc $Password
    $cn = Esc $ComputerName

@"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" $arch>
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>$InputLocale</InputLocale>
      <SystemLocale>$SystemLocale</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>$UserLocale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" $arch>
$diskXml      <ImageInstall>
        <OSImage>
          <InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>1</Value></MetaData></InstallFrom>
          $installTo
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
      <UserData>
        $keyXml
        <AcceptEula>true</AcceptEula>
      </UserData>
      <DynamicUpdate><Enable>false</Enable><WillShowUI>Never</WillShowUI></DynamicUpdate>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" $arch>
      <ComputerName>$cn</ComputerName>
      <TimeZone>$TimeZone</TimeZone>
    </component>
    <component name="Microsoft-Windows-Deployment" $arch>
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" $arch>
      <InputLocale>$InputLocale</InputLocale>
      <SystemLocale>$SystemLocale</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>$UserLocale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" $arch>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$u</Name>
            <DisplayName>$u</DisplayName>
            <Group>Administrators</Group>
            <Password><Value>$p</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <TimeZone>$TimeZone</TimeZone>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>cmd.exe /c "%WINDIR%\Setup\Scripts\FirstLogon.cmd"</CommandLine>
          <Description>Privacy hardening and cleanup</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

function Get-DefaultInputLocale {
    try {
        $tip = (Get-WinUserLanguageList)[0].InputMethodTips[0]
        if ($tip) { return $tip }
    } catch {}
    return '0409:00000409'
}

function Get-Credentials {
    if (-not $script:UserName) {
        do { $script:UserName = (Read-Host 'Local account user name').Trim() } while (-not $script:UserName)
    }
    if ($script:UserName -match '[\\/\[\]:;|=,+*?<>"@]' -or $script:UserName.Length -gt 20) {
        throw "Invalid user name '$($script:UserName)' (max 20 chars, no special characters)."
    }
    if ($null -eq $script:Password) {
        $s1 = Read-Host 'Password (leave blank for none)' -AsSecureString
        $s2 = Read-Host 'Confirm password' -AsSecureString
        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
        if ($p1 -ne $p2) { throw 'Passwords do not match.' }
        $script:Password = $p1
    }
}

if (-not $InputLocale) { $InputLocale = Get-DefaultInputLocale }

# ----------------------------------------------------------------------------------------------
# -UnattendOnly mode
# ----------------------------------------------------------------------------------------------
if ($UnattendOnly) {
    Get-Credentials
    $xml = New-UnattendXml -EditionId $EditionId -UserName $UserName -Password $Password `
        -ComputerName $ComputerName -TimeZone $TimeZone -UserLocale $UserLocale -SystemLocale $SystemLocale `
        -InputLocale $InputLocale -WipeDisk0 $AutoWipeDisk0.IsPresent
    [void][xml]$xml   # validate
    [IO.File]::WriteAllText($OutputUnattend, $xml, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Wrote $OutputUnattend"
    return
}

# ----------------------------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script from an ELEVATED PowerShell (Run as administrator).' }
# --- Source ISO / destination: asked on the command line unless passed as parameters ---------
function Read-PathAnswer([string]$Prompt, [string]$Default) {
    $a = Read-Host "$Prompt`n  [Enter = $Default]"
    $a = $a.Trim().Trim('"').Trim("'").Trim()       # drag-and-drop / "Copy as path" add quotes
    if (-not $a) { $a = $Default }
    [Environment]::ExpandEnvironmentVariables($a)
}
Write-Host ''
Write-Host '=== Windows 11 custom ISO builder ===' -ForegroundColor Cyan
while ($true) {
    if (-not $PSBoundParameters.ContainsKey('SourceIso')) {
        $SourceIso = Read-PathAnswer 'Path of the Windows 11 ISO to customize' $SourceIso
    }
    if ((Test-Path $SourceIso -PathType Leaf) -and $SourceIso -match '\.iso$') {
        $SourceIso = (Resolve-Path $SourceIso).ProviderPath; break
    }
    if ($PSBoundParameters.ContainsKey('SourceIso')) { throw "Source ISO not found (or not an .iso): $SourceIso" }
    Write-Host "  Not found or not an .iso file: $SourceIso" -ForegroundColor Red
}
while ($true) {
    if (-not $PSBoundParameters.ContainsKey('OutputIso')) {
        $OutputIso = Read-PathAnswer 'Where to save the custom ISO (file path or folder)' $OutputIso
    }
    if ((Test-Path $OutputIso -PathType Container) -or $OutputIso -match '[\\/]$') {
        $OutputIso = Join-Path $OutputIso 'Win11_Custom_x64.iso'       # folder given: default file name
    }
    if ($OutputIso -notmatch '\.iso$') { $OutputIso += '.iso' }
    $OutputIso = [IO.Path]::GetFullPath($OutputIso)
    $outDir = Split-Path $OutputIso -Parent
    $err = $null
    if ($OutputIso -eq $SourceIso) { $err = 'Destination must be different from the source ISO.' }
    elseif (-not (Test-Path $outDir)) {
        try { New-Item -ItemType Directory -Path $outDir -Force | Out-Null } catch { $err = "Cannot create folder: $outDir" }
    }
    if (-not $err) {
        $free = (Get-PSDrive -Name $OutputIso.Substring(0, 1) -ErrorAction SilentlyContinue).Free
        $need = (Get-Item $SourceIso).Length * 1.1
        if ($free -and $free -lt $need) { $err = "Not enough free space on $($OutputIso.Substring(0, 2)) (need about $([math]::Ceiling($need / 1GB)) GB)." }
    }
    if (-not $err -and (Test-Path $OutputIso)) {
        if ($PSBoundParameters.ContainsKey('OutputIso')) { Write-Host "  $OutputIso exists and will be replaced." -ForegroundColor Yellow }
        elseif ((Read-Host "  $OutputIso already exists. Overwrite? (Y/N)") -notmatch '^[Yy]') { $err = 'Choose another destination.' }
    }
    if (-not $err) { break }
    if ($PSBoundParameters.ContainsKey('OutputIso')) { throw $err }
    Write-Host "  $err" -ForegroundColor Red
}
Write-Host "Source ISO : $SourceIso" -ForegroundColor Green
Write-Host "Output ISO : $OutputIso" -ForegroundColor Green
Write-Host ''
if ($WorkDir -match ' ') { throw "WorkDir must not contain spaces: $WorkDir" }

$WallpaperDir = Join-Path $PSScriptRoot 'wallpapers'
$SoundDir     = Join-Path $PSScriptRoot 'sounds'
function Find-Wallpaper($baseName) {
    Get-ChildItem $WallpaperDir, $PSScriptRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq $baseName -and $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Wallpaper)     { $Wallpaper     = Find-Wallpaper 'light' }
if (-not $Wallpaper)     { $Wallpaper     = Find-Wallpaper 'wallpaper-light' }
if (-not $WallpaperDark) { $WallpaperDark = Find-Wallpaper 'dark' }
if (-not $WallpaperDark) { $WallpaperDark = Find-Wallpaper 'wallpaper-dark' }
# Every other image in .\wallpapers becomes its own selectable theme
$ExtraWallpapers = @(Get-ChildItem $WallpaperDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' -and $_.BaseName -notin 'light', 'dark' })
Write-Host "Extra wallpapers: $(($ExtraWallpapers.BaseName) -join ', ')"
$SoundDir = Join-Path $SoundDir 'set'
if (-not (Test-Path "$SoundDir\Startup.wav")) { Write-Warning "No sound set in $SoundDir - keeping stock Windows sounds." }
else {
    # The startup sound itself is replaced INSIDE Windows (WAVE 5080 in
    # SystemResources\imageres.dll.mun), so Windows' own startup-sound feature plays the new
    # sound at its normal moment (boot logo -> lock screen), with Fast Startup left on.
    # Turn that built-in feature ON (Windows 11 ships with it off).
    $RegSettings += 'S|Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation|DisableStartupSound|REG_DWORD|0'
    $RegSettings += 'S|Microsoft\Windows\CurrentVersion\EditionOverrides|UserSetting_DisableStartupSound|REG_DWORD|0'
}
foreach ($w in $Wallpaper, $WallpaperDark, $LockScreen) {
    if ($w -and -not (Test-Path $w)) { throw "Wallpaper not found: $w" }
}
if (-not $Wallpaper -and $WallpaperDark) { $Wallpaper = $WallpaperDark }
if (-not $WallpaperDark) { $WallpaperDark = $Wallpaper }
if (-not $Wallpaper) { Write-Warning 'No wallpaper found (wallpaper-light.jpg / wallpaper-dark.jpg next to the script). Keeping the stock wallpapers.' }
if (-not $LockScreen) { $LockScreen = $WallpaperDark }
Write-Host "Light wallpaper : $Wallpaper"
Write-Host "Dark wallpaper  : $WallpaperDark"
Write-Host "Lock screen     : $LockScreen"

# oscdimg (Windows ADK Deployment Tools)
$oscdimg = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    (Join-Path $PSScriptRoot 'oscdimg.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $oscdimg) {
    Write-Warning 'oscdimg.exe (Windows ADK - Deployment Tools) is required to build the ISO.'
    $ans = Read-Host 'Install Windows ADK Deployment Tools now with winget? [y/N]'
    if ($ans -notmatch '^[yY]') { throw 'Install the Windows ADK (Deployment Tools only) and re-run.' }
    winget install --id Microsoft.WindowsADK -e --accept-package-agreements --accept-source-agreements `
        --override '/quiet /norestart /features OptionId.DeploymentTools'
    $oscdimg = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    if (-not (Test-Path $oscdimg)) { throw 'oscdimg still not found after install.' }
}

Get-Credentials

$IsoDir   = Join-Path $WorkDir 'iso'
$MountDir = Join-Path $WorkDir 'mount'
$TmpWim   = Join-Path $WorkDir 'install.wim'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
# A transcript left running in this window by an earlier (failed) run blocks a new one: stop it.
try { Stop-Transcript -ErrorAction Stop | Out-Null } catch {}
try { Start-Transcript -Path (Join-Path $WorkDir 'build.log') -Force -ErrorAction Stop | Out-Null }
catch {   # log file busy for some other reason -> use a fresh name instead of failing the build
    Start-Transcript -Path (Join-Path $WorkDir ("build-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))) -Force | Out-Null
}

$hives = @{ S = 'HKLM\zSOFTWARE'; Y = 'HKLM\zSYSTEM'; U = 'HKLM\zNTUSER' }
$isoMounted = $false
$wimMounted = $false

function Unload-Hives {
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    foreach ($h in $hives.Values) {
        if (Test-Path "Registry::$h") { Invoke-Quiet reg.exe unload $h }
    }
}

try {
    # Clean up leftovers from an earlier failed run
    Unload-Hives
    if ((Test-Path $MountDir) -and (Get-ChildItem $MountDir -Force -ErrorAction SilentlyContinue)) {
        Write-Step 'Discarding a stale mounted image from a previous run'
        & dism.exe /English /Unmount-Image /MountDir:$MountDir /Discard | Out-Null
        & dism.exe /English /Cleanup-Wim | Out-Null
    }
    foreach ($d in $IsoDir, $MountDir) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
        New-Item -ItemType Directory -Force $d | Out-Null
    }
    if (Test-Path $TmpWim) { Remove-Item $TmpWim -Force }

    # ------------------------------------------------------------------------------------------
    Write-Step 'Mounting and copying source ISO'
    $img = Mount-DiskImage -ImagePath $SourceIso -PassThru
    $isoMounted = $true
    $src = ($img | Get-Volume).DriveLetter + ':'
    $srcWim = Join-Path $src 'sources\install.wim'
    if (-not (Test-Path $srcWim)) { $srcWim = Join-Path $src 'sources\install.esd' }
    & robocopy.exe "$src\" $IsoDir /E /R:1 /W:1 /NFL /NDL /NJH /NP /XF install.wim install.esd | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    attrib.exe -R "$IsoDir\*" /S /D | Out-Null

    # ------------------------------------------------------------------------------------------
    Write-Step 'Choosing edition'
    $images = Get-WindowsImage -ImagePath $srcWim
    if ($Edition) {
        $chosen = $images | Where-Object { $_.ImageName -eq $Edition }
        if (-not $chosen) { throw "Edition '$Edition' not in ISO. Available: $($images.ImageName -join ', ')" }
    } else {
        $images | ForEach-Object { Write-Host ('  [{0,2}] {1}' -f $_.ImageIndex, $_.ImageName) }
        $idx = [int](Read-Host 'Edition number to build')
        $chosen = $images | Where-Object { $_.ImageIndex -eq $idx }
        if (-not $chosen) { throw "Invalid choice $idx" }
    }
    $info = Get-WindowsImage -ImagePath $srcWim -Index $chosen.ImageIndex
    $EditionId = $info.EditionId
    Write-Host "Using: $($chosen.ImageName) (index $($chosen.ImageIndex), $EditionId)"

    Write-Step 'Exporting the selected edition'
    Invoke-Native dism.exe @('/English', '/Export-Image', "/SourceImageFile:$srcWim", "/SourceIndex:$($chosen.ImageIndex)",
                             "/DestinationImageFile:$TmpWim", '/Compress:max', '/CheckIntegrity')
    Dismount-DiskImage -ImagePath $SourceIso | Out-Null
    $isoMounted = $false

    Write-Step 'Mounting install image (takes a few minutes)'
    Invoke-Native dism.exe @('/English', '/Mount-Image', "/ImageFile:$TmpWim", '/Index:1', "/MountDir:$MountDir")
    $wimMounted = $true

    # ------------------------------------------------------------------------------------------
    Write-Step 'Removing bloat apps'
    foreach ($pkg in Get-AppxProvisionedPackage -Path $MountDir) {
        if ($RemoveApps -contains $pkg.DisplayName) {
            Write-Host "  - $($pkg.DisplayName)"
            try { Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName | Out-Null }
            catch { Write-Warning "    could not remove: $($_.Exception.Message)" }
        }
    }

    Write-Step 'Removing optional capabilities'
    foreach ($cap in Get-WindowsCapability -Path $MountDir | Where-Object State -eq 'Installed') {
        foreach ($prefix in $RemoveCapabilities) {
            if ($cap.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "  - $($cap.Name)"
                try { Remove-WindowsCapability -Path $MountDir -Name $cap.Name | Out-Null }
                catch { Write-Warning "    could not remove: $($_.Exception.Message)" }
            }
        }
    }

    Write-Step 'Disabling optional features'
    foreach ($f in $RemoveFeatures) {
        $feat = Get-WindowsOptionalFeature -Path $MountDir -FeatureName $f -ErrorAction SilentlyContinue
        if ($feat -and $feat.State -ne 'Disabled' -and $feat.State -ne 'DisabledWithPayloadRemoved') {
            Write-Host "  - $f"
            try { Disable-WindowsOptionalFeature -Path $MountDir -FeatureName $f -Remove -NoRestart | Out-Null }
            catch { Write-Warning "    could not disable: $($_.Exception.Message)" }
        }
    }

    Write-Step 'Removing OneDrive installer'
    foreach ($od in "$MountDir\Windows\System32\OneDriveSetup.exe", "$MountDir\Windows\SysWOW64\OneDriveSetup.exe") {
        if (Test-Path $od) {
            takeown.exe /F $od /A | Out-Null
            icacls.exe $od /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item $od -Force
            Write-Host "  - $od"
        }
    }

    # ------------------------------------------------------------------------------------------
    Write-Step 'Removing ALL stock wallpapers/themes and installing your wallpaper'
    function Grant-Admin($path) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            Invoke-Quiet takeown.exe /F $path /A /R /D Y
            Invoke-Quiet icacls.exe $path /grant '*S-1-5-32-544:F' /T /C /Q
        } else {                                              # single file: no recursion flags
            Invoke-Quiet takeown.exe /F $path /A
            Invoke-Quiet icacls.exe $path /grant '*S-1-5-32-544:F' /C /Q
        }
    }
    if ($Wallpaper) {
        $web = "$MountDir\Windows\Web"
        Grant-Admin $web
        # Wipe every stock image: desktop wallpapers (all theme folders), 4K variants,
        # lock screens, Spotlight and touch-keyboard backgrounds
        Get-ChildItem $web -Force | Remove-Item -Recurse -Force
        foreach ($d in 'Wallpaper\Windows', 'Wallpaper\Custom', 'Screen') {
            New-Item -ItemType Directory -Force "$web\$d" | Out-Null
        }
        Copy-Item $Wallpaper     "$web\Wallpaper\Custom\wallpaper-light.jpg" -Force
        Copy-Item $WallpaperDark "$web\Wallpaper\Custom\wallpaper-dark.jpg"  -Force
        # The built-in Light theme (aero.theme) uses img0, the Dark theme (dark.theme) uses img19
        Copy-Item $Wallpaper     "$web\Wallpaper\Windows\img0.jpg"  -Force
        Copy-Item $WallpaperDark "$web\Wallpaper\Windows\img19.jpg" -Force
        # Default lock-screen image names
        foreach ($n in 100..105) { Copy-Item $LockScreen "$web\Screen\img$n.jpg" -Force }

        # Remove the extra stock themes (Glow, Captured Motion, Sunrise, Flow, Spotlight);
        # keep only the plain Light (aero) and Dark themes, which now use your wallpaper
        $themes = "$MountDir\Windows\Resources\Themes"
        Get-ChildItem $themes -File -Filter '*.theme' |
            Where-Object { $_.Name -notin 'aero.theme', 'dark.theme' } |
            ForEach-Object { Grant-Admin $_.FullName; Remove-Item $_.FullName -Force; Write-Host "  - theme $($_.Name)" }

        # Extra wallpapers -> one theme each (Settings > Personalization > Themes).
        # Dark images are based on dark.theme (dark mode), bright ones on aero.theme.
        Add-Type -AssemblyName System.Drawing
        $ti = (Get-Culture).TextInfo
        foreach ($w in $ExtraWallpapers) {
            $dest = "$web\Wallpaper\Custom\$($w.BaseName).jpg"
            Copy-Item $w.FullName $dest -Force
            $bmp = New-Object Drawing.Bitmap $w.FullName
            $small = New-Object Drawing.Bitmap $bmp, 32, 18
            $sum = 0; for ($i = 0; $i -lt 32; $i++) { for ($j = 0; $j -lt 18; $j++) { $sum += $small.GetPixel($i, $j).GetBrightness() } }
            $small.Dispose(); $bmp.Dispose()
            $isDark = ($sum / 576) -lt 0.45
            $template = if ($isDark) { "$themes\dark.theme" } else { "$themes\aero.theme" }
            $display = $ti.ToTitleCase($w.BaseName.Replace('-', ' ').Replace('_', ' '))
            $section = ''
            $lines = foreach ($l in Get-Content $template) {
                if ($l -match '^\s*\[(.+)\]') { $section = $Matches[1] }
                if ($section -eq 'Theme' -and $l -match '^\s*DisplayName\s*=') { "DisplayName=$display"; continue }
                if ($section -eq 'Theme' -and $l -match '^\s*ThemeId\s*=') { "ThemeId={$([guid]::NewGuid().ToString().ToUpper())}"; continue }
                if ($section -eq 'Control Panel\Desktop' -and $l -match '^\s*Wallpaper\s*=') {
                    "Wallpaper=%SystemRoot%\Web\Wallpaper\Custom\$($w.BaseName).jpg"; continue
                }
                $l
            }
            [IO.File]::WriteAllLines("$themes\$($w.BaseName).theme", [string[]]$lines, [Text.Encoding]::Unicode)
            Write-Host ("  + theme {0} ({1})" -f $display, $(if ($isDark) { 'dark' } else { 'light' }))
        }
    }

    # ------------------------------------------------------------------------------------------
    if (Test-Path "$SoundDir\Startup.wav") {
        Write-Step 'Installing the new sound set (replaces every stock sound)'
        $media = "$MountDir\Windows\Media"
        Grant-Admin $media
        # Drop the alternative sound-scheme folders (Afternoon, Calligraphy, Delta, ...);
        # keep 'dm' (the quieter dark-mode copies Windows 11 plays) and replace those too.
        Get-ChildItem $media -Directory | Where-Object Name -ne 'dm' | Remove-Item -Recurse -Force
        # Each generated file replaces the Windows file with the same relative path: event sounds
        # (*.wav, incl. dark-mode copies) and navigation UI sounds (*.raw). Any stock sound file
        # without a replacement is removed, so no old sound can ever play.
        $replaced = 0; $removed = 0
        foreach ($f in @(Get-ChildItem $media, "$media\dm" -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -in '.wav', '.raw' })) {
            $rel = $f.FullName.Substring($media.Length + 1)
            $new = Join-Path $SoundDir $rel
            if (Test-Path $new) { Copy-Item $new $f.FullName -Force; $replaced++ }
            else { Remove-Item $f.FullName -Force; $removed++; Write-Host "  - removed old sound $rel" }
        }
        Write-Host "  replaced $replaced sound files, removed $removed old ones without a replacement"

        # The startup sound lives inside Windows itself: resource WAVE 5080 in
        # SystemResources\imageres.dll.mun. Replace it there, so Windows' own startup-sound
        # feature plays the new sound at its normal moment.
        Write-Step 'Replacing the startup sound inside Windows (imageres.dll.mun)'
        $mun = "$MountDir\Windows\SystemResources\imageres.dll.mun"
        if (-not (Test-Path $mun)) { throw "imageres.dll.mun not found in the image: $mun" }
        Grant-Admin $mun
        # Patch a copy in the work folder: saving resources writes a temp file next to the target,
        # and the protected SystemResources folder doesn't allow that. Then copy it back.
        $munWork = Join-Path $WorkDir 'imageres.dll.mun'
        Copy-Item $mun $munWork -Force
        Set-ItemProperty $munWork -Name IsReadOnly -Value $false
        $langs = Set-WaveResource -File $munWork -Id 5080 -WavPath "$SoundDir\Startup.wav"
        Copy-Item $munWork $mun -Force
        if ((Get-FileHash $mun).Hash -ne (Get-FileHash $munWork).Hash) {
            throw 'Patched imageres.dll.mun could not be written back into the image'
        }
        Remove-Item $munWork -Force
        Write-Host "  WAVE 5080 replaced (language $($langs -join ', ')) and verified byte-for-byte"
    }

    # ------------------------------------------------------------------------------------------
    Write-Step 'Applying privacy registry settings'
    & reg.exe load $hives.S "$MountDir\Windows\System32\config\SOFTWARE" | Out-Null
    & reg.exe load $hives.Y "$MountDir\Windows\System32\config\SYSTEM"   | Out-Null
    & reg.exe load $hives.U "$MountDir\Users\Default\NTUSER.DAT"          | Out-Null

    $rootMap = @{ S = "$($hives.S)"; Y = "$($hives.Y)\ControlSet001"; U = "$($hives.U)" }
    foreach ($line in $RegSettings) {
        $hive, $key, $name, $type, $data = $line.Split('|')
        $full = "$($rootMap[$hive])\$key"
        & reg.exe add $full /v $name /t $type /d $data /f | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "reg add failed: $full\$name" }
    }

    if ($Wallpaper) {
        & reg.exe add "$($hives.U)\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d 'C:\Windows\Web\Wallpaper\Windows\img0.jpg' /f | Out-Null
    }

    # Stop OneDrive from installing for new users
    Invoke-Quiet reg.exe delete "$($hives.U)\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f

    # Stop Windows from silently re-installing Outlook / Dev Home / Teams etc. after setup
    $orch = "Registry::$($hives.S)\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe"
    if (Test-Path $orch) {
        Get-ChildItem $orch | Where-Object { $_.PSChildName -match 'Outlook|DevHome|Teams|Copilot|CrossDevice' } |
            ForEach-Object { Write-Host "  - auto-install: $($_.PSChildName)"; & reg.exe delete $_.Name /f | Out-Null }
    }

    Write-Step 'Disabling telemetry / location services'
    foreach ($svc in $DisableServices) {
        $k = "$($hives.Y)\ControlSet001\Services\$svc"
        if (Test-Path "Registry::$k") {
            & reg.exe add $k /v Start /t REG_DWORD /d 4 /f | Out-Null
            Write-Host "  - $svc"
        }
    }
    Unload-Hives

    # ------------------------------------------------------------------------------------------
    Write-Step 'Writing first-logon script'
    $scripts = "$MountDir\Windows\Setup\Scripts"
    New-Item -ItemType Directory -Force $scripts | Out-Null
    $cmd = @('@echo off', 'rem Generated by Build-CustomISO.ps1')
    foreach ($t in $DisableTasks) { $cmd += "schtasks /Change /TN `"$t`" /Disable >nul 2>&1" }
    if (Test-Path "$SoundDir\Startup.wav") {
        # Safety net: a big Windows update can replace imageres.dll.mun and bring the stock
        # startup sound back. At each sign-in, check the startup sound inside it; if it is no
        # longer ours, switch Windows' startup sound off so the old one is never heard.
        $sha = (Get-FileHash "$SoundDir\Startup.wav" -Algorithm SHA256).Hash
        $guard = @'
$expected = '__SHA__'
Add-Type -Namespace SG -Name R -MemberDefinition @"
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint fl);
[DllImport("kernel32")] public static extern bool FreeLibrary(IntPtr h);
[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr FindResource(IntPtr m, IntPtr name, string type);
[DllImport("kernel32")] public static extern IntPtr LoadResource(IntPtr m, IntPtr r);
[DllImport("kernel32")] public static extern IntPtr LockResource(IntPtr r);
[DllImport("kernel32")] public static extern uint SizeofResource(IntPtr m, IntPtr r);
"@
$m = [SG.R]::LoadLibraryEx("$env:WINDIR\SystemResources\imageres.dll.mun", [IntPtr]::Zero, 0x22)
if ($m -eq [IntPtr]::Zero) { return }
try {
    $r = [SG.R]::FindResource($m, [IntPtr]5080, 'WAVE'); if ($r -eq [IntPtr]::Zero) { return }
    $n = [SG.R]::SizeofResource($m, $r); $b = New-Object byte[] $n
    [Runtime.InteropServices.Marshal]::Copy([SG.R]::LockResource([SG.R]::LoadResource($m, $r)), $b, 0, $n)
    $h = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('X2') })
} finally { [void][SG.R]::FreeLibrary($m) }
$on = if ($h -eq $expected) { 0 } else { 1 }     # ours -> keep startup sound on; stock -> mute it
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' DisableStartupSound $on -Type DWord
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides' UserSetting_DisableStartupSound $on -Type DWord
'@ -replace '__SHA__', $sha
        [IO.File]::WriteAllText("$scripts\StartupSoundGuard.ps1", $guard, [Text.Encoding]::ASCII)
        $cmd += 'schtasks /Create /TN "StartupSoundGuard" /SC ONLOGON /RU SYSTEM /RL HIGHEST /F /TR "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File %WINDIR%\Setup\Scripts\StartupSoundGuard.ps1" >nul 2>&1'
    }
    $cmd += 'net accounts /maxpwage:unlimited >nul 2>&1'
    $cmd += 'rem --- lightweight: small hibernation file (keeps Fast Startup), no reserved storage ---'
    $cmd += 'powercfg /hibernate on >nul 2>&1'
    $cmd += 'powercfg /hibernate /type reduced >nul 2>&1'
    $cmd += 'DISM /Online /Set-ReservedStorageState /State:Disabled /NoRestart >nul 2>&1'
    $cmd += 'del /f /q "%WINDIR%\Panther\unattend.xml" "%WINDIR%\Panther\unattend-original.xml" >nul 2>&1'
    $cmd += 'del /f /q "%WINDIR%\System32\Sysprep\Panther\unattend.xml" >nul 2>&1'
    [IO.File]::WriteAllLines("$scripts\FirstLogon.cmd", $cmd, [Text.Encoding]::ASCII)

    # ------------------------------------------------------------------------------------------
    Write-Step 'Committing image'
    # /ResetBase drops superseded component versions -> much smaller WinSxS (updates baked into
    # the image can no longer be uninstalled, which is fine for a fresh install)
    Invoke-Native dism.exe @('/English', '/Cleanup-Image', "/Image:$MountDir", '/StartComponentCleanup', '/ResetBase')
    Invoke-Native dism.exe @('/English', '/Unmount-Image', "/MountDir:$MountDir", '/Commit')
    $wimMounted = $false

    Write-Step 'Recompressing install.wim'
    Invoke-Native dism.exe @('/English', '/Export-Image', "/SourceImageFile:$TmpWim", '/SourceIndex:1',
                             "/DestinationImageFile:$IsoDir\sources\install.wim", '/Compress:max', '/CheckIntegrity')
    Remove-Item $TmpWim -Force

    # ------------------------------------------------------------------------------------------
    Write-Step 'Writing autounattend.xml'
    $xml = New-UnattendXml -EditionId $EditionId -UserName $UserName -Password $Password `
        -ComputerName $ComputerName -TimeZone $TimeZone -UserLocale $UserLocale -SystemLocale $SystemLocale `
        -InputLocale $InputLocale -WipeDisk0 $AutoWipeDisk0.IsPresent
    [void][xml]$xml
    [IO.File]::WriteAllText("$IsoDir\autounattend.xml", $xml, (New-Object Text.UTF8Encoding($false)))

    # ------------------------------------------------------------------------------------------
    Write-Step 'Building ISO'
    $etfs = "$IsoDir\boot\etfsboot.com"
    $efi  = "$IsoDir\efi\microsoft\boot\efisys.bin"
    if (Test-Path $OutputIso) { Remove-Item $OutputIso -Force }
    Invoke-Native $oscdimg @('-m', '-o', '-u2', '-udfver102', '-lWIN11_CUSTOM',
                             "-bootdata:2#p0,e,b$etfs#pEF,e,b$efi", $IsoDir, $OutputIso)

    Write-Host "`nDONE: $OutputIso" -ForegroundColor Green
    Write-Host 'Write it to USB with Rufus (choose GPT / UEFI) or use it in a VM.'
}
catch {
    Write-Host "`nBUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    Unload-Hives
    if ($wimMounted) { & dism.exe /English /Unmount-Image /MountDir:$MountDir /Discard | Out-Null }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $SourceIso -ErrorAction SilentlyContinue | Out-Null }
    Stop-Transcript | Out-Null
}
