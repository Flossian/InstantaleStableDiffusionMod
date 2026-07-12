================================================================================
 Instantale 画質強化 MOD (SD1.5 標準モデル版)  -  2026-07-12
================================================================================

ゲーム標準の SD1.5 モデルのまま、生成解像度の引き上げと、LoRA の
差し替え・追加適用・サンプラー上書き (いずれもゲーム側では開放されて
いない機能) を可能にする MOD です。SDXL への差し替えは行いません。

SDXL 系モデル (Illustrious 等) に置き換えて更に高解像度・高画質を狙う
場合は、同梱の README_SDXL_MOD.txt を参照してください。両モードは
switch_sd_mode.bat で相互に切り替えられます (下記 8.)。

このモードの利点:
- SDXL チェックポイントのダウンロード不要 (ゲーム標準モデルをそのまま使用)
- TAESD デコーダは SD1.5 標準のまま (緑色破綻の心配なし)
- ゲームが要求する LoRA はすべて SD1.5 用なので [lora_map] は空でも動く
- VRAM が少ない環境でも動きやすい (SDXL より軽い)

導入は 2 ステップ:
  (1) zip をゲームのルートフォルダ (instantale.exe があるフォルダ) に展開
  (2) install_sd15.bat を 1 回実行
      (DLL 導入 + TAESD + sd_upscale.ini をまとめて SD1.5 用に)

--------------------------------------------------------------------------------
1. 同梱ファイル
--------------------------------------------------------------------------------
README_SD15_MOD.txt            このファイル (SD1.5 モードの手順)
README_SDXL_MOD.txt            SDXL に差し替える場合の手順
install_sd15.bat               SD1.5 モードのワンクリック導入 (推奨。下記 3.)。
                               DLL 導入 + TAESD + sd_upscale.ini をまとめて
                               SD1.5 用にします
install_sdxl.bat               SDXL モードのワンクリック導入 (SDXL に切替える場合)
switch_sd_mode.bat             SDXL <-> SD1.5 のモード切替 (下記 8.)
sd_upscale.sd15.ini            SD1.5 モード用の設定プリセット (下記 5./6.)。
                               install_sd15.bat がこの内容を、実際に読み込まれる
                               sd_upscale.ini として書き出します (現在有効な
                               設定ファイル sd_upscale.ini は導入時に生成)
sd_upscale.sdxl.ini            SDXL モード用の設定プリセット (SDXL で使う場合)
mod_files\stable-diffusion-proxy.dll
                               自作プロキシ DLL (約 200KB)。generate_image を
                               フックして解像度とプロンプト (LoRA タグ) を
                               差し替え、他 27 個の export はオリジナル DLL へ
                               転送します。両モード共通です
mod_src\proxy.c                プロキシ DLL のソース
mod_src\exports.def            転送 (forwarder) 定義
mod_licenses\                  ダウンロードして使うモデルのライセンス表記
                               (SDXL モードで使う場合のみ関係します)

※ SD1.5 モードはダウンロード不要です。ゲーム標準の SD1.5 モデルと、その
  SD1.5 用 TAESD デコーダをそのまま使うため、追加のモデルは要りません
  (TAESDXL / LCM-LoRA / SDXL チェックポイントは SDXL モード専用。SDXL に
   切り替える場合のみ README_SDXL_MOD.txt の 2. を参照してダウンロード)。

--------------------------------------------------------------------------------
2. 前提
--------------------------------------------------------------------------------
- ゲームを一度でも起動して SD1.5 モデルで生成できていること
  (このモードは追加のモデルダウンロードを必要としません)。
- ゲーム内のモデル選択は SD1.5 系のままにしておくこと。SDXL モデルを
  選ぶとこのモード (SD1.5 TAESD) では画像が破綻します。

--------------------------------------------------------------------------------
3. インストール手順
--------------------------------------------------------------------------------
(1) 事前バックアップ (元に戻す予定があるなら):
    この MOD が変更するゲーム同梱ファイルは次の 2 種類だけです。
      sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan (存在するもの全て) の
      lib\stable-diffusion.dll
        プロキシに差し替え。オリジナルはバッチが同じ lib\ 内に
        stable-diffusion-real.dll として自動退避します
      runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
        SDXL モードへ切り替えたときのみ書き換え。初回の書き換え前に
        mod_files\taesd_sd15.safetensors へ自動退避します
    自動退避があるため手動バックアップは必須ではありませんが、
    コピーを取っておくと安心です。
    (LoRA ファイルは一切上書き・リネームされません)

(2) zip の中身をゲームルート (instantale.exe のあるフォルダ) に展開。
    「上書きしますか?」は すべて上書き。

