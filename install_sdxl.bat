@echo off
rem このファイルは Shift-JIS (CP932) で保存すること (cmd.exe が日本語
rem Windows の既定コードページで直接パースするため。UTF-8 + chcp 65001 は
rem cmd の再読込オフセットずれで誤動作する)
rem ============================================================
rem  Instantale MOD - SDXL モード インストーラ (ワンクリック)
rem  プロキシ DLL を導入し、SDXL (Illustrious-XL 等) 向けに
rem  TAESD デコーダと sd_upscale.ini を設定する。
rem  ゲームを終了した状態で実行すること。何度実行しても安全。
rem
rem  プロキシは sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のうち存在する
rem  すべてのバックエンドへ導入される。元の DLL は各バックエンドの
rem  lib\stable-diffusion-real.dll として退避される。
rem
rem  TAESDXL と LCM-LoRA は同梱されていないため、自分で
rem  ダウンロードすること (README_SDXL_MOD.txt の 2 章を参照)。
rem  ファイルが足りない場合、このスクリプトが正確な URL とパスを表示する。
rem ============================================================
setlocal
cd /d "%~dp0"

set PROXYSRC=mod_files\stable-diffusion-proxy.dll
set LEGACYREAL=stable-diffusion-real.dll
set TAESD=runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
set XL=mod_files\taesdxl.safetensors
set S15=mod_files\taesd_sd15.safetensors
set LORA=runtime\models\sd15\lora\LCM_LoRA_SDXL.safetensors
set INI=sd_upscale.sdxl.ini
set CKPTDIR=runtime\models\sd15\checkpoints
set CKPT=waiIllustriousSDXL_v170.safetensors

echo ============================================
echo  Instantale MOD : SDXL モードをインストール
echo ============================================
echo.

rem --- [1/4] 必須 / 要ダウンロードのファイル確認 ---
echo [1/4] ファイル確認
if not exist "%XL%" (
    echo    [エラー] %XL% が見つかりません。
    echo            TAESDXL は同梱されていません - 自分でダウンロードしてください:
    echo            https://huggingface.co/madebyollin/taesdxl/resolve/main/diffusion_pytorch_model.safetensors
    echo            次の名前で保存してください  %XL%
    echo            ^(README_SDXL_MOD.txt の 2 章を参照^)
    goto end
)
echo    [ok]   TAESDXL を確認しました
if exist "%CKPTDIR%\%CKPT%" (
    echo    [ok]   SDXL チェックポイント %CKPT% を確認しました
) else (
    echo    [警告] SDXL チェックポイントが %CKPTDIR%\ に見つかりません - README 2 章を参照。
    echo           別の SDXL チェックポイントを置いた場合はこの警告を無視して構いません。
)
if not exist "%LORA%" (
    echo    [警告] LCM-LoRA が見つかりません ^(%LORA%^)。
    echo           sd_upscale.ini で背景を LCM サンプラーに戻す場合のみ必要です。
    echo           任意ダウンロード:
    echo           https://huggingface.co/latent-consistency/lcm-lora-sdxl/resolve/main/pytorch_lora_weights.safetensors
    echo           次の名前で保存してください  %LORA%
)
echo.

rem --- [2/4] プロキシ DLL (存在するすべてのバックエンドへ導入) ---
echo [2/4] プロキシ DLL
if not exist "%PROXYSRC%" (
    echo    [エラー] %PROXYSRC% が見つかりません。先に zip 全体を展開してください。
    goto end
)
set FOUND=0
set DONE=0
for %%B in (sdcpp_cuda sdcpp_cpu sdcpp_vulkan) do call :proxy_one %%B
if %FOUND%==0 (
    echo    [エラー] sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のいずれにも
    echo            lib\stable-diffusion.dll が見つかりません。ここはゲームフォルダですか?
    goto end
)
if %DONE%==0 goto end
echo.

