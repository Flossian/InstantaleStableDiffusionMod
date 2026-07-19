================================================================================
 Instantale SDXL (Illustrious-XL) 化 MOD  -  2026-07-19
================================================================================

Instantale の画像生成を SD1.5 から SDXL 系モデルに置き換え、生成解像度の
引き上げと、LoRA の差し替え・追加適用 (ゲーム側では開放されていない機能)
を可能にする MOD 一式です。

この MOD は SDXL と SD1.5 の両モードに対応し、GUI (mod_gui.bat) で相互に
切り替えられます (下記 9.)。SDXL には差し替えず、ゲーム標準の SD1.5
モデルのまま「アップスケール + LoRA 追加 + サンプラー上書き」機能だけを
使いたい場合は、同梱の README_SD15_MOD.txt を参照してください。
--- このファイルは SDXL モードの導入手順です ---

導入は 3 ステップ:
  (1) SDXL チェックポイントを入手して配置 (下記 2. 参照。zip には含まれません)
  (2) zip をゲームのルートフォルダ (instantale.exe があるフォルダ) に展開
      (MOD 一式は tools\InstantaleStableDiffusionMod\ に入ります)
  (3) tools\InstantaleStableDiffusionMod\mod_gui.bat を起動し、
      「導入 / 管理」タブの「SDXL モードで導入 / 修復」を押す
      (DLL 導入 + TAESD + ini を SDXL 用に)

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
ありません。ゲーム側で書き換えるのはゲーム同梱の DLL / TAESD のみです。

このほかに次のファイルが自動生成されます (手動編集は不要):
  settings.ini (MOD ツールフォルダ内)
      GUI が検出/指定されたゲームルートのパスを保存し、次回から
      自動使用します。ツールがゲームフォルダ内にあれば自動検出、
      外にある場合は初回のみフォルダ選択を求められます

README_SDXL_MOD.txt            このファイル (SDXL モードの手順)
README_SD15_MOD.txt            SD1.5 標準モデルのまま使う場合の手順
mod_gui.bat                    統合 GUI の起動 (推奨。下記 3.)。導入・
                               SDXL/SD1.5 モード切替・アンインストール・
                               状態確認・sd_upscale.ini のフォーム編集を
                               この 1 つで行います
mod_gui.ps1                    統合 GUI 本体 (PowerShell 製)
sd_upscale.sdxl.ini            SDXL モード用の設定プリセット (下記 5./6. 参照)。
                               GUI の導入時にこの内容が、実際に読み込まれる
                               sd_upscale.ini として書き出されます (現在有効な
                               設定ファイル sd_upscale.ini は導入時に生成)
sd_upscale.sd15.ini            SD1.5 モード用の設定プリセット
mod_files\stable-diffusion-proxy.dll
                               自作プロキシ DLL (約 200KB)。generate_image を
                               フックして解像度とプロンプト (LoRA タグ) を
                               差し替え、他 27 個の export はオリジナル DLL へ
                               転送します。GUI が各バックエンド
                               (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan) の
                               lib\stable-diffusion.dll として配置します
mod_src\proxy.c                プロキシ DLL のソース
mod_src\exports.def            転送 (forwarder) 定義
mod_licenses\                  ダウンロードして使うモデルのライセンス表記
                               (TAESDXL=MIT, LCM-LoRA SDXL=OpenRAIL++-M)

※ 同梱していない (各自ダウンロード。URL は下記 2.):
   - TAESDXL (SDXL 用 latent デコーダ)             [SDXL モードで必須]
   - LCM-LoRA SDXL (背景を LCM で生成する場合のみ)   [任意]
   - SDXL チェックポイント本体 (ライセンス上再配布不可)
   - オリジナルの stable-diffusion.dll (GUI が導入先のものを流用)
   なお SD1.5 用 TAESD は SDXL 導入時に GUI がゲーム同梱の元ファイルから
   自動退避するため、ダウンロードは不要です。

--------------------------------------------------------------------------------
2. ダウンロードして配置するファイル
--------------------------------------------------------------------------------
SDXL モードでは容量の大きいモデル類を同梱していません。以下を各自で
ダウンロードして所定の場所に、指定のファイル名で置いてください。

