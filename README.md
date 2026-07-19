# Instantale 画質強化 MOD (Stable Diffusion)

**Instantale** の画像生成をフックし、**生成解像度の引き上げ**・**LoRA の差し替え/追加適用**・**サンプラー上書き**（いずれもゲーム側では開放されていない機能）を可能にする MOD です。ゲーム標準の **SD1.5** のまま強化する SD1.5 モードと、**SDXL 系モデル**（Illustrious 等）へ置き換える SDXL モードに対応します。導入・モード切替・アンインストール・設定編集は、同梱の GUI ツール（`mod_gui.bat`）にすべて統合されています。

> [!WARNING]
> 本 MOD はゲーム同梱ファイル（`sdcpp_cuda` / `sdcpp_cpu` / `sdcpp_vulkan` 各バックエンドの `lib\stable-diffusion.dll` と TAESD デコーダ）を書き換えます。導入は自己責任で行ってください。オリジナルは自動退避され、GUI の「アンインストール (原状復帰)」で元に戻せます。

> [!CAUTION]
> **SDXL への乗り換え、および LoRA の差し替え・追加適用は、意図しない異常な画像が生成される恐れがあります。** これらはゲーム本来の生成パイプラインを外れる機能であり、チェックポイントと LoRA・TAESD の系統（SD1.5 / SDXL）の不一致、解像度の上げすぎ、LoRA 同士の相性などによって、画像の破綻・崩れ・色化け、場合によってはゲームのクラッシュが起こり得ます。特に SD1.5 モデルへ SDXL 用 LoRA（またはその逆）を当てるとゲームごとクラッシュします。想定と異なる結果になった場合は、`[upscale]` を下げる・追加した LoRA を外す・GUI のモード切替で元のモードへ戻す、などで切り分けてください。生成結果は保証されません。自己責任でご利用ください。

---

## 特徴

- **解像度アップスケール** — アスペクト比を保ったまま生成解像度を引き上げ。画像の種類（縦長 / 横長 / 正方形）ごとに個別設定が可能。
- **LoRA の付け替え・追加** — ゲームが要求する LoRA の差し替え/無効化、種類別の LoRA・タグ追加、ネガティブプロンプト追加。
- **サンプラー上書き** — method / steps / cfg / scheduler を種類別に上書き。
- **ホットリロード** — 設定は生成のたびに `sd_upscale.ini` を読み直すため、**ゲームを起動したまま**編集内容が次の生成から反映されます（再起動・再ビルド不要）。
- **2 モード対応** — SD1.5 標準モデル版 / SDXL 化版をワンクリックで切り替え。
- **統合 GUI** — `mod_gui.bat` 1 つで導入・モード切替・アンインストール・状態確認・設定 (`.ini`) のフォーム編集まで完結。

---

## 動作の仕組み

画像生成が呼び出す `sdcpp_<バックエンド>\lib\stable-diffusion.dll`（`sdcpp_cuda` / `sdcpp_cpu` / `sdcpp_vulkan` のうち存在するものすべて）を**自作プロキシ DLL に差し替えてフック**します。

