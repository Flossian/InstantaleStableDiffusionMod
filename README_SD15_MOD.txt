================================================================================
 Instantale 画質強化 MOD (SD1.5 標準モデル版)  -  2026-07-19
================================================================================

ゲーム標準の SD1.5 モデルのまま、生成解像度の引き上げと、LoRA の
差し替え・追加適用・サンプラー上書き (いずれもゲーム側では開放されて
いない機能) を可能にする MOD です。SDXL への差し替えは行いません。

SDXL 系モデル (Illustrious 等) に置き換えて更に高解像度・高画質を狙う
場合は、同梱の README_SDXL_MOD.txt を参照してください。両モードは
GUI (mod_gui.bat) で相互に切り替えられます (下記 8.)。

このモードの利点:
- SDXL チェックポイントのダウンロード不要 (ゲーム標準モデルをそのまま使用)
- TAESD デコーダは SD1.5 標準のまま (緑色破綻の心配なし)
- ゲームが要求する LoRA はすべて SD1.5 用なので [lora_map] は空でも動く
- VRAM が少ない環境でも動きやすい (SDXL より軽い)

導入は 2 ステップ:
  (1) zip をゲームのルートフォルダ (instantale.exe があるフォルダ) に展開
      (MOD 一式は tools\InstantaleStableDiffusionMod\ に入ります。
       ゲームルート直下にファイルは置かれません)
  (2) tools\InstantaleStableDiffusionMod\mod_gui.bat を起動し、
      「導入 / 管理」タブの「SD1.5 モードで導入 / 修復」を押す
      (DLL 導入 + TAESD + sd_upscale.ini をまとめて SD1.5 用に)

--------------------------------------------------------------------------------
1. 同梱ファイル
--------------------------------------------------------------------------------
zip では <ゲームルート>\tools\InstantaleStableDiffusionMod\ に入りますが、
MOD ツールフォルダは任意の場所・任意の名前に移動できます (移動したら
GUI で「導入 / 修復」を再実行)。

実際に読み込まれる設定ファイル (sd_upscale.ini) と動作ログ
(proxy_resize.log) は、GUI が導入時に作る固定の設定フォルダ
<ゲームルート>\InstantaleSDMod\ に置かれます。プロキシ DLL は自分の
パス (sdcpp_*\lib\) からゲームルートを逆算してこのフォルダを読み書き
するため、場所を知らせるためのファイルをゲーム側に書き込む必要は
ありません。ゲーム側で書き換えるのはゲーム同梱の DLL / TAESD のみです
(下記 3.(1) 参照)。

このほかに次のファイルが自動生成されます (手動編集は不要):
  settings.ini (MOD ツールフォルダ内)
      GUI が検出/指定されたゲームルートのパスを保存し、次回から
      自動使用します。ツールがゲームフォルダ内にあれば自動検出、
      外にある場合は初回のみフォルダ選択を求められます

README_SD15_MOD.txt            このファイル (SD1.5 モードの手順)
README_SDXL_MOD.txt            SDXL に差し替える場合の手順
mod_gui.bat                    統合 GUI の起動 (推奨。下記 3.)。導入・
                               SD1.5/SDXL モード切替・アンインストール・
                               状態確認・sd_upscale.ini のフォーム編集を
                               この 1 つで行います