(a) SDXL チェックポイント  [必須]
    動作確認済み: WAI-illustrious (civitai model 827184)
      https://civitai.com/models/827184
    ダウンロードした safetensors を
      runtime\models\sd15\checkpoints\
    に置く (開発環境でのファイル名は waiIllustriousSDXL_v170.safetensors)。
    他の SDXL / Illustrious 系でも可。ただし:
      - SD1.5 系は不可 (TAESDXL を使うため latent が合わず破綻)
      - v-pred 系 (NoobAI vpred 等) は同梱 sd.cpp が非対応の可能性大
      - Pony 系は固定プロンプトにスコアタグが無く画風が出にくい
        ([lora_add] で score タグを注入すれば補える。下記 6.)
      - 高解像度耐性によっては [upscale] を下げる必要あり

(b) TAESDXL (SDXL 用 latent デコーダ)  [必須]  約 9.8MB
      https://huggingface.co/madebyollin/taesdxl/resolve/main/diffusion_pytorch_model.safetensors
    ダウンロードし、ファイル名を taesdxl.safetensors に変えて
      tools\InstantaleStableDiffusionMod\mod_files\taesdxl.safetensors
    として保存。GUI の SDXL 導入がこれを latent デコーダとして配置します
    (無いと SDXL の画像が緑色に破綻します)。

(c) LCM-LoRA SDXL  [任意]  約 394MB
      https://huggingface.co/latent-consistency/lcm-lora-sdxl/resolve/main/pytorch_lora_weights.safetensors
    ダウンロードし、ファイル名を LCM_LoRA_SDXL.safetensors に変えて
      runtime\models\sd15\lora\LCM_LoRA_SDXL.safetensors
    として保存。デフォルト設定は背景を通常サンプラー (euler_a) で生成する
    ため不要です。sd_upscale.ini で背景を LCM に戻す場合だけ必要になります
    (下記 6. の [lora_map] / [sampler])。

※ SD1.5 用 TAESD はダウンロード不要です。SDXL モードを初めて導入した
  とき、ゲーム同梱の SD1.5 デコーダを MOD フォルダ内の
  mod_files\taesd_sd15.safetensors へ自動退避し、以後 SD1.5 モードへ
  戻すときに再利用します。

--------------------------------------------------------------------------------
3. インストール手順
--------------------------------------------------------------------------------
(1) 上記 2. の (a) チェックポイントと (b) TAESDXL を配置
    (背景を LCM で出すなら (c) LCM-LoRA も)。

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
    「導入 / 管理」タブの「SDXL モードで導入 / 修復」を押す
    (ゲームは閉じておく)。ゲームルートは自動検出され、検出できない
    場合 (ゲームフォルダ外に置いた場合) は「変更...」ボタンで
    ゲームフォルダを選択します。決定したパスは settings.ini に保存され、
    次回から自動使用されます。
    やること:
    - 必要ファイル (TAESDXL) の存在を確認。無ければ DL URL を表示して中断
    - ゲーム同梱の SD1.5 TAESD を mod_files\taesd_sd15.safetensors へ自動退避
      (初回のみ。後で SD1.5 へ戻すとき用)
    - sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のうち存在する各バックエンドの
      lib\stable-diffusion.dll (オリジナル) を、同じ lib\ 内に
      stable-diffusion-real.dll としてコピー (プロキシの転送先)
    - mod_files\stable-diffusion-proxy.dll を各バックエンドの
      lib\stable-diffusion.dll として配置
    - TAESD デコーダを TAESDXL に設定
    - 設定フォルダ <ゲームルート>\InstantaleSDMod\ を作成し、
      sd_upscale.ini を sd_upscale.sdxl.ini (ツールフォルダ内のプリセット)
      の内容で生成 (既存の ini は sd_upscale.ini.bak へ退避。旧配置の
      ini があれば自動移行)
    冪等なので、Epic の検証などで巻き戻された時も再実行すれば全復旧します。
    実行内容はタブ下部のログに表示されます。

(4) ゲームを起動して生成テスト。ゲーム内のモデル選択で SDXL
    チェックポイントを選ぶこと。

