# ==========================================================================
#  Instantale SD MOD 設定 GUI  (sd_upscale.ini エディタ)
#  sd_upscale_gui.bat から起動します。ini のコメント行はそのまま保持し、
#  値の行だけを書き換えます。自由記載欄の「有効」チェックを外すと、内容を
#  ";off: key = value" 形式のコメントとして保存します (プロキシは無視するが
#  GUI は次回オフ状態で復元する)。保存後、次の画像生成から反映されます
#  (ゲームの再起動は不要 -- プロキシ DLL が生成のたびに ini を読み直すため)。
#  このファイルは UTF-8 (BOM 付き) で保存すること (Windows PowerShell 5.1 対応)。
# ==========================================================================
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

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

# ------------------------------------------------------------------- 画面

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instantale SD MOD 設定" Width="940" Height="740"
        WindowStartupLocation="CenterScreen" FontSize="13">
  <DockPanel Margin="10">

    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <Button Name="BtnOpen" Content="開く..." Width="80" Padding="0,4" DockPanel.Dock="Right" Margin="6,0,0,0"/>
      <TextBlock Text="設定ファイル: " VerticalAlignment="Center"/>
      <TextBox Name="TxtFile" IsReadOnly="True" VerticalContentAlignment="Center" Background="#F4F4F4"/>
    </DockPanel>

    <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
      <Button Name="BtnSave" Content="保存" Width="130" Height="32" FontWeight="Bold" DockPanel.Dock="Right"/>
      <Button Name="BtnReload" Content="再読込" Width="90" Height="32" DockPanel.Dock="Right" Margin="0,0,8,0"/>
      <TextBlock Name="LblStatus" VerticalAlignment="Center" Foreground="Gray" TextWrapping="Wrap"
                 Text="保存すると次の画像生成から反映されます (ゲームの再起動は不要)"/>
    </DockPanel>

    <TabControl Name="Tabs">

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
    'TxtFile','BtnOpen','BtnReload','BtnSave','LblStatus','Tabs'
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
    $win.Title = "Instantale SD MOD 設定 - $(Split-Path -Leaf $path)"
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

# ------------------------------------------------------------ 起動

$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($cand in 'sd_upscale.ini', 'sd_upscale.sd15.ini', 'sd_upscale.sdxl.ini') {
    $p = Join-Path $script:BaseDir $cand
    if (Test-Path $p) { Open-IniFile $p; break }
}
if (-not $script:IniPath) {
    $c['TxtFile'].Text = '(ini が見つかりません -- 「開く...」で sd_upscale.ini を選択してください)'
}

if ($SelfTest) {
    # 自己テスト: sd15 プリセットを一時コピー → 値を変更して保存 → 再読込して検証
    $src = Join-Path $script:BaseDir 'sd_upscale.sd15.ini'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'sd_upscale_gui_selftest.ini'
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

[void]$win.ShowDialog()
