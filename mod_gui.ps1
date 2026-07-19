# ==========================================================================
#  Instantale SD MOD マネージャー GUI  (mod_gui.bat から起動)
#  MOD の導入・SD1.5/SDXL モード切替・アンインストール・状態表示と、
#  sd_upscale.ini のフォーム編集を 1 つのウィンドウに統合したツール。
#
#  「導入 / 管理」タブ: 旧 install_sd15.bat / install_sdxl.bat /
#  switch_sd_mode.bat の処理を移植したもの。ゲームルートは settings.ini
#  (前回のパス) → 上位フォルダの探索 → フォルダ選択、の順で解決する。
#
#  設定編集タブ群: ini のコメント行はそのまま保持し、値の行だけを
#  書き換える。自由記載欄の「有効」チェックを外すと、内容を
#  ";off: key = value" 形式のコメントとして保存する (プロキシは無視するが
#  GUI は次回オフ状態で復元する)。保存後、次の画像生成から反映される
#  (ゲームの再起動は不要 -- プロキシ DLL が生成のたびに ini を読み直すため)。
#
#  -SelfTest       : 設定エディタの自己テスト (ウィンドウ表示なし)
#  -SelfTestManage : 導入/切替/撤去の自己テスト (一時フォルダの偽ゲームで実行)
#  このファイルは UTF-8 (BOM 付き) で保存すること (Windows PowerShell 5.1 対応)。
# ==========================================================================
param([switch]$SelfTest, [switch]$SelfTestManage)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if (-not ('SdGui.MapEntry' -as [type])) {
    Add-Type -TypeDefinition @"
namespace SdGui {
    public class MapEntry {
        public bool   Enabled { get; set; }
        public string Name   { get; set; }
        public string Target { get; set; }
        public MapEntry() { Enabled = true; Name = ""; Target = ""; }
    }
    public class RuleEntry {
        public bool   Enabled { get; set; }
        public string Name { get; set; }
        public string Cls  { get; set; }
        public string Cond { get; set; }
        public string Add  { get; set; }
        public RuleEntry() { Enabled = true; Name = ""; Cls = "portrait"; Cond = ""; Add = ""; }
    }
}
"@
} elseif (-not [SdGui.MapEntry].GetProperty('Enabled')) {
    throw '古い SdGui 型が読み込まれた PowerShell セッションです。新しいウィンドウから起動し直してください。'
}

# ---------------------------------------------------------------- ini 解析

# 有効行 (コメント/空行/セクション見出し以外) かどうか
function Test-ActiveLine([string]$line) {
    $t = $line.TrimStart()
    if ($t -eq '') { return $false }
    $c = $t[0]
    return ($c -ne ';' -and $c -ne '#' -and $c -ne '[')
}

# セクションの範囲 (見出しの次の行 Start ～ 次の見出しの手前 End) を返す
function Find-Section($lines, [string]$name) {
    $hdr = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^\[(.+)\]') {
            if ($hdr -ge 0) { return @{ Start = $hdr + 1; End = $i } }
            if ($Matches[1].Trim() -eq $name) { $hdr = $i }
        }
    }
    if ($hdr -ge 0) { return @{ Start = $hdr + 1; End = $lines.Count } }
    return $null
}

function Confirm-Section($lines, [string]$name) {
    $r = Find-Section $lines $name
    if ($r) { return $r }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
    $lines.Add("[$name]")
    return @{ Start = $lines.Count; End = $lines.Count }
}

# GUI のチェックボックスで無効化された値は ";off: key = value" 形式のコメント
# として保存する (プロキシは無視するが、GUI は次回起動時にオフ状態で復元する)。

# セクション内の ";off: key =" 無効化行をすべて削除する
function Remove-DisabledKey($lines, [string]$section, [string]$key) {
    $r = Find-Section $lines $section
    if (-not $r) { return }
    $rx = '^\s*;off:\s*' + [regex]::Escape($key) + '\s*='
    for ($i = $r.End - 1; $i -ge $r.Start; $i--) {
        if ($lines[$i] -match $rx) { $lines.RemoveAt($i) }
    }
}

# セクション内で key= の有効行を探し、最後の 1 行を書き換える (残りはコメント化)。
# 無ければセクション末尾に追加する。コメント行 (記入例など) には触らない。
function Set-IniKey($lines, [string]$section, [string]$key, [string]$value) {
    Remove-DisabledKey $lines $section $key
    $r = Confirm-Section $lines $section
    $rx = '^\s*' + [regex]::Escape($key) + '\s*='
    $hits = @()
    for ($i = $r.Start; $i -lt $r.End; $i++) {
        if ((Test-ActiveLine $lines[$i]) -and $lines[$i] -match $rx) { $hits += $i }
    }
    if ($hits.Count -gt 0) {
        $lines[$hits[$hits.Count - 1]] = "$key = $value"
        for ($j = 0; $j -lt $hits.Count - 1; $j++) { $lines[$hits[$j]] = ';' + $lines[$hits[$j]] }
    } else {
        $ins = $r.End
        while ($ins -gt $r.Start -and $lines[$ins - 1].Trim() -eq '') { $ins-- }
        $lines.Insert($ins, "$key = $value")
    }
}

# key を無効化状態で保存する: 有効行の最後の 1 行を ";off:" 行に置き換え、
# 残りの有効行はコメント化する。有効行が無ければセクション末尾に追加する。
function Set-IniKeyDisabled($lines, [string]$section, [string]$key, [string]$value) {
    Remove-DisabledKey $lines $section $key
    $r = Confirm-Section $lines $section
    $rx = '^\s*' + [regex]::Escape($key) + '\s*='
    $hits = @()
    for ($i = $r.Start; $i -lt $r.End; $i++) {
        if ((Test-ActiveLine $lines[$i]) -and $lines[$i] -match $rx) { $hits += $i }
    }
    $newLine = ";off: $key = $value"
    if ($hits.Count -gt 0) {
        $lines[$hits[$hits.Count - 1]] = $newLine
        for ($j = 0; $j -lt $hits.Count - 1; $j++) { $lines[$hits[$j]] = ';' + $lines[$hits[$j]] }
    } else {
        $ins = $r.End
        while ($ins -gt $r.Start -and $lines[$ins - 1].Trim() -eq '') { $ins-- }
        $lines.Insert($ins, $newLine)
    }
}

# key= の有効行をコメント化する (デフォルトに戻す)。";off:" 行も削除する。
# セクションが無ければ何もしない。
function Clear-IniKey($lines, [string]$section, [string]$key) {
    Remove-DisabledKey $lines $section $key
    $r = Find-Section $lines $section
    if (-not $r) { return }
    $rx = '^\s*' + [regex]::Escape($key) + '\s*='
    for ($i = $r.Start; $i -lt $r.End; $i++) {
        if ((Test-ActiveLine $lines[$i]) -and $lines[$i] -match $rx) { $lines[$i] = ';' + $lines[$i] }
    }
}

# セクション内の有効行と ";off:" 行をすべて $newLines に置き換える (その他の
# コメント行は保持)
function Set-DynamicSection($lines, [string]$section, [string[]]$newLines) {
    $r = Confirm-Section $lines $section
    $active = @()
    for ($i = $r.Start; $i -lt $r.End; $i++) {
        if ((Test-ActiveLine $lines[$i]) -or $lines[$i].TrimStart().StartsWith(';off:')) { $active += $i }
    }
    if ($active.Count -gt 0) {
        $insertAt = $active[0]
        for ($j = $active.Count - 1; $j -ge 0; $j--) { $lines.RemoveAt($active[$j]) }
    } else {
        $insertAt = $r.End
        while ($insertAt -gt $r.Start -and $lines[$insertAt - 1].Trim() -eq '') { $insertAt-- }
    }
    foreach ($nl in $newLines) { $lines.Insert($insertAt, $nl); $insertAt++ }
}

# ini 全体を読み、有効な設定値と ";off:" 無効化値を取り出す
function Read-IniValues($lines) {
    $fx    = @{}
    $dis   = @{}
    $map   = New-Object System.Collections.ArrayList
    $rules = New-Object System.Collections.ArrayList
    $sec = ''
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -eq '') { continue }
        $enabled = $true
        if ($t.StartsWith(';off:')) {           # GUI で無効化された値 (コメント扱い)
            $t = $t.Substring(5).Trim()
            if ($t -eq '') { continue }
            $enabled = $false
        } elseif ($t[0] -eq ';' -or $t[0] -eq '#') { continue }
        if ($t[0] -eq '[') {
            if ($enabled -and $t -match '^\[(.+)\]') { $sec = $Matches[1].Trim().ToLower() }
            continue
        }
        $eq = $t.IndexOf('=')
        if ($eq -lt 0) { continue }
        $key = $t.Substring(0, $eq).Trim()
        $val = $t.Substring($eq + 1).Trim()
        if ($key -eq '') { continue }
        if ($sec -eq 'lora_map') {
            [void]$map.Add(@{ Name = $key; Target = $val; Enabled = $enabled })
        } elseif ($sec -eq 'lora_add_if') {
            $parts = $val -split '\|', 3
            if ($parts.Count -eq 3) {
                [void]$rules.Add(@{ Name = $key; Cls = $parts[0].Trim(); Cond = $parts[1].Trim(); Add = $parts[2].Trim(); Enabled = $enabled })
            }
        } elseif ($enabled) {
            $fx["$sec/$($key.ToLower())"] = $val   # 後勝ち (プロキシと同じ)
        } else {
            $dis["$sec/$($key.ToLower())"] = $val
        }
    }
    return @{ Fx = $fx; Dis = $dis; Map = $map; Rules = $rules }
}

# ------------------------------------- MOD 管理 (導入 / モード切替 / 撤去)
# 旧 install_sd15.bat / install_sdxl.bat / switch_sd_mode.bat の移植。
# ゲーム側で書き換えるのは各バックエンドの lib\stable-diffusion.dll
# (+ 退避 DLL) と TAESD デコーダのみ。設定 (sd_upscale.ini) と動作ログ
# (proxy_resize.log) は固定の <ゲームルート>\InstantaleSDMod\ に置かれ、
# プロキシ DLL は自分のパスからゲームルートを逆算してそこを読む
# (v2.0 以前のポインタ ini 方式は廃止)。

$script:Backends = @('sdcpp_cuda', 'sdcpp_cpu', 'sdcpp_vulkan')
$script:GameDir  = $null          # ゲームルートの絶対パス (末尾 \ なし)
$script:CfgDirName = 'InstantaleSDMod'   # ゲームルート直下の設定フォルダ名 (プロキシと一致させること)
$script:UrlTaesd15 = 'https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors'
$script:UrlTaesdXL = 'https://huggingface.co/madebyollin/taesdxl/resolve/main/diffusion_pytorch_model.safetensors'
$script:SdxlCkpt   = 'waiIllustriousSDXL_v170.safetensors'

# 旧バージョンの bat が ANSI (CP932 等) で書いた settings.ini を読むための
# システム ANSI コードページ (新規保存は UTF-8)
try {
    if (-not ('SdGui.Native' -as [type])) {
        Add-Type -Namespace SdGui -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint GetACP();'
    }
    $script:AnsiEnc = [System.Text.Encoding]::GetEncoding([int][SdGui.Native]::GetACP())
} catch { $script:AnsiEnc = [System.Text.Encoding]::Default }