【重要】Epic Games Launcher などの「ファイルの検証」や自動アップデートは、
ゲーム同梱ファイル (stable-diffusion.dll と taesd) をオリジナルに巻き戻し
ます。巻き戻ると背景生成でクラッシュ・画像の破綻が再発します。その場合は
「SDXL モードで導入 / 修復」をもう一度実行すれば全て復旧します (GUI の
状態表示にも巻き戻り検出が出ます)。可能ならランチャー側でこのゲームの
自動アップデートを無効にしてください。

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
- プロンプト書き換えは、構造体先頭のプロンプトポインタを初回呼び出し時に
  sd_img_gen_params_to_str の出力と突き合わせて検証してから有効化します。
  検証に失敗した場合は書き換えを自動停止し、素通しします (安全側)。
- プロキシは自分のパス (sdcpp_*\lib\) からゲームルートを逆算し、
  固定の設定フォルダ <ゲームルート>\InstantaleSDMod\ の sd_upscale.ini を
  読みます (フォルダが無い場合のみゲームの作業ディレクトリ直下へ
  フォールバック)。ゲーム側にポインタファイルを書く方式は廃止しました。
- 動作ログ proxy_resize.log も同じ設定フォルダに出ます (プロンプト
  書き換えの結果も最初の数回分記録されます)。
- VAE (vaeFtMse840000...) は SD1.5 のままですが、デコードは TAESDXL が
  使われるため実害はありません。

--------------------------------------------------------------------------------
5. sd_upscale.ini : [upscale] (解像度設定)
--------------------------------------------------------------------------------
enabled=1                  0 にするとゲーム本来のサイズのまま (パススルー)
goal_short=1024            縦長/正方形 (キャラ等): 短辺の目標 px
max_long=2048              縦長/正方形: 長辺の上限 px
round=64                   両辺をこの倍数に丸める
goal_short_landscape=704   横長 (背景): 短辺目標。0 で上の値を流用
max_long_landscape=1408    横長 (背景): 長辺上限。0 で上の値を流用
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
例: キャラ画像 512x1024 の場合、
  1024/2048 (既定)  → 倍率 2.0    → 1024x2048
  832/1216          → 倍率 1.1875 → 608x1216 → 丸めて 640x1216
    (長辺上限が先に効くため短辺は 832 に届きません。832 にしたいときは
     max_long も比例させます: 832/1664 → 出力 832x1664)

背景 (横長) を控えめにしてあるのは、背景は LoRA 分の VRAM も食うため
大きくすると OOM で落ちやすいからです (RTX 4070 Ti Super 16GB 基準)。
チェックポイントによっては 1024/2048 で人体の二重化などの破綻が出ます。
その場合は 832/1216 程度まで下げてください。

--------------------------------------------------------------------------------
6. sd_upscale.ini : LoRA の差し替え・追加 (この MOD の目玉機能)
--------------------------------------------------------------------------------
LoRA ファイルはすべて runtime\models\sd15\lora\ に置きます (.safetensors)。

[lora_map] -- ゲームが要求する LoRA の付け替え/無効化
    ゲーム内の名前 = 実ファイル名[:強度]      (拡張子なし)
    ゲーム内の名前 = off                      (適用しない)
  デフォルト設定 (SDXL 用):
    LCM_LoRA_Weights_SD15 = LCM_LoRA_SDXL:1.0   ← 背景の LCM を SDXL 版へ
    HyperSD_1step_Lora = off                     ← SD1.5 専用なので無効化
    PixelArtRedmond15V-PixelArt-PIXARFK = off    ← 同上
  【重要】SD1.5 用 LoRA が SDXL モデルに適用されるとゲームごとクラッシュ
  します。この 3 行がそれを防いでいるので、SDXL で使う間は消さないこと。

[lora_add] -- 画像の種類別に LoRA やタグを追加
    portrait  = キャラ/モンスター (縦長)
    landscape = 背景 (横長)
    square    = その他 (正方形)
  例:
    portrait  = <lora:myCharStyleXL:0.7>, masterpiece, best quality
    landscape = <lora:myBgStyleXL:0.6>, scenery

[negative_add] -- 同じ書式でネガティブプロンプトに追加
  例:
    portrait = bad hands, extra fingers

すべて生成のたびに読み直されるので、ゲームを起動したまま LoRA を
付け替えて効き具合を比較できます。追加する LoRA は必ずロード中の
チェックポイントと同系統 (SDXL なら SDXL/Illustrious 用) のものを!

