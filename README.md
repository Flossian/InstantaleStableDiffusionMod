# Instantale 画質強化 MOD (Stable Diffusion)

**Instantale** の画像生成をフックし、**生成解像度の引き上げ**・**LoRA の差し替え/追加適用**・**サンプラー上書き**（いずれもゲーム側では開放されていない機能）を可能にする MOD です。ゲーム標準の **SD1.5** のまま強化する SD1.5 モードと、**SDXL 系モデル**（Illustrious 等）へ置き換える SDXL モードに対応し、`switch_sd_mode.bat` で相互に切り替えられます。

> [!WARNING]
> 本 MOD はゲーム同梱ファイル（`sdcpp_cuda\lib\stable-diffusion.dll` と TAESD デコーダ）を書き換えます。導入は自己責任で行ってください。オリジナルは自動退避され、`switch_sd_mode.bat` / アンインストール手順で元に戻せます。

> [!CAUTION]
> **SDXL への乗り換え、および LoRA の差し替え・追加適用は、意図しない異常な画像が生成される恐れがあります。** これらはゲーム本来の生成パイプラインを外れる機能であり、チェックポイントと LoRA・TAESD の系統（SD1.5 / SDXL）の不一致、解像度の上げすぎ、LoRA 同士の相性などによって、画像の破綻・崩れ・色化け、場合によってはゲームのクラッシュが起こり得ます。特に SD1.5 モデルへ SDXL 用 LoRA（またはその逆）を当てるとゲームごとクラッシュします。想定と異なる結果になった場合は、`[upscale]` を下げる・追加した LoRA を外す・`switch_sd_mode.bat` で元のモードへ戻す、などで切り分けてください。生成結果は保証されません。自己責任でご利用ください。

---

## 特徴

- **解像度アップスケール** — アスペクト比を保ったまま生成解像度を引き上げ。画像の種類（縦長 / 横長 / 正方形）ごとに個別設定が可能。
- **LoRA の付け替え・追加** — ゲームが要求する LoRA の差し替え/無効化、種類別の LoRA・タグ追加、ネガティブプロンプト追加。
- **サンプラー上書き** — method / steps / cfg / scheduler を種類別に上書き。
- **ホットリロード** — 設定は生成のたびに `sd_upscale.ini` を読み直すため、**ゲームを起動したまま**編集内容が次の生成から反映されます（再起動・再ビルド不要）。
- **2 モード対応** — SD1.5 標準モデル版 / SDXL 化版をワンコマンドで切り替え。
- **GUI 設定ツール同梱** — `sd_upscale_gui.bat` で `.ini` をフォーム編集。

---

## 動作の仕組み

ゲーム本体は Nuitka コンパイル済みで改変できないため、画像生成が呼び出す `sdcpp_cuda\lib\stable-diffusion.dll` を**自作プロキシ DLL に差し替えてフック**します。プロキシは `generate_image` をフックして解像度とプロンプト（LoRA タグ）を書き換え、残り 27 個の export はオリジナル DLL（`stable-diffusion-real.dll` として退避）へ転送します。動作ログはゲームルートの `proxy_resize.log` に出力されます。

---

## クイックスタート

### SD1.5 モード（ダウンロード不要・推奨）

ゲーム標準の SD1.5 モデルをそのまま使うため、追加モデルのダウンロードは不要です。

1. リリース zip をゲームのルートフォルダ（`instantale.exe` があるフォルダ）に展開（すべて上書き）
2. ゲームを閉じた状態で `install_sd15.bat` を 1 回実行
3. ゲームを起動し、SD1.5 系チェックポイントを選んで生成

詳細は **[README_SD15_MOD.txt](README_SD15_MOD.txt)** を参照。

### SDXL モード（Illustrious-XL 等へ置き換え）

大容量モデルは同梱していないため、事前にダウンロードが必要です。