プロキシは `generate_image` をフックして解像度とプロンプト（LoRA タグ）を書き換え、残り 27 個の export はオリジナル DLL（同じ `lib\` 内に `stable-diffusion-real.dll` として退避）へ転送します。

バックエンドごとにオリジナル DLL が異なるため、プロキシは自分と同じフォルダの退避 DLL を優先して読み込みます（無ければ v1 互換でゲームルート直下を参照）。

設定ファイル（`sd_upscale.ini`）と動作ログ（`proxy_resize.log`）は固定の **`<ゲームルート>\InstantaleSDMod\`**（設定フォルダ。GUI が導入時に作成）に置かれ、プロキシ DLL は自分のパス（`sdcpp_*\lib\`）からゲームルートを逆算してここを読み書きします。ゲーム側にポインタファイルを書き込む方式（v2.0 以前の `stable-diffusion-proxy.ini`）は廃止しました。MOD ツールフォルダ自体は**任意の場所**に置けます（既定は `<ゲームルート>\tools\InstantaleStableDiffusionMod\`）。`settings.ini`（MOD ツールフォルダ内）には GUI が検出/指定されたゲームルートのパスが保存され、次回から自動使用されます（ツールがゲームフォルダ内にあれば自動検出、外にある場合は初回のみフォルダ選択）。

ゲーム本体側に置かれるのは各バックエンドの `lib\stable-diffusion.dll` の差し替え（+ 同フォルダへの退避 DLL）、TAESD デコーダの差し替え、設定フォルダ `InstantaleSDMod\` の 3 つだけです。

---

## クイックスタート

### SD1.5 モード（ダウンロード不要・推奨）

ゲーム標準の SD1.5 モデルをそのまま使うため、追加モデルのダウンロードは不要です。

1. リリース zip をゲームのルートフォルダ（`instantale.exe` があるフォルダ）に展開（MOD 一式は `tools\InstantaleStableDiffusionMod\` に入ります）
2. ゲームを閉じた状態で `tools\InstantaleStableDiffusionMod\mod_gui.bat` を起動し、「導入 / 管理」タブの **「SD1.5 モードで導入 / 修復」** を押す
3. ゲームを起動し、SD1.5 系チェックポイントを選んで生成

詳細は **[README_SD15_MOD.txt](README_SD15_MOD.txt)** を参照。

### SDXL モード（Illustrious-XL 等へ置き換え）

大容量モデルは同梱していないため、事前にダウンロードが必要です。

1. SDXL チェックポイントと TAESDXL デコーダを入手して配置（配置先・URL は SDXL README の 2. 参照）
2. zip をゲームルートに展開（MOD 一式は `tools\InstantaleStableDiffusionMod\` に入ります）
3. ゲームを閉じた状態で `tools\InstantaleStableDiffusionMod\mod_gui.bat` を起動し、「導入 / 管理」タブの **「SDXL モードで導入 / 修復」** を押す
4. ゲームを起動し、SDXL チェックポイントを選んで生成

> [!CAUTION]
> SDXL への乗り換えと LoRA 適用は、意図しない異常な画像が生成される恐れがあります（上部の注意を参照）。系統の一致（SDXL チェックポイント ＋ SDXL 用 LoRA ＋ TAESDXL）を必ず守ってください。

詳細は **[README_SDXL_MOD.txt](README_SDXL_MOD.txt)** を参照。

### モード切替 / アンインストール

`mod_gui.bat` の「導入 / 管理」タブで行います。

- **モード切替** — 「SD1.5 へ」「SDXL へ」ボタンで TAESD デコーダと `sd_upscale.ini` を入れ替えます。切替の直前に現在の `sd_upscale.ini` が `sd_upscale.<現モード>.ini` に保存されるため、モードごとのチューニングは往復しても保持されます
- **既存の ini を読み込んで適用** — 設定の自動入れ替えを使わず手動で管理したい場合はこちら。選んだ ini ファイル（自作の設定・配布された設定など）がそのまま有効な `sd_upscale.ini` になります（適用前の設定は `sd_upscale.ini.bak` に退避。TAESD やプロキシには触りません）
- **アンインストール (原状復帰)** — 退避してあったゲーム同梱ファイルをすべて書き戻し、設定フォルダ `InstantaleSDMod\` も削除して MOD をゲームから取り外します（MOD ツールフォルダ自体は残るので不要なら手動で削除）
- タブ上部の状態表示で、現在のモード・バックエンドごとの導入状況・ファイルの巻き戻りを確認できます

> [!IMPORTANT]
> Epic Games Launcher などの「ファイルの検証」や自動アップデートは、書き換えたゲーム同梱ファイルをオリジナルに巻き戻します。巻き戻ったら GUI の「導入 / 修復」を再実行すれば復旧します（導入処理は冪等で、何度実行しても安全です）。可能ならランチャー側で自動アップデートを無効にしてください。

---

## 設定 (`sd_upscale.ini`)

GUI の導入時に、モード別プリセット（`sd_upscale.sd15.ini` / `sd_upscale.sdxl.ini`）から、実際に読み込まれる `sd_upscale.ini` が設定フォルダ（`<ゲームルート>\InstantaleSDMod\`）に生成されます。主なセクション：

| セクション | 役割 |
| --- | --- |
| `[upscale]` | 生成解像度（短辺目標 / 長辺上限 / 丸め）。種類別に有効・無効を切替可能 |
| `[lora_map]` | ゲームが要求する LoRA の付け替え・無効化 |
| `[lora_add]` | 種類（portrait / landscape / square）別の LoRA・タグ追加 |
| `[negative_add]` | 種類別のネガティブプロンプト追加 |
| `[sampler]` | 種類別に method / steps / cfg / scheduler を上書き |

### 解像度の決まり方（`[upscale]`）

`goal_short`（短辺の目標）は「この値ちょうどにする」指定ではありません。アスペクト比を保ったまま拡大するため、先に長辺が `max_long` に達するとそこで拡大が止まります。

```
倍率 = min(goal_short ÷ 元の短辺, max_long ÷ 元の長辺)   ※ 1.0 未満にはならない (縮小しない)
出力 = 元サイズ × 倍率 を、両辺とも round の倍数に四捨五入
```

例: キャラ画像 512×1024 に `goal_short=832` / `max_long=1216` を指定すると、短辺基準の 832÷512=1.625 より長辺上限の 1216÷1024=1.1875 が小さいためそちらが採用され、608×1216 → 丸めて **640×1216** になります（短辺は 832 に届きません）。短辺を実際に 832 にしたい場合は `max_long` も比例して上げてください（832/1664 → 出力 832×1664）。画像を歪めることはないため、元と異なる縦横比（832×1216 など）を直接指定することはできません。

各項目の詳しい意味と推奨値は各 README を参照してください。`mod_gui.bat` の設定編集タブ（解像度 / LoRA 付替 / プロンプト追加など）でフォーム編集もできます。

---

## リポジトリ構成

リリース zip ではこれら一式が `tools\InstantaleStableDiffusionMod\` 配下に収められます。展開後の MOD ツールフォルダは任意の場所・任意の名前に移動できます（移動したら GUI で「導入 / 修復」を再実行）。実際に読み込まれる `sd_upscale.ini` は導入時に `<ゲームルート>\InstantaleSDMod\` へ生成され、旧配置（v2.0 のツールフォルダ内 / v1.x のゲームルート直下）に `sd_upscale.ini` が残っていた場合は導入/切替時に自動移行されます。

| パス | 内容 |
| --- | --- |
| `mod_gui.bat` / `mod_gui.ps1` | 統合 GUI（導入・モード切替・アンインストール・状態確認・設定編集） |
| `sd_upscale.sd15.ini` / `sd_upscale.sdxl.ini` | モード別の設定プリセット |
| `mod_files/stable-diffusion-proxy.dll` | プロキシ DLL（両モード共通、約 200KB） |
| `mod_src/proxy.c` / `mod_src/exports.def` | プロキシ DLL のソースと転送定義 |
| `README_SD15_MOD.txt` / `README_SDXL_MOD.txt` | モード別の詳細手順 |
| `make_release_zip.bat` | 配布用 zip の作成（開発者用。`make_release_zip.bat v2` のようにバージョンを指定） |

---

## プロキシ DLL の再ビルド

[Zig](https://ziglang.org/)（`pip install ziglang`）で `mod_src/` からビルドできます。

```bat
python -m ziglang cc -target x86_64-windows-gnu -O2 -shared ^
    -o stable-diffusion-proxy.dll proxy.c exports.def
```

生成した DLL を `mod_files\` に置き、GUI の「導入 / 修復」を再実行してください。単体テスト方法は各 README の該当節を参照。

---

## 謝辞

ツール開発にあたり機能提案やテストにご協力くださった Discord の 狐雨月（こさめづき）様に感謝します。

---

## ライセンス

本リポジトリのコードは [LICENSE](LICENSE) を参照。各自でダウンロードして使うモデル（SDXL チェックポイント、TAESDXL、LCM-LoRA 等）は、それぞれの配布元ライセンスに従ってください。