[sampler] -- 画像の種類別にサンプラー設定を上書き
    <種類>_method / <種類>_steps / <種類>_cfg / <種類>_scheduler
    (種類 = portrait / landscape / square。未記入の項目はゲームの設定のまま)
  背景はゲーム標準だと LCM サンプラー + 低 CFG の約 1 秒生成のため、彩度が
  抜けた鉛筆画のようなモノクロになりがちです。デフォルト設定では背景だけ
  euler_a / 24 steps / cfg 5.0 に差し替えて解消しています (背景の生成時間は
  10 秒前後に増えます)。この差し替えを使う間は [lora_map] の LCM 行を off に
  すること (LCM LoRA は通常サンプラーと相性が悪い)。cfg が効くようになる
  ので [negative_add] の landscape (例: monochrome, greyscale) も有効です。

--------------------------------------------------------------------------------
7. アンインストール / ロールバック
--------------------------------------------------------------------------------
mod_gui.bat の「導入 / 管理」タブで「アンインストール (原状復帰)」を
押すと、次の処理が自動で行われます (ゲームは閉じておくこと):
- 各バックエンドの lib\stable-diffusion.dll を退避してあった
  オリジナルに書き戻し、退避 DLL (stable-diffusion-real.dll) を削除
  (旧版 v1 のゲームルート直下の退避 DLL、v2.0 の lib\ 内ポインタ ini に
   も対応し、あわせて削除)
- TAESD デコーダを SD1.5 版 (mod_files\taesd_sd15.safetensors) に復元
- 設定フォルダ <ゲームルート>\InstantaleSDMod\ を削除
最後に MOD ツールフォルダごと手動で削除してください (GUI 自身が
入っているため自動削除はされません)。あわせて
runtime\models\sd15\lora\LCM_LoRA_SDXL.safetensors と自分で配置した
SDXL チェックポイントを削除。
(旧版 v1.x から使っていてゲームルート直下に sd_upscale.ini*,
 proxy_resize.log, mod_files 等が残っている場合はそれらも削除)

GUI が使えない場合の手動手順:
(1) 各バックエンド (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan) について、
    lib\stable-diffusion-real.dll を lib\stable-diffusion.dll に
    コピー (上書き) し、lib\stable-diffusion-real.dll を削除
    (lib\stable-diffusion-proxy.ini が残っていればそれも削除)。
    旧版 (v1) から使っていてルートに stable-diffusion-real.dll がある
    場合は、それを sdcpp_cuda\lib\stable-diffusion.dll に戻して削除。
(2) mod_files\taesd_sd15.safetensors を
    runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors に復元。
(3) <ゲームルート>\InstantaleSDMod\ と MOD ツールフォルダ、
    上記の追加モデルを削除。

--------------------------------------------------------------------------------
8. プロキシ DLL の再ビルド (改造したい場合)
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

--------------------------------------------------------------------------------
9. SD1.5 <-> SDXL のモード切替
--------------------------------------------------------------------------------
プロキシ DLL は両モード共通です。モードの違いは (a) TAESD デコーダ
(SDXL=TAESDXL / SD1.5=標準 TAESD) と (b) sd_upscale.ini の内容 (解像度・
[lora_map]) だけです。mod_gui.bat の「導入 / 管理」タブにある
「モード切替: SD1.5 へ / SDXL へ」ボタンがこの 2 つをまとめて入れ替えます。
現在のモードはタブ上部の状態表示で確認できます。

切替の直前に、現在の sd_upscale.ini が sd_upscale.<現モード>.ini として
保存されるので、モードごとのチューニングは往復しても保持されます。
必ずゲームを閉じてから実行し、切替後はゲーム内で同系統
(SD1.5 モード = SD1.5 モデル / SDXL モード = SDXL モデル) の
チェックポイントを選んでください。系統を取り違えると画像が破綻・
クラッシュします。

この自動入れ替えを使わず設定ファイルを手動で管理したい場合は、
「既存の ini を読み込んで適用...」ボタンで任意の ini ファイルを選ぶと、
それがそのまま有効な sd_upscale.ini になります (適用前の内容は
sd_upscale.ini.bak に退避。TAESD デコーダやプロキシ DLL には触りません)。
ini の内容 ([upscale] / [lora_map]) が現在のモードと合っているかは
自分で確認してください。

SD1.5 標準モデルのまま使う詳しい手順は README_SD15_MOD.txt を参照。
================================================================================