rem --- [3/4] TAESD デコーダ (SDXL) ---
echo [3/4] TAESD デコーダ
if not exist "%TAESD%" (
    echo    [エラー] %TAESD% が見つかりません。ここはゲームフォルダですか?
    goto end
)
rem 初回の SDXL インストール時に、ゲーム標準の SD1.5 用 TAESD を退避しておく。
rem これにより install_sd15.bat / switch_sd_mode.bat が後でダウンロード無しに
rem 復元できる。まだバックアップが無く、かつ現在のファイルが TAESDXL でない
rem 場合のみ退避する。
if not exist "%S15%" (
    fc /b "%TAESD%" "%XL%" >nul 2>&1
    if errorlevel 1 (
        copy /b /y "%TAESD%" "%S15%" >nul
        echo    [ok]   ゲーム標準の SD1.5 用 TAESD を %S15% に保存しました
        echo           ^(後で SD1.5 モードへ復元する際に再利用 - ダウンロード不要^)
    )
)
copy /b /y "%XL%" "%TAESD%" >nul
echo    [ok]   TAESDXL をデコーダとして導入しました
echo.

rem --- [4/4] sd_upscale.ini (SDXL プリセット) ---
echo [4/4] sd_upscale.ini
if exist "%INI%" (
    if exist sd_upscale.ini copy /y sd_upscale.ini sd_upscale.ini.bak >nul
    copy /y "%INI%" sd_upscale.ini >nul
    echo    [ok]   sd_upscale.ini を %INI% から読み込みました
) else (
    echo    [ok]   %INI% が見つかりません - 現在の sd_upscale.ini を維持します
)
echo.
echo 完了しました。ゲームを起動し、ゲーム内で SDXL のチェックポイントを選んでください。
:end
echo.
pause
exit /b 0

rem ============================================================
rem  サブルーチン: 1 つのバックエンド (%1 = フォルダ名) にプロキシを導入。
rem  元の DLL は同じ lib\ 内へ stable-diffusion-real.dll として退避する。
rem  (プロキシは自分と同じフォルダの stable-diffusion-real.dll を優先して
rem   読み込み、無ければ旧版どおりゲームルート直下を参照する)
rem ============================================================
:proxy_one
set B=%1
set LIBDLL=%B%\lib\stable-diffusion.dll
set REALDLL=%B%\lib\stable-diffusion-real.dll
if not exist "%LIBDLL%" exit /b 0
set FOUND=1
for %%F in ("%LIBDLL%") do set LIBSIZE=%%~zF
if %LIBSIZE% LEQ 10000000 goto po_proxy
rem -- 元の DLL がまだ入っている --
if exist "%REALDLL%" (
    echo    [ok]   %B%: 退避済みの元 DLL が既にあります。そのまま使用します
) else (
    echo    [ok]   %B%: 元の DLL を lib\stable-diffusion-real.dll へ保存中 ... 少し時間がかかります
    copy /b /y "%LIBDLL%" "%REALDLL%" >nul
)
goto po_install
:po_proxy
rem -- 既にプロキシが入っている: 退避済みの元 DLL を確認 --
if exist "%REALDLL%" goto po_install
if not "%B%"=="sdcpp_cuda" goto po_noreal
if not exist "%LEGACYREAL%" goto po_noreal
echo    [ok]   %B%: 旧版の退避先 ^(ルートの %LEGACYREAL%^) を元 DLL として使用します
goto po_install
:po_noreal
echo    [エラー] %B%: lib\stable-diffusion.dll は既にプロキシですが、
echo            退避された元 DLL ^(%REALDLL%^) がありません。
echo            元の stable-diffusion.dll を %B%\lib\ に戻してから再実行してください。
exit /b 0
:po_install
copy /b /y "%PROXYSRC%" "%LIBDLL%" >nul
echo    [ok]   %B%: プロキシを導入しました
set DONE=1
exit /b 0