# MOD が参照する固定パス一式 (GameDir 確定後に呼ぶこと)。
# CfgDir = プロキシが読む設定フォルダ (<ゲームルート>\InstantaleSDMod)
function Get-ModPaths {
    $cfg = Join-Path $script:GameDir $script:CfgDirName
    return @{
        ProxySrc   = Join-Path $script:BaseDir 'mod_files\stable-diffusion-proxy.dll'
        XL         = Join-Path $script:BaseDir 'mod_files\taesdxl.safetensors'
        S15        = Join-Path $script:BaseDir 'mod_files\taesd_sd15.safetensors'
        CfgDir     = $cfg
        Ini        = Join-Path $cfg 'sd_upscale.ini'
        Taesd      = Join-Path $script:GameDir 'runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors'
        LegacyReal = Join-Path $script:GameDir 'stable-diffusion-real.dll'
        Lcm        = Join-Path $script:GameDir 'runtime\models\sd15\lora\LCM_LoRA_SDXL.safetensors'
        CkptDir    = Join-Path $script:GameDir 'runtime\models\sd15\checkpoints'
    }
}

# いずれかのバックエンドの lib\stable-diffusion.dll があればゲームルートとみなす
function Test-GameRoot([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { return $false }
    foreach ($b in $script:Backends) {
        if (Test-Path (Join-Path $dir "$b\lib\stable-diffusion.dll")) { return $true }
    }
    return $false
}

# settings.ini から前回のゲームルートを読む (旧 bat は ANSI で書いたため両対応)
function Read-GameDirSetting {
    $p = Join-Path $script:BaseDir 'settings.ini'
    if (-not (Test-Path $p)) { return $null }
    foreach ($enc in ([System.Text.Encoding]::UTF8), $script:AnsiEnc) {
        foreach ($line in [System.IO.File]::ReadAllLines($p, $enc)) {
            $t = $line.Trim()
            if ($t -eq '' -or $t[0] -eq ';' -or $t[0] -eq '#') { continue }
            $eq = $t.IndexOf('=')
            if ($eq -lt 0) { continue }
            if ($t.Substring(0, $eq).Trim() -ieq 'game_dir') {
                $v = $t.Substring($eq + 1).Trim().TrimEnd('\')
                if (Test-GameRoot $v) { return $v }
            }
        }
    }
    return $null
}

function Save-GameDirSetting([string]$dir) {
    $lines = @(
        '; InstantaleStableDiffusionMod が自動生成する設定ファイル',
        '; game_dir = ゲームルート (前回検出/指定したパス)',
        "game_dir=$dir\")
    [System.IO.File]::WriteAllLines((Join-Path $script:BaseDir 'settings.ini'), $lines,
        (New-Object System.Text.UTF8Encoding($false)))
}

# ゲームルートを settings.ini → MOD フォルダの上位探索の順で解決 (無ければ $null)
function Find-GameRoot {
    $saved = Read-GameDirSetting
    if ($saved) { return (Resolve-Path -LiteralPath $saved).Path.TrimEnd('\') }
    $d = $script:BaseDir
    for ($i = 0; $i -lt 5; $i++) {
        if (Test-GameRoot $d) { return (Resolve-Path -LiteralPath $d).Path.TrimEnd('\') }
        $parent = Split-Path -Parent $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

# 2 つのファイルが同一内容か (TAESD の系統判定に使用。旧 bat の fc /b 相当)
function Test-SameFile([string]$a, [string]$b) {
    if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) { return $false }
    if ((Get-Item -LiteralPath $a).Length -ne (Get-Item -LiteralPath $b).Length) { return $false }
    return (Get-FileHash -LiteralPath $a -Algorithm MD5).Hash -eq (Get-FileHash -LiteralPath $b -Algorithm MD5).Hash
}

# 現在のモード: sdxl / sd15 / fresh (SDXL 化の痕跡なし = ゲーム標準の SD1.5) / unknown
function Get-CurrentMode {
    $p = Get-ModPaths
    if (-not (Test-Path $p.Taesd)) { return 'unknown' }
    if (Test-SameFile $p.Taesd $p.XL)  { return 'sdxl' }
    if (Test-SameFile $p.Taesd $p.S15) { return 'sd15' }
    if (-not (Test-Path $p.S15)) { return 'fresh' }
    return 'unknown'
}

function Write-MLog([string]$msg) {
    if ($c -and $c['TxtMLog']) {
        $c['TxtMLog'].AppendText($msg + "`r`n")
        $c['TxtMLog'].ScrollToEnd()
    }
}

# 設定フォルダ (<ゲームルート>\InstantaleSDMod) を用意し、旧配置の
# sd_upscale.ini (v2.0: MOD ツールフォルダ内 / v1.x: ゲームルート直下) を
# 新しい設定フォルダへ移行する
function Initialize-ConfigDir {
    $p = Get-ModPaths
    if (-not (Test-Path $p.CfgDir)) {
        New-Item -ItemType Directory -Path $p.CfgDir -Force | Out-Null
        Write-MLog "  [ok] 設定フォルダ $($p.CfgDir) を作成しました"
    }
    foreach ($legacy in @((Join-Path $script:BaseDir 'sd_upscale.ini'),
                          (Join-Path $script:GameDir 'sd_upscale.ini'))) {
        if ($legacy -ieq $p.Ini) { continue }
        if (-not (Test-Path -LiteralPath $legacy)) { continue }
        if (Test-Path $p.Ini) {
            Move-Item -LiteralPath $legacy -Destination "$($p.Ini).old" -Force
            Write-MLog "  [ok] 旧配置の sd_upscale.ini ($legacy) を sd_upscale.ini.old として移行しました"
        } else {
            Move-Item -LiteralPath $legacy -Destination $p.Ini -Force
            Write-MLog "  [ok] 旧配置の sd_upscale.ini ($legacy) を設定フォルダへ移行しました"
        }
    }
}

# 1 バックエンドへプロキシを導入。バックエンド自体が無ければ $false。
# 「既にプロキシだが退避 DLL が無い」場合は throw (呼び出し側でログして続行)
function Install-ProxyOne([string]$b) {
    $p = Get-ModPaths
    $lib  = Join-Path $script:GameDir "$b\lib\stable-diffusion.dll"
    $real = Join-Path $script:GameDir "$b\lib\stable-diffusion-real.dll"
    if (-not (Test-Path $lib)) { return $false }
    if ((Get-Item $lib).Length -gt 10000000) {
        # 元 DLL がまだ入っている → lib\stable-diffusion-real.dll へ退避
        if (Test-Path $real) {
            Write-MLog "  [ok] ${b}: 退避済みの元 DLL が既にあります。そのまま使用します"
        } else {
            Write-MLog "  [ok] ${b}: 元の DLL を lib\stable-diffusion-real.dll へ保存中 ... しばらく時間がかかります"
            Copy-Item -LiteralPath $lib -Destination $real -Force
        }
    } else {
        # 既にプロキシ: 退避済みの元 DLL があるか確認
        if (-not (Test-Path $real)) {
            if ($b -eq 'sdcpp_cuda' -and (Test-Path $p.LegacyReal)) {
                Write-MLog "  [ok] ${b}: 旧版 (v1) の退避先 (ゲームルートの stable-diffusion-real.dll) を元 DLL として使用します"
            } else {
                throw "${b}: lib\stable-diffusion.dll は既にプロキシですが、退避された元 DLL ($real) がありません。元の stable-diffusion.dll を ${b}\lib\ に戻してから再実行してください。"
            }
        }
    }
    Copy-Item -LiteralPath $p.ProxySrc -Destination $lib -Force
    # v2.0 以前が lib\ に置いていたポインタ ini (mod_dir=) は廃止したので掃除する
    $stalePtr = Join-Path $script:GameDir "$b\lib\stable-diffusion-proxy.ini"
    if (Test-Path $stalePtr) { Remove-Item -LiteralPath $stalePtr -Force }
    Write-MLog "  [ok] ${b}: プロキシを導入しました"
    return $true
}

# sd_upscale.<mode>.ini プリセットから sd_upscale.ini を作る
# ($backup = 上書き前に .bak を残す。導入時のみ)
function Use-IniPreset([string]$mode, [bool]$backup) {
    $p = Get-ModPaths
    $preset = Join-Path $script:BaseDir "sd_upscale.$mode.ini"
    if (Test-Path $preset) {
        if ($backup -and (Test-Path $p.Ini)) { Copy-Item -LiteralPath $p.Ini -Destination "$($p.Ini).bak" -Force }
        Copy-Item -LiteralPath $preset -Destination $p.Ini -Force
        Write-MLog "  [ok] sd_upscale.ini を sd_upscale.$mode.ini から読み込みました"
    } else {
        Write-MLog "  [警告] sd_upscale.$mode.ini が見つかりません - 現在の sd_upscale.ini を維持します。[upscale] / [lora_map] が $mode 用の値になっているか確認してください"
    }
}

# 任意の ini ファイルを、実際に読み込まれる設定 (InstantaleSDMod\sd_upscale.ini)
# としてそのままコピーして適用する。自動のモード切替 (プリセット入れ替え) を
# 使わず、設定ファイルを手動で管理したい人向けの導線
function Import-IniFile([string]$src) {
    $p = Get-ModPaths
    Write-MLog "=== 既存の ini を適用 ($(Get-Date -Format 'HH:mm:ss')) ==="
    if (-not (Test-Path -LiteralPath $src)) { throw "$src が見つかりません。" }
    if (-not (Test-Path $p.CfgDir)) {
        New-Item -ItemType Directory -Path $p.CfgDir -Force | Out-Null
        Write-MLog "  [ok] 設定フォルダ $($p.CfgDir) を作成しました"
    }
    if ((Resolve-Path -LiteralPath $src).Path -ieq $p.Ini) {
        Write-MLog '  [ok] 選択されたファイルは適用中の sd_upscale.ini 自身です - 変更はありません'
        return
    }
    if (Test-Path $p.Ini) {
        Copy-Item -LiteralPath $p.Ini -Destination "$($p.Ini).bak" -Force
        Write-MLog '  [ok] 現在の sd_upscale.ini を sd_upscale.ini.bak に退避しました'
    }
    Copy-Item -LiteralPath $src -Destination $p.Ini -Force
    Write-MLog "  [ok] $src を sd_upscale.ini として適用しました"
    Write-MLog '  注意: ini の内容 ([upscale] / [lora_map]) が現在のモード (SD1.5/SDXL) と合っているか確認してください (系統違いは画像の破綻やクラッシュの原因)。'
    Write-MLog '  完了。次の画像生成から反映されます (ゲームの再起動は不要)。'
}

# 導入 / 修復 (旧 install_sd15.bat / install_sdxl.bat)。冪等なので何度でも実行可
function Install-Mode([string]$mode) {
    $p = Get-ModPaths
    $label = 'SD1.5'
    if ($mode -eq 'sdxl') { $label = 'SDXL' }
    Write-MLog "=== $label モードで導入 / 修復 ($(Get-Date -Format 'HH:mm:ss')) ==="
    Write-MLog "  ゲームルート: $script:GameDir"
    if (-not (Test-Path $p.ProxySrc)) { throw 'mod_files\stable-diffusion-proxy.dll が見つかりません。配布 zip 全体を展開してください。' }
    if (-not (Test-Path $p.Taesd))    { throw "$($p.Taesd) が見つかりません。ゲームのファイル構成を確認してください。" }

    if ($mode -eq 'sdxl') {
        # 必須 / 要ダウンロードのファイル確認 (TAESDXL は同梱していない)
        if (-not (Test-Path $p.XL)) {
            throw ("mod_files\taesdxl.safetensors が見つかりません (SDXL モードに必要)。`n" +
                   "TAESDXL は同梱されていません。ダウンロードして保存してください:`n" +
                   "$script:UrlTaesdXL`n保存先: $($p.XL)`n(README_SDXL_MOD.txt の 2 章を参照)")
        }
        Write-MLog '  [ok] TAESDXL を確認しました'
        if (Test-Path (Join-Path $p.CkptDir $script:SdxlCkpt)) {
            Write-MLog "  [ok] SDXL チェックポイント $script:SdxlCkpt を確認しました"
        } else {
            Write-MLog "  [警告] SDXL チェックポイントが $($p.CkptDir)\ に見つかりません (README_SDXL_MOD.txt の 2 章を参照)。別の SDXL チェックポイントを使う場合はこの警告は無視して構いません"
        }
        if (-not (Test-Path $p.Lcm)) {
            Write-MLog "  [警告] LCM-LoRA が見つかりません ($($p.Lcm))。sd_upscale.ini で背景を LCM サンプラーに戻す場合のみ必要です"
        }
    }

    # プロキシ DLL (存在するすべてのバックエンドへ)
    $done = 0
    foreach ($b in $script:Backends) {
        try { if (Install-ProxyOne $b) { $done++ } }
        catch { Write-MLog "  [エラー] $($_.Exception.Message)" }
    }
    if ($done -eq 0) { throw 'プロキシを導入できたバックエンドがありません。上のログを確認してください。' }

    # TAESD デコーダ
    if ($mode -eq 'sd15') {
        if (Test-Path $p.S15) {
            Copy-Item -LiteralPath $p.S15 -Destination $p.Taesd -Force
            Write-MLog '  [ok] SD1.5 用 TAESD を退避ファイルから復元しました'
        } else {
            Write-MLog '  [ok] SDXL 導入の痕跡なし - ゲーム標準の SD1.5 用 TAESD をそのまま使います'
        }
    } else {
        # 初回の SDXL 化でゲーム標準の SD1.5 用 TAESD を退避 (後で復元に使う)
        if (-not (Test-Path $p.S15) -and -not (Test-SameFile $p.Taesd $p.XL)) {
            Copy-Item -LiteralPath $p.Taesd -Destination $p.S15 -Force
            Write-MLog '  [ok] ゲーム標準の SD1.5 用 TAESD を mod_files\taesd_sd15.safetensors に退避しました'
        }
        Copy-Item -LiteralPath $p.XL -Destination $p.Taesd -Force
        Write-MLog '  [ok] TAESDXL をデコーダとして導入しました'
    }

    # sd_upscale.ini (モード別プリセット) を設定フォルダへ
    Initialize-ConfigDir
    Use-IniPreset $mode $true
    Save-GameDirSetting $script:GameDir
    Write-MLog "  完了。ゲームを起動し、ゲーム内で $label 系統のチェックポイントを選んでください。"
}

# モード切替 (旧 switch_sd_mode.bat)。プロキシ DLL は両モード共通のため触らず、
# TAESD デコーダと sd_upscale.ini だけを入れ替える
function Switch-Mode([string]$target) {
    $p = Get-ModPaths
    Write-MLog "=== $target モードへ切替 ($(Get-Date -Format 'HH:mm:ss')) ==="
    if (-not (Test-Path $p.Taesd)) { throw "$($p.Taesd) が見つかりません。ゲームのファイル構成を確認してください。" }
    Initialize-ConfigDir
    $cur = Get-CurrentMode
    if ($cur -eq 'fresh') { $cur = 'sd15' }

    # 切替先に必要なデコーダファイルの確認
    if ($target -eq 'sdxl' -and -not (Test-Path $p.XL)) {
        throw ("mod_files\taesdxl.safetensors が見つかりません (SDXL モードに必要)。`n" +
               "TAESDXL は同梱されていません。ダウンロードして保存してください:`n" +
               "$script:UrlTaesdXL`n保存先: $($p.XL)")
    }
    if ($target -eq 'sd15' -and -not (Test-Path $p.S15) -and (Test-SameFile $p.Taesd $p.XL)) {
        throw ("mod_files\taesd_sd15.safetensors が見つかりません。`n" +
               "通常は SDXL 導入時に自動退避されます。SD1.5 用 TAESD をダウンロードして保存してください:`n" +
               "$script:UrlTaesd15`n保存先: $($p.S15)")
    }

    # 現在のモードの調整を sd_upscale.<現モード>.ini に保存してから、切替先を読み込む
    if (($cur -eq 'sd15' -or $cur -eq 'sdxl') -and (Test-Path $p.Ini)) {
        Copy-Item -LiteralPath $p.Ini -Destination (Join-Path $script:BaseDir "sd_upscale.$cur.ini") -Force
        Write-MLog "  [ok] 現在の sd_upscale.ini を sd_upscale.$cur.ini に保存しました"
    }
    Use-IniPreset $target $false

    # TAESD デコーダの入れ替え
    if ($target -eq 'sdxl') {
        Copy-Item -LiteralPath $p.XL -Destination $p.Taesd -Force
    } elseif (Test-Path $p.S15) {
        Copy-Item -LiteralPath $p.S15 -Destination $p.Taesd -Force
    }
    Write-MLog "  [ok] TAESD デコーダを $target 用に設定しました"

    Save-GameDirSetting $script:GameDir
    Write-MLog "  完了。ゲーム内で $target 系統のチェックポイントを選んでください (系統違いは画像の破綻やクラッシュの原因)。"
}

# アンインストール: ゲーム側の変更をすべて元に戻す (MOD フォルダ自体は残す)
function Uninstall-Mod {
    $p = Get-ModPaths
    Write-MLog "=== アンインストール / 原状復帰 ($(Get-Date -Format 'HH:mm:ss')) ==="
    $fail = 0
    foreach ($b in $script:Backends) {
        $lib  = Join-Path $script:GameDir "$b\lib\stable-diffusion.dll"
        $real = Join-Path $script:GameDir "$b\lib\stable-diffusion-real.dll"
        $ptr  = Join-Path $script:GameDir "$b\lib\stable-diffusion-proxy.ini"
        if (-not (Test-Path $lib)) { continue }
        $isProxy = ((Get-Item $lib).Length -le 10000000)
        if (Test-Path $real) {
            if ($isProxy) {
                Write-MLog "  [ok] ${b}: 元の DLL を書き戻し中 ... しばらく時間がかかります"
                Copy-Item -LiteralPath $real -Destination $lib -Force
            }
            Remove-Item -LiteralPath $real -Force
            Write-MLog "  [ok] ${b}: 元の DLL に戻し、退避ファイルを削除しました"
        } elseif ($isProxy) {
            if ($b -eq 'sdcpp_cuda' -and (Test-Path $p.LegacyReal)) {
                Write-MLog "  [ok] ${b}: 旧版 (v1) の退避先から元の DLL を書き戻しました"
                Copy-Item -LiteralPath $p.LegacyReal -Destination $lib -Force
            } else {
                Write-MLog "  [エラー] ${b}: プロキシですが退避された元 DLL がありません。元の stable-diffusion.dll を手動で戻してください"
                $fail++
            }
        }
        if (Test-Path $ptr) { Remove-Item -LiteralPath $ptr -Force }
    }
    # 旧版 (v1) の退避ファイルは、復元が済んでいれば削除する
    if (Test-Path $p.LegacyReal) {
        $cudaLib = Join-Path $script:GameDir 'sdcpp_cuda\lib\stable-diffusion.dll'
        if ((Test-Path $cudaLib) -and ((Get-Item $cudaLib).Length -gt 10000000)) {
            Remove-Item -LiteralPath $p.LegacyReal -Force
            Write-MLog '  [ok] 旧版の退避ファイル (ゲームルートの stable-diffusion-real.dll) を削除しました'
        }
    }
    # TAESD デコーダを SD1.5 版へ復元
    if ((Test-Path $p.S15) -and (Test-Path $p.Taesd) -and -not (Test-SameFile $p.Taesd $p.S15)) {
        Copy-Item -LiteralPath $p.S15 -Destination $p.Taesd -Force
        Write-MLog '  [ok] TAESD デコーダを SD1.5 版に復元しました'
    }
    # 設定フォルダ (<ゲームルート>\InstantaleSDMod) を削除
    # (この MOD ツール自身がその中に置かれている場合は残す)
    if (Test-Path $p.CfgDir) {
        if (($script:BaseDir -ieq $p.CfgDir) -or ($script:BaseDir -like (Join-Path $p.CfgDir '*'))) {
            Write-MLog '  [ok] 設定フォルダはこのツール自身が入っているため残しました (フォルダごと手動で削除してください)'
        } else {
            Remove-Item -LiteralPath $p.CfgDir -Recurse -Force
            Write-MLog "  [ok] 設定フォルダ $($p.CfgDir) を削除しました"
        }
    }
    if ($fail -gt 0) {
        Write-MLog "  [警告] $fail 件のバックエンドを復元できませんでした (上のログを参照)"
    } else {
        Write-MLog '  完了。ゲーム側の変更はすべて元に戻りました。'
    }
    Write-MLog '  MOD フォルダ (このツールを含む) は、不要になったらフォルダごと手動で削除してください。'
}

# 「導入 / 管理」タブの状態表示を更新する
function Update-ManageStatus {
    if (-not $script:GameDir) { $script:GameDir = Find-GameRoot }
    $ok = [bool]$script:GameDir
    foreach ($n in 'BtnInstall15', 'BtnInstallXL', 'BtnSwitch15', 'BtnSwitchXL', 'BtnUninstall', 'BtnLoadIni') { $c[$n].IsEnabled = $ok }
    if (-not $ok) {
        $c['TxtGameDir'].Text = '(未検出)'
        $c['LblMode'].Text = 'ゲームルート (instantale.exe のあるフォルダ) が見つかりません。「変更...」で指定してください。'
        $c['LblBackends'].Text = ''
        return
    }
    $c['TxtGameDir'].Text = $script:GameDir
    $p = Get-ModPaths

    $sb = New-Object System.Text.StringBuilder
    $anyProxy = $false
    $reverted = $false
    foreach ($b in $script:Backends) {
        $lib = Join-Path $script:GameDir "$b\lib\stable-diffusion.dll"
        if (-not (Test-Path $lib)) { continue }
        $real = Join-Path $script:GameDir "$b\lib\stable-diffusion-real.dll"
        $isProxy = ((Get-Item $lib).Length -le 10000000)
        if ($isProxy) {
            $anyProxy = $true
            $hasReal = (Test-Path $real) -or ($b -eq 'sdcpp_cuda' -and (Test-Path $p.LegacyReal))
            if ($hasReal) { $st = '導入済み (プロキシ)' }
            else { $st = '導入済み - ただし元 DLL の退避が見つかりません!' }
        } elseif (Test-Path $real) {
            $st = '未導入 (巻き戻りを検出 - 「導入 / 修復」を再実行してください)'
            $reverted = $true
        } else {
            $st = '未導入 (オリジナル)'
        }
        [void]$sb.AppendLine("$b : $st")
    }
    if ($sb.Length -eq 0) { [void]$sb.AppendLine('(バックエンドが見つかりません)') }
    $c['LblBackends'].Text = $sb.ToString().TrimEnd()

    $mode = Get-CurrentMode
    $modeText = '不明 (TAESD が SD1.5 / SDXL のどちらとも一致しません)'
    if ($mode -eq 'sdxl')  { $modeText = 'SDXL (TAESDXL 導入済み)' }
    if ($mode -eq 'sd15')  { $modeText = 'SD1.5' }
    if ($mode -eq 'fresh') { $modeText = 'SD1.5 (ゲーム標準)' }
    $head = 'MOD: 未導入'
    if ($anyProxy) { $head = 'MOD: 導入済み' }
    $text = "$head    モード: $modeText"
    if ($reverted) { $text += "`nランチャーの「ファイルの検証」等で一部が巻き戻っています。導入ボタンで復旧できます。" }
    $c['LblMode'].Text = $text
}

# ボタン共通: 確認 → 実行 → 状態更新とエディタの追従
function Invoke-ManageAction([string]$title, [scriptblock]$action, [string]$confirm) {
    if (-not $script:GameDir) { return }
    if ($confirm) {
        $r = [System.Windows.MessageBox]::Show($confirm, $title,
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }
    $win.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        & $action
    } catch {
        Write-MLog "  [エラー] $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, $title,
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    } finally {
        $win.Cursor = $null
        Update-ManageStatus
        # 導入 / 切替で sd_upscale.ini が変わった可能性があるためエディタを追従させる
        try {
            if ($script:GameDir) {
                $ini = (Get-ModPaths).Ini
                if (Test-Path $ini) { Open-IniFile $ini }
            }
        } catch { }
    }
}

# ------------------------------------------------------------------- 画面

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instantale SD MOD マネージャー" Width="940" Height="740"
        WindowStartupLocation="CenterScreen" FontSize="13">
  <DockPanel Margin="10">

    <DockPanel Name="PnlFile" DockPanel.Dock="Top" Margin="0,0,0,8" Visibility="Collapsed">
      <Button Name="BtnOpen" Content="開く..." Width="80" Padding="0,4" DockPanel.Dock="Right" Margin="6,0,0,0"/>
      <TextBlock Text="設定ファイル: " VerticalAlignment="Center"/>
      <TextBox Name="TxtFile" IsReadOnly="True" VerticalContentAlignment="Center" Background="#F4F4F4"/>
    </DockPanel>

    <DockPanel Name="PnlSave" DockPanel.Dock="Bottom" Margin="0,10,0,0" Visibility="Collapsed">
      <Button Name="BtnSave" Content="保存" Width="130" Height="32" FontWeight="Bold" DockPanel.Dock="Right"/>
      <Button Name="BtnReload" Content="再読込" Width="90" Height="32" DockPanel.Dock="Right" Margin="0,0,8,0"/>
      <TextBlock Name="LblStatus" VerticalAlignment="Center" Foreground="Gray" TextWrapping="Wrap"
                 Text="保存すると次の画像生成から反映されます (ゲームの再起動は不要)"/>
    </DockPanel>

    <TabControl Name="Tabs">

      <!-- ============================ 導入 / 管理 ============================ -->
      <TabItem Header=" 導入 / 管理 ">
        <DockPanel Margin="12">
          <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
            <TextBlock Text="ゲームルート: " VerticalAlignment="Center"/>
            <Button Name="BtnGameBrowse" Content="変更..." Width="80" Padding="0,4" DockPanel.Dock="Right" Margin="6,0,0,0"/>
            <Button Name="BtnRefresh" Content="状態を再確認" Width="110" Padding="0,4" DockPanel.Dock="Right" Margin="6,0,0,0"/>
            <TextBox Name="TxtGameDir" IsReadOnly="True" VerticalContentAlignment="Center" Background="#F4F4F4"/>
          </DockPanel>

          <GroupBox DockPanel.Dock="Top" Header="現在の状態" Padding="8" Margin="0,0,0,8">
            <StackPanel>
              <TextBlock Name="LblMode" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,4"/>
              <TextBlock Name="LblBackends" FontFamily="Consolas" TextWrapping="Wrap"/>
            </StackPanel>
          </GroupBox>

          <GroupBox DockPanel.Dock="Top" Header="操作 (必ずゲームを閉じた状態で実行してください)" Padding="8" Margin="0,0,0,8">
            <StackPanel>
              <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,6"
                Text="導入は何度実行しても安全です (冪等)。ランチャーの「ファイルの検証」や自動アップデートで MOD が巻き戻った場合も、同じボタンで復旧できます。SDXL モードは事前に TAESDXL などのダウンロードが必要です (README_SDXL_MOD.txt の 2 章)。"/>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                <Button Name="BtnInstall15" Content="SD1.5 モードで導入 / 修復" Width="200" Height="32" FontWeight="Bold" Margin="0,0,8,0"/>
                <Button Name="BtnInstallXL" Content="SDXL モードで導入 / 修復" Width="200" Height="32" Margin="0,0,8,0"/>
              </StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                <TextBlock Text="モード切替: " VerticalAlignment="Center"/>
                <Button Name="BtnSwitch15" Content="SD1.5 へ" Width="90" Height="28" Margin="0,0,8,0"/>
                <Button Name="BtnSwitchXL" Content="SDXL へ" Width="90" Height="28" Margin="0,0,8,0"/>
                <Button Name="BtnUninstall" Content="アンインストール (原状復帰)" Width="200" Height="28" Margin="24,0,0,0"/>
              </StackPanel>
              <StackPanel Orientation="Horizontal">
                <Button Name="BtnLoadIni" Content="既存の ini を読み込んで適用..." Width="200" Height="28" Margin="0,0,8,0"/>
                <TextBlock Foreground="Gray" VerticalAlignment="Center" TextWrapping="Wrap"
                  Text="モード切替 (ini の自動入れ替え) を使わず、選んだ ini をそのまま設定として使います"/>
              </StackPanel>
            </StackPanel>
          </GroupBox>

          <TextBox Name="TxtMLog" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"
                   Background="#FAFAFA" Text="ここに操作の結果が表示されます。&#10;"/>
        </DockPanel>
      </TabItem>

      <!-- ============================ 解像度 ============================ -->
      <TabItem Header=" 解像度 ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <CheckBox Name="ChkEnabled" Content="アップスケールを有効にする (オフ = ゲーム本来のサイズのまま)" Margin="0,0,0,10" FontWeight="Bold"/>

            <GroupBox Header="縦長・正方形 (キャラ / アイテムなど)" Padding="8" Margin="0,0,0,8">
              <StackPanel>
                <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,6"
                  Text="倍率 = min(短辺の目標 ÷ 短辺, 長辺の上限 ÷ 長辺)。アスペクト比は維持され、両辺が丸めの倍数に丸められます。SD1.5 の目安: 832/1216 (安全圏)、SDXL: 1024/2048。"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="短辺の目標 px:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox Name="TxtGoalShort" Grid.Column="1" VerticalContentAlignment="Center"/>
                  <TextBlock Text="長辺の上限 px:" Grid.Column="2" VerticalAlignment="Center" Margin="14,0,6,0"/>
                  <TextBox Name="TxtMaxLong" Grid.Column="3" VerticalContentAlignment="Center"/>
                  <TextBlock Text="丸め (倍数):" Grid.Column="4" VerticalAlignment="Center" Margin="14,0,6,0"/>
                  <TextBox Name="TxtRound" Grid.Column="5" VerticalContentAlignment="Center"/>
                </Grid>
              </StackPanel>
            </GroupBox>

            <GroupBox Header="横長 (背景) の上書き" Padding="8" Margin="0,0,0,8">
              <StackPanel>
                <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,6"
                  Text="0 にすると上の値を流用します。背景を大きくしすぎると VRAM 不足でゲームごと落ちることがあります (SDXL の目安: 704/1408)。"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="短辺の目標 px:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox Name="TxtGoalShortLand" Grid.Column="1" VerticalContentAlignment="Center"/>
                  <TextBlock Text="長辺の上限 px:" Grid.Column="2" VerticalAlignment="Center" Margin="14,0,6,0"/>
                  <TextBox Name="TxtMaxLongLand" Grid.Column="3" VerticalContentAlignment="Center"/>
                </Grid>
              </StackPanel>
            </GroupBox>

            <GroupBox Header="画像の種類別の有効 / 無効" Padding="8" Margin="0,0,0,8">
              <StackPanel Orientation="Horizontal">
                <CheckBox Name="ChkEnPortrait" Content="portrait (キャラ / 縦長)" Margin="0,0,20,0"/>
                <CheckBox Name="ChkEnLandscape" Content="landscape (背景 / 横長)" Margin="0,0,20,0"/>
                <CheckBox Name="ChkEnSquare" Content="square (その他 / 正方形)"/>
              </StackPanel>
            </GroupBox>

            <GroupBox Header="特定プロンプトのスキップ (一致した生成はアップスケールしない)" Padding="8">
              <StackPanel>
                <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,6"
                  Text="語を「/」区切りで複数指定、どれか 1 つ含まれれば成立。先頭に ! を付けた語は「含まれない」ことが条件 (すべて必須)。単語境界つき・大文字小文字不問。例: pixel art/sprite。「有効」のチェックを外すと、内容を残したまま無効化できます。"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <Grid.RowDefinitions>
                    <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
                  </Grid.RowDefinitions>
                  <TextBlock Text="全種類共通:" VerticalAlignment="Center"/>
                  <TextBox Name="TxtSkipAny" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                  <CheckBox Name="ChkSkipAny" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                  <TextBlock Text="portrait のみ:" Grid.Row="1" VerticalAlignment="Center"/>
                  <TextBox Name="TxtSkipP" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                  <CheckBox Name="ChkSkipP" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                  <TextBlock Text="landscape のみ:" Grid.Row="2" VerticalAlignment="Center"/>
                  <TextBox Name="TxtSkipL" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                  <CheckBox Name="ChkSkipL" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                  <TextBlock Text="square のみ:" Grid.Row="3" VerticalAlignment="Center"/>
                  <TextBox Name="TxtSkipS" Grid.Row="3" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                  <CheckBox Name="ChkSkipS" Content="有効" Grid.Row="3" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                </Grid>
              </StackPanel>
            </GroupBox>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ============================ LoRA 付替 ============================ -->
      <TabItem Header=" LoRA 付替 ">
        <DockPanel Margin="12">
          <TextBlock DockPanel.Dock="Top" Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
            Text="[lora_map] ゲームが要求する LoRA の付け替え / 無効化。実ファイル名は拡張子 .safetensors 不要、「:強度」を付けられます (例: LCM_LoRA_SDXL:1.0)。「off」でその LoRA を適用しません。SDXL モデル使用中は SD1.5 用 LoRA を必ず off にすること (クラッシュ防止)。「有効」のチェックを外した行は、内容を残したまま無効化されます。"/>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
            <Button Name="BtnMapAdd" Content="行を追加" Width="100" Padding="0,4" Margin="0,0,8,0"/>
            <Button Name="BtnMapDel" Content="選択行を削除" Width="110" Padding="0,4"/>
          </StackPanel>
          <DataGrid Name="GridLoraMap" AutoGenerateColumns="False" CanUserAddRows="False"
                    HeadersVisibility="Column" RowHeight="26">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="有効" Binding="{Binding Enabled, UpdateSourceTrigger=PropertyChanged}" Width="46"/>
              <DataGridTextColumn Header="ゲーム内の名前" Binding="{Binding Name}" Width="2*"/>
              <DataGridTextColumn Header="実ファイル名[:強度] / off" Binding="{Binding Target}" Width="3*"/>
            </DataGrid.Columns>
          </DataGrid>
        </DockPanel>
      </TabItem>

      <!-- ============================ 追加 ============================ -->
      <TabItem Header=" プロンプト追加 ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
              Text="画像の種類ごとに (ネガティブ) プロンプトの末尾へ追加します。&lt;lora:ファイル名:強度&gt; の LoRA タグも、普通のタグも書けます。空欄 = 追加しない。「有効」のチェックを外すと、内容を残したまま無効化できます。"/>
            <GroupBox Header="プロンプトへ追加 [lora_add]" Padding="8" Margin="0,0,0,8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtAddP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkAddP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtAddL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkAddL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtAddS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkAddS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
            <GroupBox Header="ネガティブプロンプトへ追加 [negative_add]" Padding="8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegAddP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegAddP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegAddL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegAddL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegAddS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegAddS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ============================ 条件付き追加 ============================ -->
      <TabItem Header=" 条件付き追加 ">
        <DockPanel Margin="12">
          <TextBlock DockPanel.Dock="Top" Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
            Text="[lora_add_if] ゲーム本来のプロンプトに特定の語を含む場合だけ末尾へ追記します (男女で LoRA 切替など)。クラスは portrait / landscape / square / any。条件は「/」区切りでどれか 1 つ含まれれば成立、!語 は「含まれない」ことが条件。例:  1boy/male/man  →  &lt;lora:maleStyle:0.8&gt;。「有効」のチェックを外した行は、内容を残したまま無効化されます。"/>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
            <Button Name="BtnRuleAdd" Content="行を追加" Width="100" Padding="0,4" Margin="0,0,8,0"/>
            <Button Name="BtnRuleDel" Content="選択行を削除" Width="110" Padding="0,4"/>
          </StackPanel>
          <DataGrid Name="GridRules" AutoGenerateColumns="False" CanUserAddRows="False"
                    HeadersVisibility="Column" RowHeight="26">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="有効" Binding="{Binding Enabled, UpdateSourceTrigger=PropertyChanged}" Width="46"/>
              <DataGridTextColumn Header="ルール名 (任意)" Binding="{Binding Name}" Width="*"/>
              <DataGridTextColumn Header="クラス" Binding="{Binding Cls}" Width="*"/>
              <DataGridTextColumn Header="条件 (語1/語2/!語3)" Binding="{Binding Cond}" Width="2*"/>
              <DataGridTextColumn Header="追加内容" Binding="{Binding Add}" Width="3*"/>
            </DataGrid.Columns>
          </DataGrid>
        </DockPanel>
      </TabItem>

      <!-- ============================ 除去 ============================ -->
      <TabItem Header=" タグ除去 ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
              Text="ゲームの (ネガティブ) プロンプトから、カンマ区切りで指定したタグを取り除きます。1 区画単位・大文字小文字不問の完全一致 (watercolor と書いても watercolor painting は消えません)。例: medieval, dark fantasy, watercolor。「有効」のチェックを外すと、内容を残したまま無効化できます。"/>
            <GroupBox Header="プロンプトから除去 [prompt_remove]" Padding="8" Margin="0,0,0,8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtRmP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRmP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtRmL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRmL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtRmS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRmS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
            <GroupBox Header="ネガティブプロンプトから除去 [negative_remove]" Padding="8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRmP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRmP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRmL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRmL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRmS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRmS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ============================ 置換 ============================ -->
      <TabItem Header=" 完全置き換え ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
              Text="記入したクラスは (ネガティブ) プロンプトが丸ごとここの内容になります。{prompt} と書いた位置にゲーム本来のプロンプトが埋め込まれます。{prompt} 無しだと毎回ほぼ同じ絵になるので注意。空欄 = 置換しない。例: 1girl, solo, {prompt}, masterpiece, best quality。「有効」のチェックを外すと、内容を残したまま無効化できます。"/>
            <GroupBox Header="プロンプトの置き換え [prompt_replace]" Padding="8" Margin="0,0,0,8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtRpP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRpP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtRpL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRpL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtRpS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkRpS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
            <GroupBox Header="ネガティブプロンプトの置き換え [negative_replace]" Padding="8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="portrait (キャラ):" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRpP" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRpP" Content="有効" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="landscape (背景):" Grid.Row="1" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRpL" Grid.Row="1" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRpL" Content="有効" Grid.Row="1" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
                <TextBlock Text="square (その他):" Grid.Row="2" VerticalAlignment="Center"/>
                <TextBox Name="TxtNegRpS" Grid.Row="2" Grid.Column="1" Margin="0,2" VerticalContentAlignment="Center"/>
                <CheckBox Name="ChkNegRpS" Content="有効" Grid.Row="2" Grid.Column="2" VerticalAlignment="Center" Margin="8,0,0,0"/>
              </Grid>
            </GroupBox>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ============================ サンプラー ============================ -->
      <TabItem Header=" サンプラー ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <TextBlock Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,8"
              Text="画像の種類別にサンプラー設定を上書きします。空欄 = ゲームの設定のまま。おすすめ: euler_a / 24 / cfg 5.0 (無難)、dpm++2m + karras / 15～20 / 5.0 (高品質でやや速い)。lcm はゲーム標準の LCM LoRA 専用 (4～8 steps, cfg 1～2)。【重要】通常サンプラーへ差し替える間は「LoRA 付替」タブで LCM_LoRA_Weights_SD15 = off にすること。"/>
            <GroupBox Header="portrait (キャラ)" Padding="8" Margin="0,0,0,8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="150"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="サンプラー:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="CmbMethodP" Grid.Column="1" IsEditable="True"/>
                <TextBlock Text="スケジューラ:" Grid.Column="2" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <ComboBox Name="CmbSchedP" Grid.Column="3" IsEditable="True"/>
                <TextBlock Text="steps:" Grid.Column="4" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtStepsP" Grid.Column="5" VerticalContentAlignment="Center"/>
                <TextBlock Text="cfg:" Grid.Column="6" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtCfgP" Grid.Column="7" VerticalContentAlignment="Center"/>
              </Grid>
            </GroupBox>
            <GroupBox Header="landscape (背景)" Padding="8" Margin="0,0,0,8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="150"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="サンプラー:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="CmbMethodL" Grid.Column="1" IsEditable="True"/>
                <TextBlock Text="スケジューラ:" Grid.Column="2" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <ComboBox Name="CmbSchedL" Grid.Column="3" IsEditable="True"/>
                <TextBlock Text="steps:" Grid.Column="4" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtStepsL" Grid.Column="5" VerticalContentAlignment="Center"/>
                <TextBlock Text="cfg:" Grid.Column="6" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtCfgL" Grid.Column="7" VerticalContentAlignment="Center"/>
              </Grid>
            </GroupBox>
            <GroupBox Header="square (その他)" Padding="8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="150"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="130"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="Auto"/><ColumnDefinition Width="60"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="サンプラー:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <ComboBox Name="CmbMethodS" Grid.Column="1" IsEditable="True"/>
                <TextBlock Text="スケジューラ:" Grid.Column="2" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <ComboBox Name="CmbSchedS" Grid.Column="3" IsEditable="True"/>
                <TextBlock Text="steps:" Grid.Column="4" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtStepsS" Grid.Column="5" VerticalContentAlignment="Center"/>
                <TextBlock Text="cfg:" Grid.Column="6" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox Name="TxtCfgS" Grid.Column="7" VerticalContentAlignment="Center"/>
              </Grid>
            </GroupBox>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

    </TabControl>
  </DockPanel>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)

$names = @(
    'ChkEnabled','TxtGoalShort','TxtMaxLong','TxtRound','TxtGoalShortLand','TxtMaxLongLand',
    'ChkEnPortrait','ChkEnLandscape','ChkEnSquare',
    'TxtSkipAny','TxtSkipP','TxtSkipL','TxtSkipS',
    'ChkSkipAny','ChkSkipP','ChkSkipL','ChkSkipS',
    'GridLoraMap','BtnMapAdd','BtnMapDel',
    'TxtAddP','TxtAddL','TxtAddS','TxtNegAddP','TxtNegAddL','TxtNegAddS',
    'ChkAddP','ChkAddL','ChkAddS','ChkNegAddP','ChkNegAddL','ChkNegAddS',
    'GridRules','BtnRuleAdd','BtnRuleDel',
    'TxtRmP','TxtRmL','TxtRmS','TxtNegRmP','TxtNegRmL','TxtNegRmS',
    'ChkRmP','ChkRmL','ChkRmS','ChkNegRmP','ChkNegRmL','ChkNegRmS',
    'TxtRpP','TxtRpL','TxtRpS','TxtNegRpP','TxtNegRpL','TxtNegRpS',
    'ChkRpP','ChkRpL','ChkRpS','ChkNegRpP','ChkNegRpL','ChkNegRpS',
    'CmbMethodP','CmbSchedP','TxtStepsP','TxtCfgP',
    'CmbMethodL','CmbSchedL','TxtStepsL','TxtCfgL',
    'CmbMethodS','CmbSchedS','TxtStepsS','TxtCfgS',
    'TxtFile','BtnOpen','BtnReload','BtnSave','LblStatus','Tabs','PnlFile','PnlSave',
    'TxtGameDir','BtnGameBrowse','BtnRefresh','LblMode','LblBackends',
    'BtnInstall15','BtnInstallXL','BtnSwitch15','BtnSwitchXL','BtnUninstall','BtnLoadIni','TxtMLog'
)
$c = @{}
foreach ($n in $names) { $c[$n] = $win.FindName($n) }

$methods = @('', 'euler_a', 'euler', 'heun', 'dpm2', 'dpm++2s_a', 'dpm++2m', 'dpm++2mv2',
             'ipndm', 'ipndm_v', 'lcm', 'ddim_trailing', 'tcd')
$scheds  = @('', 'default', 'discrete', 'karras', 'exponential', 'ays', 'gits', 'smoothstep')
foreach ($k in 'CmbMethodP', 'CmbMethodL', 'CmbMethodS') { $c[$k].ItemsSource = $methods }
foreach ($k in 'CmbSchedP', 'CmbSchedL', 'CmbSchedS')    { $c[$k].ItemsSource = $scheds }

$script:MapColl  = New-Object 'System.Collections.ObjectModel.ObservableCollection[SdGui.MapEntry]'
$script:RuleColl = New-Object 'System.Collections.ObjectModel.ObservableCollection[SdGui.RuleEntry]'
$c['GridLoraMap'].ItemsSource = $script:MapColl
$c['GridRules'].ItemsSource   = $script:RuleColl

$script:IniPath = $null
$script:Lines   = $null

# ------------------------------------------------------- 読み込み → 画面へ

function Update-Controls($parsed) {
    $fx  = $parsed.Fx
    $dis = $parsed.Dis
    function V([string]$key, [string]$def = '') {
        if ($fx.ContainsKey($key)) { return $fx[$key] } else { return $def }
    }
    # テキスト欄と「有効」チェックの組を読み込む (";off:" 行はオフ状態で復元)
    function LoadPair([string]$txt, [string]$chk, [string]$key) {
        if ($fx.ContainsKey($key))      { $c[$txt].Text = $fx[$key];  $c[$chk].IsChecked = $true }
        elseif ($dis.ContainsKey($key)) { $c[$txt].Text = $dis[$key]; $c[$chk].IsChecked = $false }
        else                            { $c[$txt].Text = '';         $c[$chk].IsChecked = $true }
    }
    $c['ChkEnabled'].IsChecked      = ((V 'upscale/enabled' '1') -ne '0')
    $c['TxtGoalShort'].Text         = V 'upscale/goal_short'
    $c['TxtMaxLong'].Text           = V 'upscale/max_long'
    $c['TxtRound'].Text             = V 'upscale/round'
    $c['TxtGoalShortLand'].Text     = V 'upscale/goal_short_landscape'
    $c['TxtMaxLongLand'].Text       = V 'upscale/max_long_landscape'
    $c['ChkEnPortrait'].IsChecked   = ((V 'upscale/enabled_portrait'  '1') -ne '0')
    $c['ChkEnLandscape'].IsChecked  = ((V 'upscale/enabled_landscape' '1') -ne '0')
    $c['ChkEnSquare'].IsChecked     = ((V 'upscale/enabled_square'    '1') -ne '0')
    LoadPair 'TxtSkipAny' 'ChkSkipAny' 'upscale/skip_if'
    LoadPair 'TxtSkipP'   'ChkSkipP'   'upscale/skip_if_portrait'
    LoadPair 'TxtSkipL'   'ChkSkipL'   'upscale/skip_if_landscape'
    LoadPair 'TxtSkipS'   'ChkSkipS'   'upscale/skip_if_square'

    LoadPair 'TxtAddP'    'ChkAddP'    'lora_add/portrait';        LoadPair 'TxtAddL'    'ChkAddL'    'lora_add/landscape';        LoadPair 'TxtAddS'    'ChkAddS'    'lora_add/square'
    LoadPair 'TxtNegAddP' 'ChkNegAddP' 'negative_add/portrait';    LoadPair 'TxtNegAddL' 'ChkNegAddL' 'negative_add/landscape';    LoadPair 'TxtNegAddS' 'ChkNegAddS' 'negative_add/square'
    LoadPair 'TxtRmP'     'ChkRmP'     'prompt_remove/portrait';   LoadPair 'TxtRmL'     'ChkRmL'     'prompt_remove/landscape';   LoadPair 'TxtRmS'     'ChkRmS'     'prompt_remove/square'
    LoadPair 'TxtNegRmP'  'ChkNegRmP'  'negative_remove/portrait'; LoadPair 'TxtNegRmL'  'ChkNegRmL'  'negative_remove/landscape'; LoadPair 'TxtNegRmS'  'ChkNegRmS'  'negative_remove/square'
    LoadPair 'TxtRpP'     'ChkRpP'     'prompt_replace/portrait';  LoadPair 'TxtRpL'     'ChkRpL'     'prompt_replace/landscape';  LoadPair 'TxtRpS'     'ChkRpS'     'prompt_replace/square'
    LoadPair 'TxtNegRpP'  'ChkNegRpP'  'negative_replace/portrait'; LoadPair 'TxtNegRpL' 'ChkNegRpL'  'negative_replace/landscape'; LoadPair 'TxtNegRpS' 'ChkNegRpS'  'negative_replace/square'

    $c['CmbMethodP'].Text = V 'sampler/portrait_method';  $c['CmbSchedP'].Text = V 'sampler/portrait_scheduler'
    $c['TxtStepsP'].Text  = V 'sampler/portrait_steps';   $c['TxtCfgP'].Text   = V 'sampler/portrait_cfg'
    $c['CmbMethodL'].Text = V 'sampler/landscape_method'; $c['CmbSchedL'].Text = V 'sampler/landscape_scheduler'
    $c['TxtStepsL'].Text  = V 'sampler/landscape_steps';  $c['TxtCfgL'].Text   = V 'sampler/landscape_cfg'
    $c['CmbMethodS'].Text = V 'sampler/square_method';    $c['CmbSchedS'].Text = V 'sampler/square_scheduler'
    $c['TxtStepsS'].Text  = V 'sampler/square_steps';     $c['TxtCfgS'].Text   = V 'sampler/square_cfg'

    $script:MapColl.Clear()
    foreach ($m in $parsed.Map) {
        $e = New-Object SdGui.MapEntry; $e.Name = $m.Name; $e.Target = $m.Target; $e.Enabled = [bool]$m.Enabled
        $script:MapColl.Add($e)
    }
    $script:RuleColl.Clear()
    foreach ($r in $parsed.Rules) {
        $e = New-Object SdGui.RuleEntry; $e.Name = $r.Name; $e.Cls = $r.Cls; $e.Cond = $r.Cond; $e.Add = $r.Add; $e.Enabled = [bool]$r.Enabled
        $script:RuleColl.Add($e)
    }
}

function Open-IniFile([string]$path) {
    $raw = [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)
    $script:Lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $raw) { $script:Lines.Add($l) }
    Update-Controls (Read-IniValues $script:Lines)
    $script:IniPath = $path
    $c['TxtFile'].Text = $path
    $win.Title = "Instantale SD MOD マネージャー - $(Split-Path -Leaf $path)"
    $c['LblStatus'].Text = "読み込みました: $(Split-Path -Leaf $path)"
}

# ------------------------------------------------------- 画面 → 保存

function Get-IntField($tb, [string]$label, [int]$min, [int]$max) {
    $s = $tb.Text.Trim()
    if ($s -eq '') { return $null }
    $v = 0
    if (-not [int]::TryParse($s, [ref]$v)) { throw "$label : 整数で入力してください (入力値: $s)" }
    if ($v -lt $min -or $v -gt $max) { throw "$label : $min ～ $max の範囲で入力してください (入力値: $v)" }
    return $v
}

function Get-FloatField($tb, [string]$label, [double]$min, [double]$max) {
    $s = $tb.Text.Trim()
    if ($s -eq '') { return $null }
    $v = 0.0
    if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
        throw "$label : 数値で入力してください (入力値: $s)"
    }
    if ($v -le $min -or $v -gt $max) { throw "$label : $min より大きく $max 以下で入力してください (入力値: $v)" }
    return $v
}

# 値が空ならコメント化、あれば書き込み
function Set-OrClear($lines, [string]$section, [string]$key, [string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { Clear-IniKey $lines $section $key }
    else { Set-IniKey $lines $section $key $value.Trim() }
}

# 「有効」チェック付きの欄: 空ならコメント化、チェックありは通常書き込み、
# チェックなしは ";off:" 行として内容を保存する
function Set-OrClearChk($lines, [string]$section, [string]$key, [string]$value, [bool]$enabled) {
    if ([string]::IsNullOrWhiteSpace($value)) { Clear-IniKey $lines $section $key }
    elseif ($enabled) { Set-IniKey $lines $section $key $value.Trim() }
    else { Set-IniKeyDisabled $lines $section $key $value.Trim() }
}

function Save-IniFile {
    if (-not $script:IniPath) {
        [System.Windows.MessageBox]::Show('先に「開く...」で ini ファイルを読み込んでください。', 'Instantale SD MOD 設定') | Out-Null
        return
    }
    try {
        foreach ($g in $c['GridLoraMap'], $c['GridRules']) {
            $g.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
            $g.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        }

        # --- 検証 (プロキシ側の受理範囲と同じ) ---
        $goalShort = Get-IntField $c['TxtGoalShort'] '短辺の目標' 64 4096
        $maxLong   = Get-IntField $c['TxtMaxLong']   '長辺の上限' 64 8192
        $round     = Get-IntField $c['TxtRound']     '丸め'       8  256
        $goalLandS = Get-IntField $c['TxtGoalShortLand'] '横長: 短辺の目標' 0 4096
        $maxLandL  = Get-IntField $c['TxtMaxLongLand']   '横長: 長辺の上限' 0 8192

        $smp = @{}
        foreach ($cls in @(
                @{ K = 'portrait';  M = 'CmbMethodP'; C = 'CmbSchedP'; St = 'TxtStepsP'; Cf = 'TxtCfgP' },
                @{ K = 'landscape'; M = 'CmbMethodL'; C = 'CmbSchedL'; St = 'TxtStepsL'; Cf = 'TxtCfgL' },
                @{ K = 'square';    M = 'CmbMethodS'; C = 'CmbSchedS'; St = 'TxtStepsS'; Cf = 'TxtCfgS' })) {
            $smp[$cls.K] = @{
                Method = $c[$cls.M].Text.Trim()
                Sched  = $c[$cls.C].Text.Trim()
                Steps  = Get-IntField   $c[$cls.St] "$($cls.K) steps" 1 200
                Cfg    = Get-FloatField $c[$cls.Cf] "$($cls.K) cfg"   0 50
            }
        }

        $ruleLines = @()
        foreach ($r in $script:RuleColl) {
            if ([string]::IsNullOrWhiteSpace($r.Name) -and [string]::IsNullOrWhiteSpace($r.Cond) -and
                [string]::IsNullOrWhiteSpace($r.Add)) { continue }
            $cls = $r.Cls.Trim().ToLower()
            if ($cls -notin @('portrait', 'landscape', 'square', 'any')) {
                throw "条件付き追加「$($r.Name)」: クラスは portrait / landscape / square / any のいずれかにしてください (入力値: $($r.Cls))"
            }
            if ([string]::IsNullOrWhiteSpace($r.Name)) { throw '条件付き追加: ルール名が空の行があります' }
            if ([string]::IsNullOrWhiteSpace($r.Cond) -or [string]::IsNullOrWhiteSpace($r.Add)) {
                throw "条件付き追加「$($r.Name)」: 条件と追加内容の両方を入力してください"
            }
            $rl = "$($r.Name.Trim()) = $cls | $($r.Cond.Trim()) | $($r.Add.Trim())"
            if (-not $r.Enabled) { $rl = ";off: $rl" }
            $ruleLines += $rl
        }

        $mapLines = @()
        foreach ($m in $script:MapColl) {
            if ([string]::IsNullOrWhiteSpace($m.Name)) { continue }
            $ml = "$($m.Name.Trim()) = $($m.Target.Trim())"
            if (-not $m.Enabled) { $ml = ";off: $ml" }
            $mapLines += $ml
        }

        # --- 書き込み ---
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($l in $script:Lines) { $lines.Add($l) }

        Set-IniKey $lines 'upscale' 'enabled' $(if ($c['ChkEnabled'].IsChecked) { '1' } else { '0' })
        if ($null -ne $goalShort) { Set-IniKey $lines 'upscale' 'goal_short' $goalShort } else { Clear-IniKey $lines 'upscale' 'goal_short' }
        if ($null -ne $maxLong)   { Set-IniKey $lines 'upscale' 'max_long'   $maxLong }   else { Clear-IniKey $lines 'upscale' 'max_long' }
        if ($null -ne $round)     { Set-IniKey $lines 'upscale' 'round'      $round }     else { Clear-IniKey $lines 'upscale' 'round' }
        if ($null -ne $goalLandS) { Set-IniKey $lines 'upscale' 'goal_short_landscape' $goalLandS } else { Clear-IniKey $lines 'upscale' 'goal_short_landscape' }
        if ($null -ne $maxLandL)  { Set-IniKey $lines 'upscale' 'max_long_landscape'   $maxLandL }  else { Clear-IniKey $lines 'upscale' 'max_long_landscape' }

        # 種類別: チェック済み (デフォルト) はコメント化、オフのときだけ 0 を書く
        foreach ($p in @(@{ K = 'enabled_portrait'; C = 'ChkEnPortrait' },
                         @{ K = 'enabled_landscape'; C = 'ChkEnLandscape' },
                         @{ K = 'enabled_square'; C = 'ChkEnSquare' })) {
            if ($c[$p.C].IsChecked) { Clear-IniKey $lines 'upscale' $p.K }
            else { Set-IniKey $lines 'upscale' $p.K '0' }
        }

        Set-DynamicSection $lines 'lora_map'    $mapLines
        Set-DynamicSection $lines 'lora_add_if' $ruleLines

        # 「有効」チェック付きの自由記載欄 (S=セクション, K=キー, T=テキスト, C=チェック)
        foreach ($f in @(
                @{ S = 'upscale';          K = 'skip_if';           T = 'TxtSkipAny'; C = 'ChkSkipAny' },
                @{ S = 'upscale';          K = 'skip_if_portrait';  T = 'TxtSkipP';   C = 'ChkSkipP' },
                @{ S = 'upscale';          K = 'skip_if_landscape'; T = 'TxtSkipL';   C = 'ChkSkipL' },
                @{ S = 'upscale';          K = 'skip_if_square';    T = 'TxtSkipS';   C = 'ChkSkipS' },
                @{ S = 'lora_add';         K = 'portrait';  T = 'TxtAddP';    C = 'ChkAddP' },
                @{ S = 'lora_add';         K = 'landscape'; T = 'TxtAddL';    C = 'ChkAddL' },
                @{ S = 'lora_add';         K = 'square';    T = 'TxtAddS';    C = 'ChkAddS' },
                @{ S = 'negative_add';     K = 'portrait';  T = 'TxtNegAddP'; C = 'ChkNegAddP' },
                @{ S = 'negative_add';     K = 'landscape'; T = 'TxtNegAddL'; C = 'ChkNegAddL' },
                @{ S = 'negative_add';     K = 'square';    T = 'TxtNegAddS'; C = 'ChkNegAddS' },
                @{ S = 'prompt_remove';    K = 'portrait';  T = 'TxtRmP';     C = 'ChkRmP' },
                @{ S = 'prompt_remove';    K = 'landscape'; T = 'TxtRmL';     C = 'ChkRmL' },
                @{ S = 'prompt_remove';    K = 'square';    T = 'TxtRmS';     C = 'ChkRmS' },
                @{ S = 'negative_remove';  K = 'portrait';  T = 'TxtNegRmP';  C = 'ChkNegRmP' },
                @{ S = 'negative_remove';  K = 'landscape'; T = 'TxtNegRmL';  C = 'ChkNegRmL' },
                @{ S = 'negative_remove';  K = 'square';    T = 'TxtNegRmS';  C = 'ChkNegRmS' },
                @{ S = 'prompt_replace';   K = 'portrait';  T = 'TxtRpP';     C = 'ChkRpP' },
                @{ S = 'prompt_replace';   K = 'landscape'; T = 'TxtRpL';     C = 'ChkRpL' },
                @{ S = 'prompt_replace';   K = 'square';    T = 'TxtRpS';     C = 'ChkRpS' },
                @{ S = 'negative_replace'; K = 'portrait';  T = 'TxtNegRpP';  C = 'ChkNegRpP' },
                @{ S = 'negative_replace'; K = 'landscape'; T = 'TxtNegRpL';  C = 'ChkNegRpL' },
                @{ S = 'negative_replace'; K = 'square';    T = 'TxtNegRpS';  C = 'ChkNegRpS' })) {
            Set-OrClearChk $lines $f.S $f.K $c[$f.T].Text ([bool]$c[$f.C].IsChecked)
        }

        foreach ($k in 'portrait', 'landscape', 'square') {
            Set-OrClear $lines 'sampler' "${k}_method"    $smp[$k].Method
            Set-OrClear $lines 'sampler' "${k}_scheduler" $smp[$k].Sched
            if ($null -ne $smp[$k].Steps) { Set-IniKey $lines 'sampler' "${k}_steps" $smp[$k].Steps } else { Clear-IniKey $lines 'sampler' "${k}_steps" }
            if ($null -ne $smp[$k].Cfg) {
                Set-IniKey $lines 'sampler' "${k}_cfg" $smp[$k].Cfg.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            } else { Clear-IniKey $lines 'sampler' "${k}_cfg" }
        }

        # プロキシ (fopen/fgets) は UTF-8 の生バイトを読むため BOM なしで保存する
        [System.IO.File]::WriteAllLines($script:IniPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
        $script:Lines = $lines
        $c['LblStatus'].Text = "保存しました ($(Get-Date -Format 'HH:mm:ss')) - 次の画像生成から反映されます"
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, '入力エラー',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
}

# ------------------------------------------------------------ イベント

$c['BtnOpen'].Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'INI ファイル (*.ini)|*.ini|すべてのファイル (*.*)|*.*'
    $dlg.InitialDirectory = $script:BaseDir
    if ($dlg.ShowDialog()) { Open-IniFile $dlg.FileName }
})
$c['BtnReload'].Add_Click({
    if ($script:IniPath) { Open-IniFile $script:IniPath }
})
$c['BtnSave'].Add_Click({ Save-IniFile })
$c['BtnMapAdd'].Add_Click({ $script:MapColl.Add((New-Object SdGui.MapEntry)) })
$c['BtnMapDel'].Add_Click({
    foreach ($it in @($c['GridLoraMap'].SelectedItems)) { [void]$script:MapColl.Remove($it) }
})
$c['BtnRuleAdd'].Add_Click({ $script:RuleColl.Add((New-Object SdGui.RuleEntry)) })
$c['BtnRuleDel'].Add_Click({
    foreach ($it in @($c['GridRules'].SelectedItems)) { [void]$script:RuleColl.Remove($it) }
})

# --- 導入 / 管理タブ ---

# 「設定ファイル」「保存」バーは設定編集タブのときだけ表示する
$c['Tabs'].Add_SelectionChanged({
    if ($args[1].OriginalSource -ne $c['Tabs']) { return }
    $vis = [System.Windows.Visibility]::Visible
    if ($c['Tabs'].SelectedIndex -eq 0) { $vis = [System.Windows.Visibility]::Collapsed }
    $c['PnlFile'].Visibility = $vis
    $c['PnlSave'].Visibility = $vis
})

$c['BtnRefresh'].Add_Click({ $script:GameDir = $null; Update-ManageStatus })

$c['BtnGameBrowse'].Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'ゲームルート (instantale.exe のあるフォルダ) を選択してください'
    if ($script:GameDir) { $dlg.SelectedPath = $script:GameDir }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if (Test-GameRoot $dlg.SelectedPath) {
            $script:GameDir = $dlg.SelectedPath.TrimEnd('\')
            Save-GameDirSetting $script:GameDir
            Write-MLog "ゲームルートを設定しました: $script:GameDir"
        } else {
            [System.Windows.MessageBox]::Show(
                "指定のフォルダにバックエンド (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan の lib\stable-diffusion.dll) が見つかりません。`ninstantale.exe のあるフォルダを選択してください。",
                'ゲームルート', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        Update-ManageStatus
    }
})

$c['BtnInstall15'].Add_Click({
    Invoke-ManageAction 'SD1.5 モードで導入' { Install-Mode 'sd15' } `
        "ゲーム同梱の stable-diffusion.dll を MOD のプロキシに差し替えます (元ファイルは自動退避)。`nゲームを閉じた状態で実行してください。続行しますか?"
})
$c['BtnInstallXL'].Add_Click({
    Invoke-ManageAction 'SDXL モードで導入' { Install-Mode 'sdxl' } `
        "ゲーム同梱の stable-diffusion.dll と TAESD デコーダを差し替えます (元ファイルは自動退避)。`nSDXL モードはゲーム本来のパイプラインを外れるため、画像の破綻やクラッシュが起こり得ます (README 参照)。`nゲームを閉じた状態で実行してください。続行しますか?"
})
$c['BtnSwitch15'].Add_Click({
    Invoke-ManageAction 'SD1.5 モードへ切替' { Switch-Mode 'sd15' } `
        "TAESD デコーダと sd_upscale.ini を SD1.5 用に切り替えます。`nゲームを閉じた状態で実行してください。続行しますか?"
})
$c['BtnSwitchXL'].Add_Click({
    Invoke-ManageAction 'SDXL モードへ切替' { Switch-Mode 'sdxl' } `
        "TAESD デコーダと sd_upscale.ini を SDXL 用に切り替えます。`nゲームを閉じた状態で実行してください。続行しますか?"
})
$c['BtnUninstall'].Add_Click({
    Invoke-ManageAction 'アンインストール' { Uninstall-Mod } `
        "MOD を取り外し、ゲーム同梱ファイル (stable-diffusion.dll / TAESD) を元に戻します。`nMOD フォルダ自体は残るので、不要なら後で手動で削除してください。`nゲームを閉じた状態で実行してください。続行しますか?"
})
$c['BtnLoadIni'].Add_Click({
    if (-not $script:GameDir) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = '適用する設定ファイルを選択'
    $dlg.Filter = 'INI ファイル (*.ini)|*.ini|すべてのファイル (*.*)|*.*'
    $dlg.InitialDirectory = $script:BaseDir
    if (-not $dlg.ShowDialog()) { return }
    $src = $dlg.FileName
    Invoke-ManageAction '既存の ini を適用' { Import-IniFile $src } `
        "$src を`n$((Get-ModPaths).Ini) にコピーして適用します。`n現在の設定は sd_upscale.ini.bak に退避されます。続行しますか?"
})

# ------------------------------------------------------------ 起動

$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not ($SelfTest -or $SelfTestManage)) { Update-ManageStatus }

# 設定エディタの初期表示: 設定フォルダの sd_upscale.ini → 旧配置 (ツール
# フォルダ内) → モード別プリセット の順で最初に見つかったものを開く
$cands = @()
if ($script:GameDir) { $cands += (Get-ModPaths).Ini }
foreach ($cand in 'sd_upscale.ini', 'sd_upscale.sd15.ini', 'sd_upscale.sdxl.ini') {
    $cands += Join-Path $script:BaseDir $cand
}
foreach ($pth in $cands) {
    if (Test-Path $pth) { Open-IniFile $pth; break }
}
if (-not $script:IniPath) {
    $c['TxtFile'].Text = '(ini が見つかりません -- 「開く...」で sd_upscale.ini を選択してください)'
}

if ($SelfTest) {
    # 自己テスト: sd15 プリセットを一時コピー → 値を変更して保存 → 再読込して検証
    $src = Join-Path $script:BaseDir 'sd_upscale.sd15.ini'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'mod_gui_selftest.ini'
    Copy-Item $src $tmp -Force
    Open-IniFile $tmp
    $before = ([System.IO.File]::ReadAllLines($tmp, [System.Text.Encoding]::UTF8) |
        Where-Object { $_.TrimStart().StartsWith(';') }).Count

    $c['TxtGoalShort'].Text = '896'
    $c['ChkEnLandscape'].IsChecked = $false
    $c['TxtSkipAny'].Text = 'pixel art/sprite'
    $c['TxtAddP'].Text = '<lora:testStyle:0.5>, masterpiece'; $c['ChkAddP'].IsChecked = $false
    $e = New-Object SdGui.MapEntry; $e.Name = 'TestLora'; $e.Target = 'off'; $script:MapColl.Add($e)
    $e2 = New-Object SdGui.MapEntry; $e2.Name = 'PausedLora'; $e2.Target = 'myLora:0.7'; $e2.Enabled = $false; $script:MapColl.Add($e2)
    $r = New-Object SdGui.RuleEntry; $r.Name = 'rule1'; $r.Cls = 'portrait'; $r.Cond = '1boy'; $r.Add = '<lora:x:0.8>'
    $script:RuleColl.Add($r)
    $c['CmbMethodL'].Text = 'dpm++2m'; $c['CmbSchedL'].Text = 'karras'
    $c['TxtStepsL'].Text = '20'; $c['TxtCfgL'].Text = '5.0'
    Save-IniFile

    Open-IniFile $tmp
    $v = Read-IniValues $script:Lines
    $fail = @()
    if ($v.Fx['upscale/goal_short'] -ne '896')            { $fail += 'goal_short' }
    if ($v.Fx['upscale/enabled_landscape'] -ne '0')       { $fail += 'enabled_landscape' }
    if ($v.Fx['upscale/skip_if'] -ne 'pixel art/sprite')  { $fail += 'skip_if' }
    if ($v.Fx['sampler/landscape_method'] -ne 'dpm++2m')  { $fail += 'landscape_method' }
    if ($v.Fx['sampler/landscape_cfg'] -ne '5')           { $fail += 'landscape_cfg' }
    if ($v.Fx['sampler/portrait_method'] -ne 'euler_a')   { $fail += 'portrait_method (既存値の保持)' }
    if ($v.Map.Count -ne 2 -or $v.Map[0].Name -ne 'TestLora' -or -not $v.Map[0].Enabled) { $fail += 'lora_map' }
    if ($v.Map.Count -eq 2 -and ($v.Map[1].Name -ne 'PausedLora' -or $v.Map[1].Target -ne 'myLora:0.7' -or $v.Map[1].Enabled)) { $fail += 'lora_map (無効行の保持)' }
    if ($v.Rules.Count -ne 1 -or $v.Rules[0].Cond -ne '1boy') { $fail += 'lora_add_if' }
    if ($v.Fx.ContainsKey('lora_add/portrait'))                              { $fail += 'lora_add/portrait が有効のまま' }
    if ($v.Dis['lora_add/portrait'] -ne '<lora:testStyle:0.5>, masterpiece') { $fail += 'lora_add/portrait (無効値の保持)' }
    if ($c['ChkAddP'].IsChecked -or $c['TxtAddP'].Text -ne '<lora:testStyle:0.5>, masterpiece') { $fail += 'ChkAddP の復元' }

    # 無効 → 有効に戻して保存し、通常の行として書かれることを確認
    $c['ChkAddP'].IsChecked = $true
    Save-IniFile
    Open-IniFile $tmp
    $v2 = Read-IniValues $script:Lines
    if ($v2.Fx['lora_add/portrait'] -ne '<lora:testStyle:0.5>, masterpiece') { $fail += 'lora_add/portrait の再有効化' }
    if ($v2.Dis.ContainsKey('lora_add/portrait'))                            { $fail += ';off: 行の残留' }
    $c['ChkAddP'].IsChecked = $false
    Save-IniFile
    Open-IniFile $tmp
    $after = ([System.IO.File]::ReadAllLines($tmp, [System.Text.Encoding]::UTF8) |
        Where-Object { $_.TrimStart().StartsWith(';') }).Count
    if ($after -lt $before) { $fail += "コメント行が減った ($before -> $after)" }

    # 再保存して安定性を確認 (行が増殖しないこと)
    $n1 = $script:Lines.Count
    Save-IniFile
    Open-IniFile $tmp
    if ($script:Lines.Count -ne $n1) { $fail += "再保存で行数が変化 ($n1 -> $($script:Lines.Count))" }

    Remove-Item $tmp -Force
    if ($fail.Count) { Write-Host "SELFTEST FAIL: $($fail -join ', ')"; exit 1 }
    Write-Host "SELFTEST PASS (コメント行 $before -> $after, 全 $n1 行)"
    exit 0
}

if ($SelfTestManage) {
    # 自己テスト: 一時フォルダに偽のゲーム + MOD フォルダを作り、
    # 導入 → SDXL 化 → 切替往復 → アンインストールを通しで検証する
    $root = Join-Path ([System.IO.Path]::GetTempPath()) 'mod_gui_selftest_manage'
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    $game = Join-Path $root 'game'
    $mod  = Join-Path $game 'tools\InstantaleStableDiffusionMod'
    New-Item -ItemType Directory -Force -Path (Join-Path $mod 'mod_files') | Out-Null
    foreach ($b in 'sdcpp_cuda', 'sdcpp_cpu') {
        New-Item -ItemType Directory -Force -Path (Join-Path $game "$b\lib") | Out-Null
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $game 'runtime\models\sd15\taesd') | Out-Null
    # 11MB のダミー元 DLL (プロキシ判定のしきい値 10MB を超えるサイズ)
    $big = New-Object byte[] (11MB)
    foreach ($b in 'sdcpp_cuda', 'sdcpp_cpu') {
        [System.IO.File]::WriteAllBytes((Join-Path $game "$b\lib\stable-diffusion.dll"), $big)
    }
    $taesd = Join-Path $game 'runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors'
    [System.IO.File]::WriteAllText($taesd, 'TAESD-SD15-ORIGINAL')
    [System.IO.File]::WriteAllText((Join-Path $mod 'mod_files\stable-diffusion-proxy.dll'), 'PROXY-DLL')
    [System.IO.File]::WriteAllText((Join-Path $mod 'mod_files\taesdxl.safetensors'), 'TAESD-XL')
    Copy-Item (Join-Path $script:BaseDir 'sd_upscale.sd15.ini') (Join-Path $mod 'sd_upscale.sd15.ini')
    Copy-Item (Join-Path $script:BaseDir 'sd_upscale.sdxl.ini') (Join-Path $mod 'sd_upscale.sdxl.ini')
    # 旧バージョンの残骸: lib\ のポインタ ini と、ツールフォルダ内の sd_upscale.ini
    [System.IO.File]::WriteAllText((Join-Path $game 'sdcpp_cuda\lib\stable-diffusion-proxy.ini'), "mod_dir=$mod\")
    [System.IO.File]::WriteAllText((Join-Path $mod 'sd_upscale.ini'), "[upscale]`ngoal_short = 777`n")

    $script:BaseDir = $mod
    $script:GameDir = $null
    Update-ManageStatus

    $fail = @()
    if ($script:GameDir -ne $game) { $fail += "ゲームルートの自動検出 ($($script:GameDir))" }
    $cfg    = Join-Path $game 'InstantaleSDMod'
    $cfgIni = Join-Path $cfg 'sd_upscale.ini'

    Install-Mode 'sd15'
    $cudaLib = Join-Path $game 'sdcpp_cuda\lib\stable-diffusion.dll'
    if ((Get-Item $cudaLib).Length -gt 10000000) { $fail += 'プロキシ導入 (cuda)' }
    if (-not (Test-Path (Join-Path $game 'sdcpp_cuda\lib\stable-diffusion-real.dll'))) { $fail += '元 DLL の退避 (cuda)' }
    if (-not (Test-Path $cfgIni)) { $fail += 'InstantaleSDMod\sd_upscale.ini の生成' }
    if (Test-Path (Join-Path $mod 'sd_upscale.ini')) { $fail += '旧配置 ini の移行 (ツールフォルダに残留)' }
    if (-not (Test-Path "$cfgIni.bak")) { $fail += '移行した旧 ini の .bak 退避' }
    foreach ($b in 'sdcpp_cuda', 'sdcpp_cpu') {
        if (Test-Path (Join-Path $game "$b\lib\stable-diffusion-proxy.ini")) { $fail += "ポインタ ini の廃止/掃除 ($b)" }
    }
    if (-not (Test-Path (Join-Path $mod 'settings.ini'))) { $fail += 'settings.ini の保存' }
    if ((Get-CurrentMode) -ne 'fresh') { $fail += "モード判定 fresh ($(Get-CurrentMode))" }

    # 導入の冪等性 (2 回目でも壊れない)
    Install-Mode 'sd15'
    if (-not (Test-Path (Join-Path $game 'sdcpp_cuda\lib\stable-diffusion-real.dll'))) { $fail += '再導入で退避が消えた' }

    Install-Mode 'sdxl'
    if (-not (Test-SameFile $taesd (Join-Path $mod 'mod_files\taesdxl.safetensors'))) { $fail += 'TAESDXL の導入' }
    if (-not (Test-Path (Join-Path $mod 'mod_files\taesd_sd15.safetensors'))) { $fail += 'SD1.5 用 TAESD の退避' }
    if ((Get-CurrentMode) -ne 'sdxl') { $fail += "モード判定 sdxl ($(Get-CurrentMode))" }

    Switch-Mode 'sd15'
    if ((Get-CurrentMode) -ne 'sd15') { $fail += 'SD1.5 への切替' }
    if (-not (Test-SameFile $taesd (Join-Path $mod 'mod_files\taesd_sd15.safetensors'))) { $fail += 'SD1.5 TAESD の復元' }
    Switch-Mode 'sdxl'
    if ((Get-CurrentMode) -ne 'sdxl') { $fail += 'SDXL への切替' }

    # 既存 ini の手動適用 (Import-IniFile)
    $customIni = Join-Path $mod 'my_custom.ini'
    [System.IO.File]::WriteAllText($customIni, "[upscale]`r`ngoal_short = 999`r`n")
    $before = [System.IO.File]::ReadAllText($cfgIni)
    Import-IniFile $customIni
    if ([System.IO.File]::ReadAllText($cfgIni) -notlike '*goal_short = 999*') { $fail += '既存 ini の適用' }
    if ([System.IO.File]::ReadAllText("$cfgIni.bak") -ne $before) { $fail += '既存 ini 適用時の .bak 退避' }
    Import-IniFile $cfgIni   # 適用中のファイル自身を選んでも壊れない
    if ([System.IO.File]::ReadAllText($cfgIni) -notlike '*goal_short = 999*') { $fail += '適用中 ini 自身の選択' }

    Uninstall-Mod
    if ((Get-Item $cudaLib).Length -le 10000000) { $fail += 'アンインストール: DLL 復元' }
    if (Test-Path (Join-Path $game 'sdcpp_cuda\lib\stable-diffusion-real.dll')) { $fail += 'アンインストール: 退避 DLL の削除' }
    if (-not (Test-SameFile $taesd (Join-Path $mod 'mod_files\taesd_sd15.safetensors'))) { $fail += 'アンインストール: TAESD 復元' }
    if (Test-Path $cfg) { $fail += 'アンインストール: InstantaleSDMod フォルダの削除' }
    Update-ManageStatus
    if ($c['LblMode'].Text -notmatch '未導入') { $fail += "アンインストール後の状態表示 ($($c['LblMode'].Text))" }

    Remove-Item $root -Recurse -Force
    if ($fail.Count) { Write-Host "SELFTEST-MANAGE FAIL: $($fail -join ', ')"; exit 1 }
    Write-Host 'SELFTEST-MANAGE PASS'
    exit 0
}

[void]$win.ShowDialog()