(3) install_sd15.bat をダブルクリックで 1 回実行 (ゲームは閉じておく)。
    やること:
    - sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のうち存在する各バックエンドの
      lib\stable-diffusion.dll (オリジナル) を、同じ lib\ 内に
      stable-diffusion-real.dll としてコピー (プロキシの転送先)
    - mod_files\stable-diffusion-proxy.dll を各バックエンドの
      lib\stable-diffusion.dll として配置
    - TAESD デコーダを SD1.5 標準版に設定
    - sd_upscale.ini を sd_upscale.sd15.ini の内容に設定
      (上書き前に sd_upscale.ini.bak へ退避します)
    以前 SDXL モードにしていた場合も、このバッチだけで SD1.5 用に
    統一されます。冪等なので何度実行しても壊れません。

(4) ゲームを起動して生成テスト。ゲーム内のモデルは SD1.5 系のまま。

【重要】Epic Games Launcher などの「ファイルの検証」や自動アップデートは、
ゲーム同梱ファイル (stable-diffusion.dll と taesd) をオリジナルに巻き戻し
ます。巻き戻ったら install_sd15.bat をもう一度実行すれば全て復旧します。
可能ならランチャー側でこのゲームの自動アップデートを無効にしてください。

--------------------------------------------------------------------------------
4. 仕組みメモ
--------------------------------------------------------------------------------
- ゲーム本体は Nuitka コンパイル済みで改変不可。そのため画像生成が呼ぶ
  sdcpp_<バックエンド>\lib\stable-diffusion.dll (cuda / cpu / vulkan) を
  プロキシに差し替えてフックしています。バックエンドごとにオリジナル DLL
  が異なるため、プロキシは自分と同じフォルダに退避された
  stable-diffusion-real.dll を読み込みます (無ければ旧版どおりゲーム
  ルート直下を参照)。
- プロキシは generate_image のたびに sd_upscale.ini を読み直します
  (編集 → 次の生成から反映。ゲーム再起動・再ビルド不要)。
- キャラは 2 段生成 (txt2img 縦長 → img2img 縦長)、背景は 1 段 txt2img
  (横長) + LCM-LoRA。プロキシは img2img の init/mask 画像も拡大してから
  本体に渡します (これをしないとアクセス違反で落ちます)。
- SD1.5 標準モデルでは TAESD も SD1.5 用なので latent はそのまま正しく
  デコードされます。ゲームが読み込む LoRA も SD1.5 用のため、[lora_map]
  は空 (付け替えなし) で問題ありません。
- 動作ログはゲームルートの proxy_resize.log に出ます。

--------------------------------------------------------------------------------
5. sd_upscale.ini : [upscale] (解像度設定)
--------------------------------------------------------------------------------
enabled=1                  0 にするとゲーム本来のサイズのまま (パススルー)
goal_short=832             縦長/正方形 (キャラ等): 短辺の目標 px
max_long=1216              縦長/正方形: 長辺の上限 px
round=64                   両辺をこの倍数に丸める
goal_short_landscape=0     横長 (背景): 短辺目標。0 で上の値を流用
max_long_landscape=0       横長 (背景): 長辺上限。0 で上の値を流用
enabled_portrait=1         画像の種類別の有効/無効 (portrait/landscape/square)。
enabled_landscape=1        0 でその種類だけパススルー。行を消すと 1 に戻る
enabled_square=1
skip_if =                  ゲーム本来のプロンプトが条件に一致した生成を
skip_if_portrait =         アップスケールしない。skip_if は全種類共通、
skip_if_landscape =        skip_if_<種類> はその種類のみ。条件の書式は
skip_if_square =           [lora_add_if] と同じ (「/」区切り、「!」で不含有。
                           単語境界つき・大文字小文字不問)。
                           例: skip_if = pixel art/sprite

アスペクト比は維持されます。SD1.5 は高解像度に弱く、大きくしすぎると
人体の二重化などが出ます。目安:
  512 / 1024    変化なし (ゲーム標準)
  832 / 1216    SD1.5 の安全圏。まず崩れない (このモードの既定)
  896 / 1408    やや攻めた設定。二重化が出たら戻す

--------------------------------------------------------------------------------
6. sd_upscale.ini : LoRA の差し替え・追加
--------------------------------------------------------------------------------
LoRA ファイルはすべて runtime\models\sd15\lora\ に置きます (.safetensors)。
このモードで追加する LoRA は必ず SD1.5 用のものを使ってください
(SDXL 用 LoRA を SD1.5 モデルに当てるとゲームごとクラッシュします)。