1. SDXL チェックポイントと TAESDXL デコーダを入手して配置（配置先・URL は SDXL README の 2. 参照）
2. zip をゲームルートに展開（すべて上書き）
3. ゲームを閉じた状態で `install_sdxl.bat` を 1 回実行
4. ゲームを起動し、SDXL チェックポイントを選んで生成

> [!CAUTION]
> SDXL への乗り換えと LoRA 適用は、意図しない異常な画像が生成される恐れがあります（上部の注意を参照）。系統の一致（SDXL チェックポイント ＋ SDXL 用 LoRA ＋ TAESDXL）を必ず守ってください。

詳細は **[README_SDXL_MOD.txt](README_SDXL_MOD.txt)** を参照。

### モード切替

```bat
switch_sd_mode.bat        現在と逆のモードへトグル
switch_sd_mode.bat sd15   SD1.5 モードへ強制
switch_sd_mode.bat sdxl   SDXL モードへ強制
```

> [!IMPORTANT]
> Epic Games Launcher などの「ファイルの検証」や自動アップデートは、書き換えたゲーム同梱ファイルをオリジナルに巻き戻します。巻き戻ったら `install_sd15.bat` / `install_sdxl.bat` を再実行すれば復旧します（バッチは冪等）。可能ならランチャー側で自動アップデートを無効にしてください。

---

## 設定 (`sd_upscale.ini`)

インストーラがモード別プリセット（`sd_upscale.sd15.ini` / `sd_upscale.sdxl.ini`）から、実際に読み込まれる `sd_upscale.ini` を生成します。主なセクション：

| セクション | 役割 |
| --- | --- |
| `[upscale]` | 生成解像度（短辺目標 / 長辺上限 / 丸め）。種類別に有効・無効を切替可能 |
| `[lora_map]` | ゲームが要求する LoRA の付け替え・無効化 |
| `[lora_add]` | 種類（portrait / landscape / square）別の LoRA・タグ追加 |
| `[negative_add]` | 種類別のネガティブプロンプト追加 |
| `[sampler]` | 種類別に method / steps / cfg / scheduler を上書き |

各項目の詳しい意味と推奨値は各 README を参照してください。`sd_upscale_gui.bat`（PowerShell 製 GUI）でフォーム編集もできます。

---

## リポジトリ構成

| パス | 内容 |
| --- | --- |
| `install_sd15.bat` / `install_sdxl.bat` | 各モードのワンクリック導入 |
| `switch_sd_mode.bat` | SD1.5 ⇔ SDXL のモード切替 |
| `sd_upscale.sd15.ini` / `sd_upscale.sdxl.ini` | モード別の設定プリセット |
| `sd_upscale_gui.bat` / `sd_upscale_gui.ps1` | `.ini` を編集する GUI ツール |
| `mod_files/stable-diffusion-proxy.dll` | プロキシ DLL（両モード共通、約 200KB） |
| `mod_src/proxy.c` / `mod_src/exports.def` | プロキシ DLL のソースと転送定義 |
| `README_SD15_MOD.txt` / `README_SDXL_MOD.txt` | モード別の詳細手順 |

---

## プロキシ DLL の再ビルド

[Zig](https://ziglang.org/)（`pip install ziglang`）で `mod_src/` からビルドできます。

```bat
python -m ziglang cc -target x86_64-windows-gnu -O2 -shared ^
    -o stable-diffusion-proxy.dll proxy.c exports.def
```

生成した DLL を `mod_files\` に置き、`install_sd15.bat`（または `install_sdxl.bat`）を再実行してください。単体テスト方法は各 README の該当節を参照。

---

## 謝辞

ツール開発にあたり機能提案やテストにご協力くださった Discord の 狐雨月（こさめづき）様に感謝します。

---

## ライセンス

本リポジトリのコードは [LICENSE](LICENSE) を参照。各自でダウンロードして使うモデル（SDXL チェックポイント、TAESDXL、LCM-LoRA 等）は、それぞれの配布元ライセンスに従ってください。