mod_gui.ps1                    統合 GUI 本体 (PowerShell 製)
sd_upscale.sd15.ini            SD1.5 モード用の設定プリセット (下記 5./6.)。
                               GUI の導入時にこの内容が、実際に読み込まれる
                               sd_upscale.ini として書き出されます (現在有効な
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
        プロキシに差し替え。オリジナルは GUI が同じ lib\ 内に
        stable-diffusion-real.dll として自動退避します
      runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
        SDXL モードへ切り替えたときのみ書き換え。初回の書き換え前に
        mod_files\taesd_sd15.safetensors へ自動退避します
    自動退避があるため手動バックアップは必須ではありませんが、
    コピーを取っておくと安心です。
    (LoRA ファイルは一切上書き・リネームされません)

(2) zip の中身をゲームルート (instantale.exe のあるフォルダ) に展開。
    「上書きしますか?」は すべて上書き。MOD 一式は
    tools\InstantaleStableDiffusionMod\ に入ります。
    MOD フォルダは好きな場所 (ゲームフォルダ外でも可) へ移動して
    構いません。その場合は移動後に GUI で導入を実行してください。
    (旧版 v1.x をゲームルート直下に展開して使っていた場合もそのまま上に
     展開して OK。導入時にゲームルートの旧 sd_upscale.ini は MOD
     フォルダへ自動移行されます。ゲームルートに残った旧版のバッチや
     README、プリセット ini は手で削除して構いません)

(3) MOD フォルダ内の mod_gui.bat をダブルクリックで起動し、
    「導入 / 管理」タブの「SD1.5 モードで導入 / 修復」を押す
    (ゲームは閉じておく)。ゲームルートは自動検出され、検出できない
    場合 (ゲームフォルダ外に置いた場合) は「変更...」ボタンで
    ゲームフォルダを選択します。決定したパスは settings.ini に保存され、
    次回から自動使用されます。
    やること:
    - sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のうち存在する各バックエンドの
      lib\stable-diffusion.dll (オリジナル) を、同じ lib\ 内に
      stable-diffusion-real.dll としてコピー (プロキシの転送先)
    - mod_files\stable-diffusion-proxy.dll を各バックエンドの
      lib\stable-diffusion.dll として配置
    - TAESD デコーダを SD1.5 標準版に設定
    - 設定フォルダ <ゲームルート>\InstantaleSDMod\ を作成し、
      sd_upscale.ini を sd_upscale.sd15.ini (ツールフォルダ内のプリセット)
      の内容で生成 (既存の ini は sd_upscale.ini.bak へ退避。旧配置の
      ini があれば自動移行)
    以前 SDXL モードにしていた場合も、この操作だけで SD1.5 用に
    統一されます。冪等なので何度実行しても壊れません。実行内容は
    タブ下部のログに表示されます。

(4) ゲームを起動して生成テスト。ゲーム内のモデルは SD1.5 系のまま。

【重要】Epic Games Launcher などの「ファイルの検証」や自動アップデートは、
ゲーム同梱ファイル (stable-diffusion.dll と taesd) をオリジナルに巻き戻し
ます。巻き戻ったら「SD1.5 モードで導入 / 修復」をもう一度実行すれば全て
復旧します (GUI の状態表示にも巻き戻り検出が出ます)。可能ならランチャー側で
このゲームの自動アップデートを無効にしてください。

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
- プロキシは自分のパス (sdcpp_*\lib\) からゲームルートを逆算し、
  固定の設定フォルダ <ゲームルート>\InstantaleSDMod\ の sd_upscale.ini を
  読みます (フォルダが無い場合のみゲームの作業ディレクトリ直下へ
  フォールバック)。ゲーム側にポインタファイルを書く方式は廃止しました。
- 動作ログ proxy_resize.log も同じ設定フォルダに出ます。

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

新しいサイズの決まり方 (アスペクト比は常に維持、画像は歪めません):
  倍率 = min(goal_short ÷ 元の短辺, max_long ÷ 元の長辺)
         (1.0 未満にはならない = 縮小はしない)
  出力 = 元サイズ × 倍率 を、両辺とも round の倍数に四捨五入
goal_short は「短辺をちょうどこの値にする」指定ではなく、先に長辺が
max_long に達するとそこで拡大が止まります。
例: キャラ画像 512x1024 に goal_short=832 / max_long=1216 の場合、
  短辺基準 832÷512=1.625 より長辺上限 1216÷1024=1.1875 が小さいので
  1.1875 倍 → 608x1216 → 丸めて 640x1216 (短辺は 832 に届きません)。
  短辺を 832 にしたいときは max_long も比例させます
  (832/1664 → 出力 832x1664)。

SD1.5 は高解像度に弱く、大きくしすぎると人体の二重化などが出ます。
目安 (512x1024 のキャラ画像に適用した場合の出力):
  512 / 1024  → 512x1024   変化なし (ゲーム標準)
  832 / 1216  → 640x1216   SD1.5 の安全圏。まず崩れない (このモードの既定)
  896 / 1408  → 704x1408   やや攻めた設定。二重化が出たら戻す

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
mod_gui.bat の「導入 / 管理」タブで「アンインストール (原状復帰)」を
押すと、次の処理が自動で行われます (ゲームは閉じておくこと):
- 各バックエンドの lib\stable-diffusion.dll を退避してあった
  オリジナルに書き戻し、退避 DLL (stable-diffusion-real.dll) を削除
  (旧版 v1 のゲームルート直下の退避 DLL、v2.0 の lib\ 内ポインタ ini に
   も対応し、あわせて削除)
- TAESD デコーダが SDXL 版になっていた場合は SD1.5 版に復元
- 設定フォルダ <ゲームルート>\InstantaleSDMod\ を削除
最後に MOD ツールフォルダごと手動で削除してください (GUI 自身が
入っているため自動削除はされません)。
(旧版 v1.x から使っていてゲームルート直下に sd_upscale.ini*,
 proxy_resize.log, mod_files 等が残っている場合はそれらも削除。
 SD1.5 モードでは使っていない LCM_LoRA_SDXL.safetensors も削除して可)

GUI が使えない場合の手動手順:
(1) 各バックエンド (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan) について、
    lib\stable-diffusion-real.dll を lib\stable-diffusion.dll に
    コピー (上書き) し、lib\stable-diffusion-real.dll を削除
    (lib\stable-diffusion-proxy.ini が残っていればそれも削除)。
    旧版 (v1) から使っていてルートに stable-diffusion-real.dll がある
    場合は、それを sdcpp_cuda\lib\stable-diffusion.dll に戻して削除。
(2) taesd は SD1.5 版のままなら操作不要 (SDXL に切り替えていた場合は
    mod_files\taesd_sd15.safetensors を
    runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors に復元)。
(3) <ゲームルート>\InstantaleSDMod\ と MOD ツールフォルダを削除。

--------------------------------------------------------------------------------
8. SD1.5 <-> SDXL のモード切替
--------------------------------------------------------------------------------
プロキシ DLL は両モード共通です。モードの違いは (a) TAESD デコーダ
(SD1.5=標準 TAESD / SDXL=TAESDXL) と (b) sd_upscale.ini の内容 (解像度・
[lora_map]) だけです。mod_gui.bat の「導入 / 管理」タブにある
「モード切替: SD1.5 へ / SDXL へ」ボタンがこの 2 つをまとめて入れ替えます。
現在のモードはタブ上部の状態表示で確認できます。

切替の直前に、現在の sd_upscale.ini が sd_upscale.<現モード>.ini として
保存されるので、モードごとのチューニングは往復しても保持されます。
必ずゲームを閉じてから実行し、切替後はゲーム内で同系統のチェックポイント
(SD1.5 モード = SD1.5 モデル) を選んでください。

この自動入れ替えを使わず設定ファイルを手動で管理したい場合は、
「既存の ini を読み込んで適用...」ボタンで任意の ini ファイルを選ぶと、
それがそのまま有効な sd_upscale.ini になります (適用前の内容は
sd_upscale.ini.bak に退避。TAESD デコーダやプロキシ DLL には触りません)。
ini の内容 ([upscale] / [lora_map]) が現在のモードと合っているかは
自分で確認してください。

SDXL への差し替え手順は README_SDXL_MOD.txt を参照。

--------------------------------------------------------------------------------
9. プロキシ DLL の再ビルド (改造したい場合)
--------------------------------------------------------------------------------
Python があれば:  pip install ziglang
mod_src で:
  python -m ziglang cc -target x86_64-windows-gnu -O2 -shared ^
      -o stable-diffusion-proxy.dll proxy.c exports.def
できた stable-diffusion-proxy.dll を mod_files\ に置き、
GUI の「導入 / 修復」を再実行。
単体テスト:
  python -m ziglang cc -target x86_64-windows-gnu -O1 -DPROXY_TEST ^
      -o proxy_test.exe proxy.c
  (テスト用の sd_upscale.ini は mod_src\test\ に同梱。その ini と同じ
   フォルダで proxy_test.exe を実行)
================================================================================