[lora_map] -- ゲームが要求する LoRA の付け替え/無効化
  SD1.5 モードでは基本的に空のままで OK (ゲーム標準の LoRA がそのまま
  正しく動きます)。背景を通常サンプラーに差し替える場合だけ、セットで
  LCM LoRA を無効化します:
    LCM_LoRA_Weights_SD15 = off

[lora_add] -- 画像の種類別に LoRA やタグを追加
    portrait  = キャラ/モンスター (縦長)
    landscape = 背景 (横長)
    square    = その他 (正方形)
  例:
    portrait  = <lora:myCharStyle15:0.7>, masterpiece, best quality
    landscape = <lora:myBgStyle15:0.6>, scenery

[negative_add] -- 同じ書式でネガティブプロンプトに追加
  例:
    portrait = bad hands, extra fingers

すべて生成のたびに読み直されるので、ゲームを起動したまま LoRA を
付け替えて効き具合を比較できます。

[sampler] -- 画像の種類別にサンプラー設定を上書き
    <種類>_method / <種類>_steps / <種類>_cfg / <種類>_scheduler
    (種類 = portrait / landscape / square。未記入の項目はゲームの設定のまま)
  背景はゲーム標準だと LCM サンプラー + 低 CFG の約 1 秒生成です。SD1.5
  標準ではこれで成立していますが、彩度や描き込みを上げたい場合は
  landscape_* を euler_a / 24 steps / cfg 5.0 などに差し替えられます
  (生成時間は 10 秒前後に増加)。この差し替えを使う間は [lora_map] に
  LCM_LoRA_Weights_SD15 = off を書くこと (LCM LoRA は通常サンプラーと
  相性が悪い)。cfg が効くので [negative_add] の landscape も有効になります。

--------------------------------------------------------------------------------
7. アンインストール / ロールバック
--------------------------------------------------------------------------------
(1) 各バックエンド (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan) について、
    lib\stable-diffusion-real.dll を lib\stable-diffusion.dll に
    コピー (上書き) し、lib\stable-diffusion-real.dll を削除。
    旧版 (v1) から使っていてルートに stable-diffusion-real.dll がある
    場合は、それを sdcpp_cuda\lib\stable-diffusion.dll に戻して削除。
(2) taesd は SD1.5 版のままなので通常は操作不要 (SDXL に切り替えていた
    場合は switch_sd_mode.bat sd15 で戻すか、バックアップを復元)。
(3) sd_upscale.ini, sd_upscale.ini.bak, sd_upscale.sd15.ini,
    sd_upscale.sdxl.ini, proxy_resize.log, mod_files, mod_src,
    README_SD15_MOD.txt, README_SDXL_MOD.txt, install_sd15.bat,
    install_sdxl.bat, switch_sd_mode.bat を削除。
    (SD1.5 モードでは使っていない LCM_LoRA_SDXL.safetensors も削除して可)

--------------------------------------------------------------------------------
8. SD1.5 <-> SDXL のモード切替 (switch_sd_mode.bat)
--------------------------------------------------------------------------------
プロキシ DLL は両モード共通です。モードの違いは (a) TAESD デコーダ
(SD1.5=標準 TAESD / SDXL=TAESDXL) と (b) sd_upscale.ini の内容 (解像度・
[lora_map]) だけです。switch_sd_mode.bat がこの 2 つをまとめて入れ替えます。

  switch_sd_mode.bat        現在と逆のモードへトグル
  switch_sd_mode.bat sd15   SD1.5 モードへ強制
  switch_sd_mode.bat sdxl   SDXL モードへ強制

切替の直前に、現在の sd_upscale.ini が sd_upscale.<現モード>.ini として
保存されるので、モードごとのチューニングは往復しても保持されます。
必ずゲームを閉じてから実行し、切替後はゲーム内で同系統のチェックポイント
(SD1.5 モード = SD1.5 モデル) を選んでください。

SDXL への差し替え手順は README_SDXL_MOD.txt を参照。

--------------------------------------------------------------------------------
9. プロキシ DLL の再ビルド (改造したい場合)
--------------------------------------------------------------------------------
Python があれば:  pip install ziglang
mod_src で:
  python -m ziglang cc -target x86_64-windows-gnu -O2 -shared ^
      -o stable-diffusion-proxy.dll proxy.c exports.def
できた stable-diffusion-proxy.dll を mod_files\ に置き、
install_sd15.bat (または install_sdxl.bat) を再実行。
単体テスト:
  python -m ziglang cc -target x86_64-windows-gnu -O1 -DPROXY_TEST ^
      -o proxy_test.exe proxy.c
  (テスト用の sd_upscale.ini は mod_src\test\ に同梱。その ini と同じ
   フォルダで proxy_test.exe を実行)
================================================================================
