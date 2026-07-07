@echo off
rem このファイルは Shift-JIS (CP932) で保存すること (cmd.exe が日本語
rem Windows の既定コードページで直接パースするため。UTF-8 + chcp 65001 は
rem cmd の再読込オフセットずれで誤動作する)
rem ============================================================
rem  Instantale SDXL <-> SD1.5 モード切り替え
rem  TAESD 潜在デコーダと sd_upscale.ini を 2 つのモデル系列間で
rem  入れ替える。ゲームを終了した状態で実行すること。
rem
rem    switch_sd_mode.bat        -> もう一方のモードへトグル
rem    switch_sd_mode.bat sdxl   -> SDXL モードを強制
rem    switch_sd_mode.bat sd15   -> SD1.5 モードを強制
rem
rem  切り替え前に現在の sd_upscale.ini を sd_upscale.<モード>.ini へ
rem  保存するため、モードごとの調整が往復しても失われない。
rem  TAESDXL は同梱されていない: 先に install_sdxl.bat を一度実行するか
rem  (ダウンロードを確認し SD1.5 デコーダを退避してくれる)、
rem  mod_files\taesdxl.safetensors を自分で配置すること。
rem  切り替え後は、ゲームのモデル選択で同じ系列のチェックポイントを
rem  選ぶこと (SD1.5 モデル + SDXL モード、またはその逆は画像の破綻や
rem  クラッシュの原因になる)。
rem ============================================================
setlocal
cd /d "%~dp0"

set TAESD=runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
set XL=mod_files\taesdxl.safetensors
set S15=mod_files\taesd_sd15.safetensors

if not exist "%TAESD%" (
    echo [エラー] %TAESD% が見つかりません。ここはゲームフォルダですか?
    goto end
)

rem --- 導入済み taesd から現在のモードを判定する (参照ファイルが必要) ---
set CUR=unknown
if not exist "%XL%" goto chk_s15
fc /b "%TAESD%" "%XL%" >nul 2>&1
if not errorlevel 1 set CUR=sdxl
:chk_s15
if not "%CUR%"=="unknown" goto cur_done
if not exist "%S15%" goto cur_done
fc /b "%TAESD%" "%S15%" >nul 2>&1
if not errorlevel 1 set CUR=sd15
:cur_done

set TARGET=%~1
if "%TARGET%"=="" if "%CUR%"=="sdxl" set TARGET=sd15
if "%TARGET%"=="" if "%CUR%"=="sd15" set TARGET=sdxl
if "%TARGET%"=="" (
    echo [エラー] 現在のモードを自動判定できません。
    echo         明示的に指定してください:  switch_sd_mode.bat sdxl
    echo                             または:  switch_sd_mode.bat sd15
    goto end
)
if /i "%TARGET%"=="sdxl" goto target_ok
if /i "%TARGET%"=="sd15" goto target_ok
echo [エラー] 不明なモード "%TARGET%" - sdxl か sd15 を指定してください
goto end
:target_ok

rem --- 切り替え先モードには、対応するデコーダファイルが必要 ---
if /i "%TARGET%"=="sdxl" if not exist "%XL%" goto need_xl
if /i "%TARGET%"=="sd15" if not exist "%S15%" goto need_s15
goto files_ok
:need_xl
echo [エラー] %XL% が見つかりません ^(SDXL モードに必要^)。
echo         TAESDXL は同梱されていません - ダウンロードしてください:
echo         https://huggingface.co/madebyollin/taesdxl/resolve/main/diffusion_pytorch_model.safetensors
echo         次の名前で保存してください  %XL%
goto end
:need_s15
echo [エラー] %S15% が見つかりません。
echo         これは install_sdxl.bat を初回実行した際に自動で退避されます。
echo         一度も SDXL に切り替えていない場合、ゲーム標準の SD1.5 用 TAESD が
echo         既に有効なので切り替えは不要です。
echo         それ以外の場合は SD1.5 デコーダをダウンロードしてください:
echo         https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors
echo         次の名前で保存してください  %S15%
goto end
:files_ok

echo 現在のモード: %CUR%  -^>  切り替え先: %TARGET%

rem --- 現在のモードの ini を保存してから、切り替え先の ini を読み込む ---
if not "%CUR%"=="unknown" if exist sd_upscale.ini copy /y sd_upscale.ini "sd_upscale.%CUR%.ini" >nul
if exist "sd_upscale.%TARGET%.ini" (
    copy /y "sd_upscale.%TARGET%.ini" sd_upscale.ini >nul
    echo [ok]   sd_upscale.ini を sd_upscale.%TARGET%.ini から読み込みました
) else (
    echo [警告] sd_upscale.%TARGET%.ini が見つかりません - 現在の
    echo        sd_upscale.ini を維持します。[lora_map] を自分で確認してください!
    echo        ^(SD1.5 用 LoRA を SDXL モデルに適用するとゲームがクラッシュします^)
)

rem --- taesd デコーダを入れ替える ---
if /i "%TARGET%"=="sdxl" copy /b /y "%XL%" "%TAESD%" >nul
if /i "%TARGET%"=="sd15" copy /b /y "%S15%" "%TAESD%" >nul
echo [ok]   TAESD デコーダを %TARGET% 用に設定しました

echo.
echo 完了しました。ゲームを起動し、ゲーム内で %TARGET% のチェックポイントを選んでください。
:end
pause
exit /b 0
