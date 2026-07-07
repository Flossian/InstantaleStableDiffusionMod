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
rem  SD1.5 モードでは何もダウンロードする必要はない。ゲームには
rem  SD1.5 モデルとその SD1.5 用 TAESD デコーダが最初から同梱されている。
rem ============================================================
setlocal
cd /d "%~dp0"

set LIBDLL=sdcpp_cuda\lib\stable-diffusion.dll
set REALDLL=stable-diffusion-real.dll
set PROXYSRC=mod_files\stable-diffusion-proxy.dll
set TAESD=runtime\models\sd15\taesd\diffusion_pytorch_model.safetensors
set S15=mod_files\taesd_sd15.safetensors
set INI=sd_upscale.sd15.ini

echo ============================================
echo  Instantale MOD : SD1.5 モードをインストール
echo ============================================
echo.

rem --- [1/3] プロキシ DLL ---
echo [1/3] プロキシ DLL
if not exist "%PROXYSRC%" (
    echo    [エラー] %PROXYSRC% が見つかりません。先に zip 全体を展開してください。
    goto end
)
if not exist "%LIBDLL%" (
    echo    [エラー] %LIBDLL% が見つかりません。ここはゲームフォルダですか?
    goto end
)
for %%F in ("%LIBDLL%") do set LIBSIZE=%%~zF
if %LIBSIZE% GTR 10000000 (
    if not exist "%REALDLL%" (
        echo    [ok]   元の DLL を %REALDLL% へ保存中 ... 少し時間がかかります
        copy /b /y "%LIBDLL%" "%REALDLL%" >nul
    ) else (
        echo    [ok]   %REALDLL% は既に存在します。そのまま使用します
    )
    copy /b /y "%PROXYSRC%" "%LIBDLL%" >nul
    echo    [ok]   プロキシを導入しました
) else (
    if not exist "%REALDLL%" (
        echo    [エラー] %LIBDLL% は既にプロキシですが %REALDLL% がありません。
        echo            元の 489MB の stable-diffusion.dll を
        echo            sdcpp_cuda\lib\ に戻してから再実行してください。
        goto end
    )
    copy /b /y "%PROXYSRC%" "%LIBDLL%" >nul
    echo    [ok]   プロキシを更新しました。元 DLL は %REALDLL% として保存済みです
)
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
