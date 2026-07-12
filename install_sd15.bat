@echo off
rem このファイルは Shift-JIS (CP932) で保存すること (cmd.exe が日本語
rem Windows の既定コードページで直接パースするため。UTF-8 + chcp 65001 は
rem cmd の再読込オフセットずれで誤動作する)
rem ============================================================
rem  Instantale MOD - SD1.5 モード インストーラ (ワンクリック)
rem  プロキシ DLL を導入し、標準の SD1.5 モデル向けに TAESD
rem  デコーダと sd_upscale.ini を設定する。
rem  ゲームを終了した状態で実行すること。何度実行しても安全。
rem
rem  プロキシは sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan のうち存在する
rem  すべてのバックエンドへ導入される。元の DLL は各バックエンドの
rem  lib\stable-diffusion-real.dll として退避される。
rem
rem  SD1.5 モードでは何もダウンロードする必要はない。ゲームには
rem  SD1.5 モデルとその SD1.5 用 TAESD デコーダが最初から同梱されている。
rem ============================================================
setlocal
cd /d "%~dp0"

set PROXYSRC=mod_files\stable-diffusion-proxy.dll
set LEGACYREAL=stable-diffusion-real.dll
set TAESD=runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
set S15=mod_files\taesd_sd15.safetensors
set INI=sd_upscale.sd15.ini

echo ============================================
echo  Instantale MOD : SD1.5 モードをインストール
echo ============================================
echo.

rem --- [1/3] プロキシ DLL (存在するすべてのバックエンドへ導入) ---
echo [1/3] プロキシ DLL
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

rem --- [2/3] TAESD デコーダ (SD1.5) ---
echo [2/3] TAESD デコーダ
if not exist "%TAESD%" (
    echo    [エラー] %TAESD% が見つかりません。ここはゲームフォルダですか?
    goto end
)
if exist "%S15%" (
    copy /b /y "%S15%" "%TAESD%" >nul
    echo    [ok]   SD1.5 用 TAESD を %S15% から復元しました
) else (
    echo    [ok]   SDXL のインストールは検出されませんでした - ゲーム標準の
    echo           SD1.5 用 TAESD がそのまま使われるため、変更は不要です。
    echo           ^(画像が壊れる/緑色になる場合は以前 SDXL に切り替えています:
    echo            SD1.5 用デコーダを再ダウンロードし、次の名前で保存してください
    echo            %TAESD%
    echo            https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors ^)
)
echo.

rem --- [3/3] sd_upscale.ini (SD1.5 プリセット) ---
echo [3/3] sd_upscale.ini
if exist "%INI%" (
    if exist sd_upscale.ini copy /y sd_upscale.ini sd_upscale.ini.bak >nul
    copy /y "%INI%" sd_upscale.ini >nul
    echo    [ok]   sd_upscale.ini を %INI% から読み込みました
) else (
    echo    [警告] %INI% が見つかりません - 現在の sd_upscale.ini を維持します。
    echo           [upscale] / [lora_map] が SD1.5 用の値になっているか確認してください。
)
echo.
echo 完了しました。ゲームを起動し、ゲーム内で SD1.5 のチェックポイントを選んでください。
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
