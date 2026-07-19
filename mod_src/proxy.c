/* Instantale 用プロキシ stable-diffusion.dll
 *
 * 1) 解像度: 要求された生成解像度をアスペクト比を保ったまま引き上げる。
 *    画像クラス別に enabled_<クラス>=0 で無効化でき、skip_if /
 *    skip_if_<クラス> の条件 (書式は [lora_add_if] の条件部と同じ) に
 *    ゲーム本来のプロンプトが一致した生成もスキップされる。
 *    img2img ではアプリが「元の」ターゲットサイズで確保した init_image と
 *    mask_image のバッファを渡してくるが、sd.cpp はそれらを(新しい)
 *    ターゲットサイズで読むため、両バッファをテンポラリへバイリニア拡大して
 *    構造体のポインタを差し替え、本物の関数を呼んだあと構造体を復元して
 *    テンポラリを解放する。
 *
 * 2) LoRA / プロンプト注入: 生成のたびにプロンプト文字列を書き換える:
 *      [prompt_remove]    ゲームのプロンプトから指定タグを除去 (カンマ区切り
 *                         1 区画単位・大文字小文字不問の完全一致)
 *      [negative_remove]  同上、ネガティブプロンプト版
 *      [prompt_replace]   画像クラスごとのプロンプト完全置換。値中の
 *                         "{prompt}" にゲーム本来のプロンプトが埋め込まれる
 *      [negative_replace] 同上、ネガティブプロンプト版
 *      [lora_map]      ゲームが要求する <lora:名前:重み> タグを別ファイルへ
 *                      付け替える ("off" / 空値 = タグ削除)
 *      [lora_add]      画像クラス (portrait/landscape/square) ごとに
 *                      プロンプト末尾へ追加するテキスト (lora タグ、品質タグ等)
 *      [negative_add]  同上、ネガティブプロンプトへ追加
 *      [lora_add_if]   条件付き追加。ルール = "クラス | 条件 | 追加内容"。
 *                      条件はゲーム本来のプロンプト (除去/置換前) に対する
 *                      単語境界つき・大文字小文字不問の含有判定。「/」区切りで
 *                      複数 (いずれか)、「!」前置で不含有条件 (すべて必須)
 *    1回の呼び出し内での順序: 除去 -> 置換 -> lora_map -> 追加。除去は元の
 *    プロンプトに対して行われるため、{prompt} に埋め込まれるのは除去済みの
 *    文字列。ゲームの lora タグも付け替え/削除の対象になる。
 *    プロンプトポインタのオフセット (0 / 8) は初回呼び出し時に
 *    sd_img_gen_params_to_str() と突き合わせて検証し、少しでも疑わしければ
 *    この機能は自己無効化して呼び出しを素通しする。
 *
 * 3) サンプラー上書き: [sampler] の ini キー (画像クラスごと) が、ゲームが
 *    ハードコードしているサンプリング方法 / steps / cfg / スケジューラを
 *    置き換える。背景を LCM の低 cfg による彩度抜けから救うために使う。
 *    書き込み前にフィールド値を妥当性チェックし、疑わしければ自己無効化する。
 *
 * 設定はすべて sd_upscale.ini で行い、generate_image のたびに読み直される
 * (ライブリロード、ゲーム再起動不要)。ini とログ (proxy_resize.log) の
 * 場所は固定:
 *   <ゲームルート>\InstantaleSDMod\
 * (ゲームルートはプロキシ自身のパス sdcpp_*\lib\ から逆算。GUI が導入時に
 *  このフォルダを作成して ini を生成する)。フォルダが無ければ従来どおり
 * ゲームの作業ディレクトリ直下を使う。
 *
 * 他のエクスポートはすべて .def のフォワーダ経由で本物の DLL
 * (stable-diffusion-real.dll) へ転送される。本物の DLL はプロキシ自身と
 * 同じフォルダ (sdcpp_cuda / sdcpp_cpu / sdcpp_vulkan の lib\) に置く。
 * DllMain でフルパス指定で先にロードしておくことで、フォワーダの
 * モジュール名解決 (ベース名一致) が正しいバックエンドの DLL に束縛される。
 * 同じフォルダに無い場合は従来どおりゲームルート直下の
 * stable-diffusion-real.dll へフォールバックする (v1 互換)。
 *
 * sd_img_gen_params_t のフィールドオフセット (同梱 DLL の
 * sd_img_gen_params_init/_to_str に対する probe2.exe のフリップテストで検証済):
 *   prompt     : char* @0      negative_prompt : char* @8
 *   init_image : width@24 height@28 channel@32 data@40(ポインタ)
 *   mask_image : width@64 height@68 channel@72 data@80(ポインタ)
 *   target     : width@88 height@92
 *   txt_cfg    : float @96    scheduler : int @144   sample_method : int @148
 *   steps      : int @152     eta       : float @156
 *   sample_method 列挙: 0=euler_a 1=euler 2=heun 3=dpm2 4=dpm++2s_a 5=dpm++2m
 *     6=dpm++2mv2 7=ipndm 8=ipndm_v 9=lcm 10=ddim_trailing 11=tcd
 *   scheduler 列挙: 0=default 1=discrete 2=karras 3=exponential 4=ays 5=gits
 *     6=smoothstep
 */
/* ======================= ファイル構成 (目次) =======================
 * 上から順に:
 *   1. 調整値・設定テーブル   ini から読み込むグローバル変数一式
 *   2. 文字列ユーティリティ   大文字小文字不問の比較・トリム等の小物
 *   3. 設定読み込み           load_config() = sd_upscale.ini のパース
 *   4. 本物 DLL のロード      load_real_beside_proxy() / ensure_real()
 *   5. 安全なメモリ検査       mem_readable() / str_readable() / prompt_ok()
 *   6. プロンプト書き換え     remove_tags() / rewrite_prompt() など
 *   7. 画像バッファ拡大       upscale() / fixup_image() (img2img 対応)
 *   8. メインフック           generate_image() ← 全体の流れはここを読む
 *   9. DllMain / 単体テスト
 * ==================================================================== */

#include <windows.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

/* ---- 調整値 (既定値。ゲームフォルダの sd_upscale.ini で上書きされる) ---- */
static int g_enabled    = 1;
static int g_goal_short = 832;   /* 縦長/正方形: 短辺をだいたいこの値まで引き上げる */
static int g_max_long   = 1216;  /* 縦長/正方形: 長辺がこの値を超えないようにする */
static int g_round      = 64;    /* 両辺をこの倍数に丸める */
/* 横長 (幅 > 高さ、背景など) 用の上書き。0 = 上の値を流用 */
static int g_goal_short_land = 768;
static int g_max_long_land   = 1344;
/* 画像クラス別の有効/無効 (ini の enabled_portrait / _landscape / _square)。
 * ini 読み込みのたびに 1 へ戻し、明示的に 0 が書かれたクラスだけ無効化する
 * (行を消せば = 有効に戻る)。全体の g_enabled が 0 なら全クラス無効 */
static int g_enabled_cls[3] = { 1, 1, 1 };
/* skip_if: ゲーム本来のプロンプトが条件を満たす生成はアップスケールしない。
 * 書式は [lora_add_if] の条件部と同じ (「/」区切りでいずれか、「!」で不含有)。
 * "" = 条件なし。skip_if は全クラス共通、skip_if_<クラス> はクラス別 */
static char g_skip_any[256];
static char g_skip_cls[3][256];
/* ----------------------------------------------------------------------------- */

/* sd_img_gen_params_t 内の各フィールドのバイトオフセット (冒頭コメントの
 * 検証済みレイアウト表に対応)。この構造体の定義はゲーム側にしか無いため、
 * 構造体をバイト列として扱い rd_i32/wr_i32 等で直接読み書きする */
#define OFF_PROMPT  0
#define OFF_NEG     8
#define OFF_CFG    96
#define OFF_SCHED 144
#define OFF_METHOD 148
#define OFF_STEPS 152
#define OFF_INIT_W 24
#define OFF_INIT_H 28
#define OFF_INIT_C 32
#define OFF_INIT_D 40
#define OFF_MASK_W 64
#define OFF_MASK_H 68
#define OFF_MASK_C 72
#define OFF_MASK_D 80
#define OFF_W      88
#define OFF_H      92

/* クラス別注入のための画像クラス */
#define CLS_PORTRAIT  0
#define CLS_LANDSCAPE 1
#define CLS_SQUARE    2
static const char* CLS_NAME[3] = { "portrait", "landscape", "square" };

/* lora / プロンプト注入設定 (ini 読み込みのたびにリセットして詰め直す) */
#define MAX_MAP 32
static struct { char from[96]; char to[192]; } g_map[MAX_MAP];
static int  g_map_n = 0;
static char g_add[3][512];
static char g_negadd[3][512];
static char g_repl[3][1024];     /* [prompt_replace]   "" = 置換しない */
static char g_negrepl[3][1024];  /* [negative_replace] "" = 置換しない */
static char g_rm[3][512];        /* [prompt_remove]    "" = 除去しない */
static char g_negrm[3][512];     /* [negative_remove]  "" = 除去しない */

/* [lora_add_if] の条件付き追加ルール (ini 読み込みのたびにリセット) */
#define MAX_RULES 16
static struct { int cls; char cond[192]; char add[384]; } g_rule[MAX_RULES];
static int g_rule_n = 0;         /* cls: 0-2 = クラス限定, -1 = any */

/* サンプラー上書き設定 (ini 読み込みのたびにリセットして詰め直す) */
static char  g_smp_method[3][24];  /* "" = 上書きしない */
static char  g_smp_sched[3][24];   /* "" = 上書きしない */
static int   g_smp_steps[3];       /* 0  = 上書きしない */
static float g_smp_cfg[3];         /* 0  = 上書きしない */
static int   g_smp_state = 0;      /* 0=未確認, 1=検証済, -1=異常 (機能停止) */

/* sample_method / scheduler の列挙値に対応する名前。ini の [sampler] で
 * 指定する文字列であり、配列の添字がそのまま列挙値になる */
static const char* METHOD_NAMES[] = { "euler_a", "euler", "heun", "dpm2", "dpm++2s_a",
    "dpm++2m", "dpm++2mv2", "ipndm", "ipndm_v", "lcm", "ddim_trailing", "tcd" };
static const char* SCHED_NAMES[] = { "default", "discrete", "karras", "exponential",
    "ays", "gits", "smoothstep" };

/* ---------------- 文字列ユーティリティ (前方宣言) ----------------
 * いずれも ASCII の大文字小文字を無視して比較する。プロンプトのタグ照合が
 * "Male" / "male" のような表記ゆれに左右されないようにするため */
static int ci_eq(const char* a, const char* b);
static int ci_eq_range(const char* a, const char* b, int n);
static void trim_range(const char* s, const char* e, const char** ps, const char** pe);

/* [s,e) を前後の空白抜きで dst へコピーする (NUL 終端、cap でクリップ) */
static void copy_trim(char* dst, size_t cap, const char* s, const char* e) {
    const char *ts, *te;
    trim_range(s, e, &ts, &te);
    size_t n = (size_t)(te - ts);
    if (n >= cap) n = cap - 1;
    memcpy(dst, ts, n);
    dst[n] = '\0';
}

static int name_to_enum(const char* name, const char** table, int n) {
    for (int i = 0; i < n; i++)
        if (ci_eq(name, table[i])) return i;
    return -1;
}

typedef void* (*gen_fn)(void*, void*);    /* generate_image と同じシグネチャ */
typedef char* (*to_str_fn)(const void*);  /* sd_img_gen_params_to_str と同じ */

static HMODULE   g_real = NULL;               /* 本物の stable-diffusion DLL */
static gen_fn    real_generate_image = NULL;  /* 本物の generate_image */
static to_str_fn real_params_to_str  = NULL;  /* レイアウト検証用 (prompt_ok が使う) */
static FILE*     g_log = NULL;                /* proxy_resize.log のハンドル */
static int       g_calls = 0;                 /* generate_image の呼び出し回数 */
static int       g_prompt_state = 0;  /* 0=未確認, 1=検証済, -1=異常 (機能停止) */

/* sd_upscale.ini / proxy_resize.log のフルパス。DllMain の init_mod_paths()
 * が <ゲームルート>\InstantaleSDMod を見つけたときだけ設定される。
 * "" のままなら従来どおりゲームの作業ディレクトリ直下を使う */
static char g_ini_path[1024];
static char g_log_path[1024];

/* パス末尾の 1 要素 (\xxx または /xxx) を切り落とす。成功なら 1 */
static int strip_last_component(char* s) {
    char* bs = strrchr(s, '\\');
    char* fs = strrchr(s, '/');
    char* slash = fs > bs ? fs : bs;
    if (!slash || slash == s) return 0;
    *slash = '\0';
    return 1;
}

/* 設定フォルダ (sd_upscale.ini の置き場所) を決める。場所は固定:
 * プロキシ自身 (sdcpp_*\lib\stable-diffusion.dll) の 2 つ上 = ゲームルート
 * にある InstantaleSDMod フォルダ。GUI が導入時にこのフォルダを作成して
 * ini を生成する。無ければ何もしない = ゲームの作業ディレクトリ直下
 * (フォルダを消した場合の最終フォールバック) */
static void init_mod_paths(HINSTANCE self) {
    char dir[1024];
    DWORD n = GetModuleFileNameA(self, dir, sizeof dir);
    if (n == 0 || n >= sizeof dir) return;
    /* dir = プロキシのあるフォルダ → 2 つ上がゲームルート */
    if (!strip_last_component(dir)) return;
    if (!strip_last_component(dir) || !strip_last_component(dir)) return;
    static const char MODDIR[] = "\\InstantaleSDMod";
    if (strlen(dir) + sizeof MODDIR >= sizeof dir) return;
    strcat(dir, MODDIR);
    DWORD attr = GetFileAttributesA(dir);
    if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY)) return;
    snprintf(g_ini_path, sizeof g_ini_path, "%s\\sd_upscale.ini", dir);
    snprintf(g_log_path, sizeof g_log_path, "%s\\proxy_resize.log", dir);
}

/* proxy_resize.log (設定フォルダ、無ければゲームの作業ディレクトリ) へ
 * 追記する。初回呼び出し時にオープンし、開けなければ黙って何もしない */
static void logf_(const char* fmt, ...) {
    if (!g_log) g_log = fopen(g_log_path[0] ? g_log_path : "proxy_resize.log", "a");
    if (!g_log) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(g_log, fmt, ap); va_end(ap);
    fflush(g_log);
}

/* v を g_round の倍数へ四捨五入で丸める (SD 系は 64 の倍数を要求するため)。
 * 最低でも 1 倍数分は確保する */
static int snap(int v) {
    int rnd = g_round >= 8 ? g_round : 8;
    int r = ((v + rnd / 2) / rnd) * rnd;
    if (r < rnd) r = rnd;
    return r;
}

/* 文字列全体の一致判定 (大文字小文字不問)。一致なら 1 */
static int ci_eq(const char* a, const char* b) {
    for (; *a && *b; a++, b++) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        if (ca != cb) return 0;
    }
    return *a == *b;
}

/* a の先頭 n 文字が文字列 b 全体と一致するか (大文字小文字不問)。
 * a は NUL 終端でなくてよい (プロンプト中の部分文字列を直接比較する用) */
static int ci_eq_n(const char* a, const char* b, int n) {
    /* a は比較対象がちょうど n 文字。b は NUL 終端文字列 */
    for (int i = 0; i < n; i++) {
        char ca = a[i], cb = b[i];
        if (!cb) return 0;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        if (ca != cb) return 0;
    }
    return b[n] == '\0';
}

/* s が pre で始まるか (大文字小文字不問)。始まっていれば 1 */
static int ci_starts(const char* s, const char* pre) {
    for (; *pre; s++, pre++) {
        char ca = *s, cb = *pre;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (ca != cb) return 0;
    }
    return 1;
}

/* 呼び出しごとに sd_upscale.ini を読み直し、ゲームを再起動せずに全設定を
 * 調整できるようにする。MOD フォルダの ini を優先し、無ければゲームの
 * 作業ディレクトリ直下 (v1.1 以前の配置) へフォールバック。ファイルが
 * 無い場合は数値は現状維持だが、注入テーブルは最後に成功した読み込みの
 * 内容が残る。 */
static void load_config(void) {
    FILE* f = g_ini_path[0] ? fopen(g_ini_path, "r") : NULL;
    if (!f) f = fopen("sd_upscale.ini", "r");
    if (!f) return;
    g_map_n = 0;
    memset(g_add, 0, sizeof g_add);
    memset(g_negadd, 0, sizeof g_negadd);
    memset(g_repl, 0, sizeof g_repl);
    memset(g_negrepl, 0, sizeof g_negrepl);
    memset(g_rm, 0, sizeof g_rm);
    memset(g_negrm, 0, sizeof g_negrm);
    g_rule_n = 0;
    memset(g_smp_method, 0, sizeof g_smp_method);
    memset(g_smp_sched, 0, sizeof g_smp_sched);
    memset(g_smp_steps, 0, sizeof g_smp_steps);
    memset(g_smp_cfg, 0, sizeof g_smp_cfg);
    g_enabled_cls[0] = g_enabled_cls[1] = g_enabled_cls[2] = 1;
    memset(g_skip_any, 0, sizeof g_skip_any);
    memset(g_skip_cls, 0, sizeof g_skip_cls);
    /* 以降は素朴な INI パーサ: 1 行ずつ読み、行頭空白を飛ばし、';' '#' 行は
     * コメントとして無視。"[名前]" で現在のセクションを切り替え、
     * "キー = 値" を切り出して前後の空白と改行を落としてから、
     * セクションごとの分岐で対応するテーブル / 変数に格納していく */
    char line[1024];
    char section[64] = "";
    while (fgets(line, sizeof line, f)) {
        char* p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == ';' || *p == '#' || *p == '\r' || *p == '\n' || *p == '\0') continue;
        if (*p == '[') {
            char* e = strchr(p, ']');
            if (e) {
                size_t n = (size_t)(e - (p + 1));
                if (n >= sizeof section) n = sizeof section - 1;
                memcpy(section, p + 1, n); section[n] = '\0';
            }
            continue;
        }
        char* eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char* key = p;
        char* val = eq + 1;
        char* ke = key + strlen(key);
        while (ke > key && (ke[-1] == ' ' || ke[-1] == '\t')) *--ke = '\0';
        while (*val == ' ' || *val == '\t') val++;
        char* ve = val + strlen(val);
        while (ve > val && (ve[-1] == '\n' || ve[-1] == '\r' || ve[-1] == ' ' || ve[-1] == '\t')) *--ve = '\0';

        if (ci_eq(section, "lora_map")) {
            if (key[0] && g_map_n < MAX_MAP) {
                snprintf(g_map[g_map_n].from, sizeof g_map[0].from, "%s", key);
                snprintf(g_map[g_map_n].to,   sizeof g_map[0].to,   "%s", val);
                g_map_n++;
            }
            continue;
        }
        if (ci_eq(section, "lora_add") || ci_eq(section, "negative_add")) {
            char (*dst)[512] = ci_eq(section, "lora_add") ? g_add : g_negadd;
            int c = ci_eq(key, "portrait") ? CLS_PORTRAIT
                  : ci_eq(key, "landscape") ? CLS_LANDSCAPE
                  : ci_eq(key, "square") ? CLS_SQUARE : -1;
            if (c >= 0) snprintf(dst[c], sizeof dst[0], "%s", val);
            continue;
        }
        if (ci_eq(section, "prompt_replace") || ci_eq(section, "negative_replace")) {
            char (*dst)[1024] = ci_eq(section, "prompt_replace") ? g_repl : g_negrepl;
            int c = ci_eq(key, "portrait") ? CLS_PORTRAIT
                  : ci_eq(key, "landscape") ? CLS_LANDSCAPE
                  : ci_eq(key, "square") ? CLS_SQUARE : -1;
            if (c >= 0) snprintf(dst[c], sizeof dst[0], "%s", val);
            continue;
        }
        if (ci_eq(section, "prompt_remove") || ci_eq(section, "negative_remove")) {
            char (*dst)[512] = ci_eq(section, "prompt_remove") ? g_rm : g_negrm;
            int c = ci_eq(key, "portrait") ? CLS_PORTRAIT
                  : ci_eq(key, "landscape") ? CLS_LANDSCAPE
                  : ci_eq(key, "square") ? CLS_SQUARE : -1;
            if (c >= 0) snprintf(dst[c], sizeof dst[0], "%s", val);
            continue;
        }
        if (ci_eq(section, "lora_add_if")) {
            /* 値の書式: クラス | 条件 | 追加内容 (キー名は任意のルール名) */
            if (!key[0] || g_rule_n >= MAX_RULES) continue;
            char* p1 = strchr(val, '|');
            char* p2 = p1 ? strchr(p1 + 1, '|') : NULL;
            if (!p2) continue;
            char clsbuf[24];
            copy_trim(clsbuf, sizeof clsbuf, val, p1);
            int c = ci_eq(clsbuf, "portrait") ? CLS_PORTRAIT
                  : ci_eq(clsbuf, "landscape") ? CLS_LANDSCAPE
                  : ci_eq(clsbuf, "square") ? CLS_SQUARE
                  : ci_eq(clsbuf, "any") ? -1 : -2;
            if (c == -2) continue;
            g_rule[g_rule_n].cls = c;
            copy_trim(g_rule[g_rule_n].cond, sizeof g_rule[0].cond, p1 + 1, p2);
            copy_trim(g_rule[g_rule_n].add,  sizeof g_rule[0].add,  p2 + 1, p2 + 1 + strlen(p2 + 1));
            if (g_rule[g_rule_n].cond[0] && g_rule[g_rule_n].add[0]) g_rule_n++;
            continue;
        }
        if (ci_eq(section, "sampler")) {
            /* キーは <クラス>_<フィールド>。例: landscape_method = euler_a */
            char* us = strchr(key, '_');
            if (!us) continue;
            *us = '\0';
            const char* field = us + 1;
            int c = ci_eq(key, "portrait") ? CLS_PORTRAIT
                  : ci_eq(key, "landscape") ? CLS_LANDSCAPE
                  : ci_eq(key, "square") ? CLS_SQUARE : -1;
            if (c < 0) continue;
            if      (ci_eq(field, "method"))    snprintf(g_smp_method[c], sizeof g_smp_method[0], "%s", val);
            else if (ci_eq(field, "scheduler")) snprintf(g_smp_sched[c],  sizeof g_smp_sched[0],  "%s", val);
            else if (ci_eq(field, "steps")) { int v2 = atoi(val); if (v2 >= 1 && v2 <= 200) g_smp_steps[c] = v2; }
            else if (ci_eq(field, "cfg"))   { float f = (float)atof(val); if (f > 0.0f && f <= 50.0f) g_smp_cfg[c] = f; }
            continue;
        }

        /* skip_if 系は値が文字列 (条件式) なので数値パースの前に処理する */
        if (ci_eq(key, "skip_if"))           { snprintf(g_skip_any, sizeof g_skip_any, "%s", val); continue; }
        if (ci_eq(key, "skip_if_portrait"))  { snprintf(g_skip_cls[CLS_PORTRAIT],  sizeof g_skip_cls[0], "%s", val); continue; }
        if (ci_eq(key, "skip_if_landscape")) { snprintf(g_skip_cls[CLS_LANDSCAPE], sizeof g_skip_cls[0], "%s", val); continue; }
        if (ci_eq(key, "skip_if_square"))    { snprintf(g_skip_cls[CLS_SQUARE],    sizeof g_skip_cls[0], "%s", val); continue; }

        int v = atoi(val);
        if      (ci_eq(key, "enabled"))    g_enabled = v;
        else if (ci_eq(key, "enabled_portrait"))  g_enabled_cls[CLS_PORTRAIT]  = v;
        else if (ci_eq(key, "enabled_landscape")) g_enabled_cls[CLS_LANDSCAPE] = v;
        else if (ci_eq(key, "enabled_square"))    g_enabled_cls[CLS_SQUARE]    = v;
        else if (ci_eq(key, "goal_short") && v >= 64 && v <= 4096) g_goal_short = v;
        else if (ci_eq(key, "max_long")   && v >= 64 && v <= 8192) g_max_long   = v;
        else if (ci_eq(key, "round")      && v >= 8  && v <= 256)  g_round      = v;
        else if (ci_eq(key, "goal_short_landscape") && v >= 0 && v <= 4096) g_goal_short_land = v;
        else if (ci_eq(key, "max_long_landscape")   && v >= 0 && v <= 8192) g_max_long_land   = v;
    }
    fclose(f);
}

/* プロキシ自身と同じフォルダにある本物 DLL のフルパス ("" = 無し) */
static char g_realpath[1024];

/* プロキシのロード時に、同じフォルダの stable-diffusion-real.dll を
 * フルパスでロードしておく。バックエンド (cuda / cpu / vulkan) ごとに
 * オリジナル DLL が異なるため、.def のフォワーダがベース名
 * "stable-diffusion-real" を解決する際に、既にロード済みのこのモジュール
 * (= 正しいバックエンドのもの) へ束縛されるようにするのが目的。
 * LOAD_WITH_ALTERED_SEARCH_PATH により依存 DLL (cublas 等) も同じ lib\
 * フォルダから解決される。ファイルが無ければ何もしない: フォワーダと
 * ensure_real は従来どおりゲームルートの同名 DLL へフォールバックする。 */
static void load_real_beside_proxy(HINSTANCE self) {
    DWORD n = GetModuleFileNameA(self, g_realpath, sizeof g_realpath);
    if (n == 0 || n >= sizeof g_realpath) { g_realpath[0] = '\0'; return; }
    char* bs = strrchr(g_realpath, '\\');
    char* fs = strrchr(g_realpath, '/');
    char* slash = fs > bs ? fs : bs;
    if (!slash) { g_realpath[0] = '\0'; return; }
    static const char NAME[] = "stable-diffusion-real.dll";
    size_t dir = (size_t)(slash + 1 - g_realpath);
    if (dir + sizeof NAME > sizeof g_realpath) { g_realpath[0] = '\0'; return; }
    memcpy(g_realpath + dir, NAME, sizeof NAME);
    if (GetFileAttributesA(g_realpath) == INVALID_FILE_ATTRIBUTES) {
        g_realpath[0] = '\0';
        return;
    }
    g_real = LoadLibraryExA(g_realpath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
}

/* 本物 DLL のハンドルとフックに必要な関数ポインタを (初回のみ) 解決する。
 * 探す順序:
 *   (1) ロード済みモジュール (通常は DllMain が先行ロードしたもの)
 *   (2) プロキシと同じフォルダの stable-diffusion-real.dll (g_realpath)
 *   (3) 通常の DLL 検索順 = ゲームルート直下 (v1 の旧配置)
 * 失敗しても致命的にはせず、generate_image 側が素通し動作になる */
static void ensure_real(void) {
    if (real_generate_image) return;
    if (!g_real) g_real = GetModuleHandleA("stable-diffusion-real.dll");
    if (!g_real && g_realpath[0])
        g_real = LoadLibraryExA(g_realpath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!g_real) g_real = LoadLibraryA("stable-diffusion-real.dll");
    if (g_real) {
        real_generate_image = (gen_fn)GetProcAddress(g_real, "generate_image");
        real_params_to_str  = (to_str_fn)GetProcAddress(g_real, "sd_img_gen_params_to_str");
        char path[1024];
        if (GetModuleFileNameA(g_real, path, sizeof path))
            logf_("real dll: %s\n", path);
    }
}

/* 構造体 (バイト列 p) の任意オフセットから int / ポインタを読み書きする
 * ヘルパ。memcpy 経由にすることでアラインメントを気にせず安全に扱える */
static int rd_i32(unsigned char* p, int off) { int v; memcpy(&v, p + off, 4); return v; }
static void wr_i32(unsigned char* p, int off, int v) { memcpy(p + off, &v, 4); }
static void* rd_ptr(unsigned char* p, int off) { void* v; memcpy(&v, p + off, sizeof v); return v; }
static void wr_ptr(unsigned char* p, int off, void* v) { memcpy(p + off, &v, sizeof v); }

/* -------- 安全なメモリ検査 (zig cc では SEH が使えないため) --------
 * 構造体レイアウトの想定が外れているとポインタの読み取りでクラッシュする。
 * 例外ハンドラの代わりに VirtualQuery でページ属性を確認してから読む */

/* [p, p+n) の全域が読み取り可能なコミット済みページに載っているか */
static int mem_readable(const void* p, size_t n) {
    MEMORY_BASIC_INFORMATION mbi;
    const unsigned char* q = (const unsigned char*)p;
    size_t left = n;
    while (left) {
        if (!VirtualQuery(q, &mbi, sizeof mbi)) return 0;
        if (mbi.State != MEM_COMMIT) return 0;
        if (mbi.Protect & PAGE_GUARD) return 0;
        DWORD pr = mbi.Protect & 0xFF;
        if (!(pr == PAGE_READONLY || pr == PAGE_READWRITE || pr == PAGE_WRITECOPY ||
              pr == PAGE_EXECUTE_READ || pr == PAGE_EXECUTE_READWRITE || pr == PAGE_EXECUTE_WRITECOPY))
            return 0;
        size_t avail = (size_t)((const unsigned char*)mbi.BaseAddress + mbi.RegionSize - q);
        if (avail >= left) return 1;
        q += avail; left -= avail;
    }
    return 1;
}

/* NUL 終端文字列が読み取り可能メモリに完全に収まっているか?
 * ページ単位で少しずつ確認しながら歩く。 */
static int str_readable(const char* s, int maxn, int* out_len) {
    uintptr_t a = (uintptr_t)s;
    int i = 0;
    while (i < maxn) {
        size_t to_page = 4096 - ((a + (size_t)i) & 4095);
        size_t chunk = to_page;
        if ((int)chunk > maxn - i) chunk = (size_t)(maxn - i);
        if (!mem_readable(s + i, chunk)) return 0;
        for (size_t k = 0; k < chunk; k++, i++)
            if (s[i] == '\0') { if (out_len) *out_len = i; return 1; }
    }
    return 0;
}

/* オフセット 0 が本当にプロンプトポインタであることを (一度だけ) 検証する。
 * 疑わしければプロセスの残りの間は注入を無効化して素通しする。 */
static int prompt_ok(unsigned char* p) {
    if (g_prompt_state) return g_prompt_state > 0;
    const char* pr = (const char*)rd_ptr(p, OFF_PROMPT);
    if (!pr) return 0;  /* この呼び出しでは判定できない。次回に再挑戦 */
    int len = 0;
    if (!str_readable(pr, 65536, &len)) {
        g_prompt_state = -1;
        logf_("lora: pointer @0 is not a readable string, injection disabled\n");
        return 0;
    }
    for (int i = 0; i < len && i < 64; i++) {
        unsigned char c = (unsigned char)pr[i];
        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') {
            g_prompt_state = -1;
            logf_("lora: pointer @0 is not text, injection disabled\n");
            return 0;
        }
    }
    if (real_params_to_str && len >= 8) {
        char* s = real_params_to_str(p);
        if (s) {
            char frag[33];
            int fl = len < 32 ? len : 32;
            memcpy(frag, pr, (size_t)fl); frag[fl] = '\0';
            int hit = strstr(s, frag) != NULL;
            /* s は本物 DLL 側の CRT が確保したもの。意図的に一度だけリークさせる */
            if (!hit) {
                g_prompt_state = -1;
                logf_("lora: to_str cross-check failed, injection disabled\n");
                return 0;
            }
        }
    }
    g_prompt_state = 1;
    logf_("lora: prompt offset verified, injection active\n");
    return 1;
}

/* ---------------- プロンプト書き換え ---------------- */

/* プロンプト書き換え系の設定が ini に 1 つでも存在するか。
 * 無ければ書き換え処理 (とプロンプトの検証) を丸ごとスキップできる */
static int lora_active(void) {
    if (g_map_n > 0 || g_rule_n > 0) return 1;
    for (int i = 0; i < 3; i++)
        if (g_add[i][0] || g_negadd[i][0] || g_repl[i][0] || g_negrepl[i][0] ||
            g_rm[i][0] || g_negrm[i][0]) return 1;
    return 0;
}

/* 英数字か (単語境界の判定に使う) */
static int is_alnum_c(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

/* needle が hay に単語境界つき・大文字小文字不問で含まれるか。
 * 境界判定のおかげで "male" は "female" に、"man" は "woman" にマッチしない */
static int ci_word_in(const char* hay, const char* nd) {
    size_t nl = strlen(nd), hl = strlen(hay);
    if (!nl || hl < nl) return 0;
    for (size_t i = 0; i + nl <= hl; i++) {
        if (!ci_eq_range(hay + i, nd, (int)nl)) continue;
        if (i > 0 && is_alnum_c(hay[i - 1]) && is_alnum_c(nd[0])) continue;
        if (is_alnum_c(hay[i + nl]) && is_alnum_c(nd[nl - 1])) continue;
        return 1;
    }
    return 0;
}

/* [lora_add_if] の条件 ("kw1/kw2/!kw3") をプロンプトに対して評価する。
 * ! なしの語はどれか 1 つ含まれれば成立 (1 つも書かなければ常に成立)、
 * ! つきの語はすべて「含まれない」必要がある。 */
static int rule_match(const char* prompt, const char* cond) {
    int pos_n = 0, pos_hit = 0;
    const char* q = cond;
    while (*q) {
        const char* c = strchr(q, '/');
        const char* e = c ? c : q + strlen(q);
        char kw[128];
        copy_trim(kw, sizeof kw, q, e);
        if (kw[0] == '!') {
            if (kw[1] && ci_word_in(prompt, kw + 1)) return 0;
        } else if (kw[0]) {
            pos_n++;
            if (ci_word_in(prompt, kw)) pos_hit = 1;
        }
        q = c ? c + 1 : e;
    }
    return pos_n == 0 || pos_hit;
}

/* [upscale] の skip_if / skip_if_<クラス> を評価する。prompt はゲーム本来の
 * プロンプト (除去・置換前)。どちらかの条件が成立すれば 1 (= スキップ) */
static int upscale_skip_match(const char* prompt, int cls) {
    if (g_skip_any[0] && rule_match(prompt, g_skip_any)) return 1;
    if (g_skip_cls[cls][0] && rule_match(prompt, g_skip_cls[cls])) return 1;
    return 0;
}

/* [s,e) の前後の空白を除いた範囲を返す */
static void trim_range(const char* s, const char* e, const char** ps, const char** pe) {
    while (s < e && (*s == ' ' || *s == '\t')) s++;
    while (e > s && (e[-1] == ' ' || e[-1] == '\t')) e--;
    *ps = s; *pe = e;
}

static int ci_eq_range(const char* a, const char* b, int n) {
    for (int i = 0; i < n; i++) {
        char ca = a[i], cb = b[i];
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        if (ca != cb) return 0;
    }
    return 1;
}

/* len 文字のタグ s が、カンマ区切りリスト list に含まれるか (大文字小文字不問) */
static int tag_in_list(const char* s, int len, const char* list) {
    const char* q = list;
    while (*q) {
        const char* c = strchr(q, ',');
        const char* e = c ? c : q + strlen(q);
        const char *ts, *te;
        trim_range(q, e, &ts, &te);
        if ((int)(te - ts) == len && len > 0 && ci_eq_range(s, ts, len)) return 1;
        q = c ? c + 1 : e;
    }
    return 0;
}

/* src (カンマ区切りのタグ列) から、list に載っているタグを丸ごと取り除く。
 * カンマ区切りの 1 区画単位・大文字小文字不問の完全一致で判定する
 * (部分一致では消えない)。残った区画は ", " で繋ぎ直す。
 * malloc した文字列を返す。何も消えなければ NULL。 */
static char* remove_tags(const char* src, const char* list) {
    if (!list[0]) return NULL;
    size_t slen = strlen(src);
    size_t segs = 1;
    for (const char* t = src; *t; t++) if (*t == ',') segs++;
    char* out = (char*)malloc(slen + segs * 2 + 1);
    if (!out) return NULL;
    size_t o = 0;
    int removed = 0, wrote = 0;
    const char* q = src;
    while (*q) {
        const char* c = strchr(q, ',');
        const char* e = c ? c : q + strlen(q);
        const char *ts, *te;
        trim_range(q, e, &ts, &te);
        if (te > ts && tag_in_list(ts, (int)(te - ts), list)) {
            removed = 1;
        } else if (te > ts) {
            if (wrote) { out[o++] = ','; out[o++] = ' '; }
            memcpy(out + o, ts, (size_t)(te - ts));
            o += (size_t)(te - ts);
            wrote = 1;
        }
        q = c ? c + 1 : e;
    }
    out[o] = '\0';
    if (!removed) { free(out); return NULL; }
    return out;
}

/* tmpl 中のすべての "{prompt}" (大文字小文字不問) を orig に展開する。
 * malloc した文字列を返す。 */
static char* apply_template(const char* tmpl, const char* orig) {
    size_t ol = strlen(orig);
    size_t count = 0, tl = 0;
    for (const char* q = tmpl; *q; )
        if (ci_starts(q, "{prompt}")) { count++; q += 8; tl += 8; }
        else { q++; tl++; }
    char* out = (char*)malloc(tl + count * ol + 1);
    if (!out) return NULL;
    size_t o = 0;
    for (const char* q = tmpl; *q; ) {
        if (ci_starts(q, "{prompt}")) {
            memcpy(out + o, orig, ol); o += ol; q += 8;
        } else out[o++] = *q++;
    }
    out[o] = '\0';
    return out;
}

static const char* map_lookup(const char* name, int name_len) {
    for (int i = 0; i < g_map_n; i++)
        if (ci_eq_n(name, g_map[i].from, name_len)) return g_map[i].to;
    return NULL;
}

/* まず [prompt_remove] のタグを除去し、次に [prompt_replace] があれば
 * プロンプト全体を置換 ({prompt} = 除去済みの元プロンプト)、続いて
 * <lora:...> タグを [lora_map] で書き換え、そのクラスの [lora_add] テキストと
 * [lora_add_if] の成立ルールを追記する。ルールの条件判定は除去・置換前の
 * ゲーム本来のプロンプト (orig) に対して行う。malloc した文字列を返す。
 * 何も変わらなければ NULL。 */
static char* rewrite_prompt(const char* src, int cls) {
    const char* orig = src;
    char* rm = NULL;
    if (g_rm[cls][0]) {
        rm = remove_tags(src, g_rm[cls]);
        if (rm) src = rm;
    }
    char* base = NULL;
    if (g_repl[cls][0]) {
        base = apply_template(g_repl[cls], src);
        if (base) src = base;
    }
    const char* add = g_add[cls];
    size_t slen = strlen(src);
    /* 伸び代は「マップ表の行数」ではなく「プロンプト中のタグ出現数」ぶん
     * 必要になる (同じタグが繰り返されても各出現が置換される)。置換は必ず
     * '<' を起点とするため、'<' の数 >= 置換されうるタグ数。1 出現あたりの
     * 増加は最大でも sizeof to + 16 ("<lora:" + to + 重み + ">") に収まる */
    size_t ntag = 0;
    for (const char* t = src; *t; t++) if (*t == '<') ntag++;
    size_t cap = slen + strlen(add) + 16 + (ntag + 1) * (sizeof g_map[0].to + 16)
               + (size_t)MAX_RULES * (sizeof g_rule[0].add + 2);
    char* out = (char*)malloc(cap);
    if (!out) { free(base); free(rm); return NULL; }
    size_t o = 0;
    int changed = base != NULL || rm != NULL;
    const char* q = src;
    while (*q) {
        if (*q == '<' && ci_starts(q + 1, "lora:")) {
            const char* close = strchr(q, '>');
            if (!close) { out[o++] = *q++; continue; }
            const char* inner = q + 6;                     /* "<lora:" の直後 */
            const char* colon = (const char*)memchr(inner, ':', (size_t)(close - inner));
            int name_len = (int)((colon ? colon : close) - inner);
            const char* to = map_lookup(inner, name_len);
            if (!to) {  /* マップに無い: そのままコピー */
                memcpy(out + o, q, (size_t)(close + 1 - q));
                o += (size_t)(close + 1 - q);
                q = close + 1;
                continue;
            }
            changed = 1;
            if (!*to || ci_eq(to, "off")) {
                /* タグと直後の区切りを 1 つ落とし ",," にならないようにする */
                q = close + 1;
                while (*q == ' ') q++;
                if (*q == ',') { q++; while (*q == ' ') q++; }
                continue;
            }
            if (strchr(to, ':'))          /* マップ値が自前の重みを持つ */
                o += (size_t)sprintf(out + o, "<lora:%s>", to);
            else if (colon)               /* 元の重みを維持する */
                o += (size_t)sprintf(out + o, "<lora:%s%.*s>", to, (int)(close - colon), colon);
            else
                o += (size_t)sprintf(out + o, "<lora:%s>", to);
            q = close + 1;
            continue;
        }
        out[o++] = *q++;
    }
    if (add[0]) {
        changed = 1;
        if (o > 0) { out[o++] = ','; out[o++] = ' '; }
        memcpy(out + o, add, strlen(add));
        o += strlen(add);
    }
    for (int i = 0; i < g_rule_n; i++) {
        if (g_rule[i].cls >= 0 && g_rule[i].cls != cls) continue;
        if (!rule_match(orig, g_rule[i].cond)) continue;
        changed = 1;
        if (o > 0) { out[o++] = ','; out[o++] = ' '; }
        size_t al = strlen(g_rule[i].add);
        memcpy(out + o, g_rule[i].add, al);
        o += al;
    }
    out[o] = '\0';
    free(base);
    free(rm);
    if (!changed) { free(out); return NULL; }
    return out;
}

static char* append_text(const char* src, const char* add) {
    if (!add[0]) return NULL;
    size_t sl = strlen(src), al = strlen(add);
    char* out = (char*)malloc(sl + al + 4);
    if (!out) return NULL;
    if (sl) sprintf(out, "%s, %s", src, add);
    else    memcpy(out, add, al + 1);
    return out;
}

/* ネガティブプロンプト: [negative_remove] のタグを除去し、[negative_replace]
 * のテンプレートがあれば置換し、その後 [negative_add] を追記する。
 * malloc した文字列を返す。何も変わらなければ NULL。 */
static char* rewrite_negative(const char* src, int cls) {
    char* rm = NULL;
    if (g_negrm[cls][0]) {
        rm = remove_tags(src, g_negrm[cls]);
        if (rm) src = rm;
    }
    char* base = NULL;
    if (g_negrepl[cls][0]) {
        base = apply_template(g_negrepl[cls], src);
        if (base) src = base;
    }
    char* out = append_text(src, g_negadd[cls]);
    if (out) { free(base); free(rm); return out; }
    if (base) { free(rm); return base; }
    return rm;
}

/* ---------------- 画像バッファ拡大 (img2img の補正) ---------------- */

/* バイリニア拡大。チャンネルはインターリーブ、8bit */
static unsigned char* upscale(const unsigned char* src, int sw, int sh, int ch, int dw, int dh) {
    unsigned char* dst = (unsigned char*)malloc((size_t)dw * dh * ch);
    if (!dst) return NULL;
    for (int y = 0; y < dh; y++) {
        float fy = (sh > 1) ? (float)y * (sh - 1) / (dh - 1) : 0.0f;
        int y0 = (int)fy; int y1 = (y0 + 1 < sh) ? y0 + 1 : y0; float wy = fy - y0;
        for (int x = 0; x < dw; x++) {
            float fx = (sw > 1) ? (float)x * (sw - 1) / (dw - 1) : 0.0f;
            int x0 = (int)fx; int x1 = (x0 + 1 < sw) ? x0 + 1 : x0; float wx = fx - x0;
            const unsigned char* r0 = src + ((size_t)y0 * sw) * ch;
            const unsigned char* r1 = src + ((size_t)y1 * sw) * ch;
            unsigned char* d = dst + ((size_t)y * dw + x) * ch;
            for (int c = 0; c < ch; c++) {
                float p00 = r0[x0 * ch + c], p01 = r0[x1 * ch + c];
                float p10 = r1[x0 * ch + c], p11 = r1[x1 * ch + c];
                float v = p00 * (1 - wx) * (1 - wy) + p01 * wx * (1 - wy)
                        + p10 * (1 - wx) * wy       + p11 * wx * wy;
                int iv = (int)(v + 0.5f);
                d[c] = (unsigned char)(iv < 0 ? 0 : iv > 255 ? 255 : iv);
            }
        }
    }
    return dst;
}

/* (w_off,h_off,c_off,d_off) にある sd_image_t にバッファがあれば (nW,nH) へ
 * 拡大して構造体を差し替え、テンポラリバッファを返す (呼び出し側が解放と
 * 保存済みフィールドの復元を行うこと)。何もしなかった場合は NULL。 */
static unsigned char* fixup_image(unsigned char* p, int w_off, int h_off, int c_off, int d_off,
                                  int nW, int nH,
                                  int* sw, int* sh, int* sc, void** sd) {
    *sw = rd_i32(p, w_off); *sh = rd_i32(p, h_off); *sc = rd_i32(p, c_off); *sd = rd_ptr(p, d_off);
    if (!*sd) return NULL;
    if (*sw < 8 || *sw > 8192 || *sh < 8 || *sh > 8192 || *sc < 1 || *sc > 4) return NULL;
    if (*sw == nW && *sh == nH) return NULL;
    unsigned char* nb = upscale((const unsigned char*)*sd, *sw, *sh, *sc, nW, nH);
    if (!nb) return NULL;
    wr_i32(p, w_off, nW); wr_i32(p, h_off, nH); wr_ptr(p, d_off, nb);
    return nb;
}

/* ---------------- メインフック ---------------- */

/* ゲームが呼ぶ generate_image の差し替え実体。処理の流れ:
 *   (1) sd_upscale.ini を読み直す (ホットリロード。ゲーム再起動不要)
 *   (2) 要求サイズから画像クラス (縦長 / 横長 / 正方形) を判定
 *   (3) skip_if の判定 (書き換え前の、ゲーム本来のプロンプトで評価)
 *   (4) プロンプト / ネガティブプロンプトの書き換え (ポインタ差し替え)
 *   (5) サンプラー上書き (method / steps / cfg / scheduler)
 *   (6) 解像度アップスケール (img2img の init/mask バッファも拡大)
 *   (7) 本物の generate_image を呼ぶ
 *   (8) 構造体を呼び出し前の状態へ完全に復元し、確保したメモリを解放
 * params は sd_img_gen_params_t (フィールドオフセットは冒頭コメント参照)。
 * アプリが同じ構造体を使い回しても壊れないよう、(8) の復元が重要 */
__declspec(dllexport) void* generate_image(void* ctx, void* params) {
    ensure_real();
    g_calls++;
    /* 本物が見つからない / params が NULL なら、何もせずできる範囲で素通し */
    if (!real_generate_image || !params) return real_generate_image ? real_generate_image(ctx, params) : NULL;

    load_config();   /* (1) 生成のたびに ini を読み直す */

    /* (2) 構造体はバイト列 p として OFF_* オフセットで直接読み書きする */
    unsigned char* p = (unsigned char*)params;
    int W = rd_i32(p, OFF_W), H = rd_i32(p, OFF_H);   /* ゲームが要求したサイズ */
    /* サイズが常識の範囲外ならレイアウトの想定が崩れている。触らず素通し */
    if (W < 64 || W > 8192 || H < 64 || H > 8192) return real_generate_image(ctx, params);
    int cls = (W > H) ? CLS_LANDSCAPE : (W < H ? CLS_PORTRAIT : CLS_SQUARE);

    /* ---- (3) アップスケールのスキップ判定 ----
     * プロンプト書き換えでポインタが差し替わる前に、ゲーム本来のプロンプトに
     * 対して skip_if を評価しておく。プロンプトが検証できない場合 (prompt_ok
     * が偽) は判定できないため、スキップせず通常どおり動作する */
    int up_on = g_enabled && g_enabled_cls[cls];   /* このクラスで拡大有効か */
    int up_skip = 0;                               /* skip_if に一致したか */
    if (up_on && (g_skip_any[0] || g_skip_cls[cls][0]) && prompt_ok(p)) {
        const char* pr = (const char*)rd_ptr(p, OFF_PROMPT);
        if (pr && upscale_skip_match(pr, cls)) up_skip = 1;
    }

    /* ---- (4) LoRA / プロンプト注入 ----
     * new_* = malloc した書き換え後の文字列 (NULL = 書き換え不要だった)
     * old_* = アプリが渡してきた元のポインタ (呼び出し後に戻すため保存) */
    char *new_prompt = NULL, *new_neg = NULL;
    void *old_prompt = NULL, *old_neg = NULL;
    if (lora_active() && prompt_ok(p)) {
        old_prompt = rd_ptr(p, OFF_PROMPT);
        if (old_prompt) {
            new_prompt = rewrite_prompt((const char*)old_prompt, cls);
            if (new_prompt) wr_ptr(p, OFF_PROMPT, new_prompt);
        }
        /* ネガティブ側は設定がある場合のみ。ポインタの読み取り可能性も
         * (プロンプト側と違い未検証のため) ここで個別に確認する */
        old_neg = rd_ptr(p, OFF_NEG);
        if (old_neg && (g_negadd[cls][0] || g_negrepl[cls][0] || g_negrm[cls][0])) {
            int nlen;
            if (str_readable((const char*)old_neg, 65536, &nlen)) {
                new_neg = rewrite_negative((const char*)old_neg, cls);
                if (new_neg) wr_ptr(p, OFF_NEG, new_neg);
            }
        }
        /* 書き換え結果は最初の数回だけログに残す (動作確認用) */
        if ((new_prompt || new_neg) && g_calls <= 8) {
            if (new_prompt) logf_("call %d: [%s] prompt rewritten: %.300s%s\n",
                          g_calls, CLS_NAME[cls], new_prompt, strlen(new_prompt) > 300 ? "..." : "");
            if (new_neg) logf_("call %d: [%s] negative rewritten: %.200s%s\n",
                          g_calls, CLS_NAME[cls], new_neg, strlen(new_neg) > 200 ? "..." : "");
        }
    }

    /* ---- (5) サンプラー上書き ----
     * saved_* は復元用に取っておく呼び出し前の値。初回は現在のフィールド値が
     * 列挙値・妥当な範囲に収まっているかを確認し (レイアウト検証を兼ねる)、
     * 疑わしければ g_smp_state = -1 にしてこの機能だけ以後停止する */
    int   saved_method = 0, saved_sched = 0, saved_steps = 0;
    float saved_cfg = 0.0f;
    int   smp_applied = 0;   /* 実際に書き換えたか (= 復元が必要か) */
    if (g_smp_state >= 0 &&
        (g_smp_method[cls][0] || g_smp_sched[cls][0] || g_smp_steps[cls] || g_smp_cfg[cls] > 0.0f)) {
        int cur_method = rd_i32(p, OFF_METHOD), cur_steps = rd_i32(p, OFF_STEPS), cur_sched = rd_i32(p, OFF_SCHED);
        float cur_cfg; memcpy(&cur_cfg, p + OFF_CFG, 4);
        if (cur_method < 0 || cur_method > 11 || cur_steps < 1 || cur_steps > 500 ||
            cur_sched < 0 || cur_sched > 6 || !(cur_cfg >= 0.0f && cur_cfg <= 50.0f)) {
            if (g_smp_state == 0)
                logf_("sampler: layout sanity check failed (m=%d s=%d sc=%d cfg=%.2f), override disabled\n",
                      cur_method, cur_steps, cur_sched, cur_cfg);
            g_smp_state = -1;
        } else {
            g_smp_state = 1;
            saved_method = cur_method; saved_steps = cur_steps; saved_sched = cur_sched; saved_cfg = cur_cfg;
            /* ini に書かれている項目だけ差し替える (未記入はゲームの値のまま) */
            int new_method = cur_method, new_sched = cur_sched, new_steps = cur_steps;
            float new_cfg = cur_cfg;
            if (g_smp_method[cls][0]) {
                int e = name_to_enum(g_smp_method[cls], METHOD_NAMES, 12);
                if (e >= 0) new_method = e;
                else if (g_calls <= 8) logf_("sampler: unknown method '%s' ignored\n", g_smp_method[cls]);
            }
            if (g_smp_sched[cls][0]) {
                int e = name_to_enum(g_smp_sched[cls], SCHED_NAMES, 7);
                if (e >= 0) new_sched = e;
                else if (g_calls <= 8) logf_("sampler: unknown scheduler '%s' ignored\n", g_smp_sched[cls]);
            }
            if (g_smp_steps[cls])      new_steps = g_smp_steps[cls];
            if (g_smp_cfg[cls] > 0.0f) new_cfg = g_smp_cfg[cls];
            if (new_method != cur_method || new_sched != cur_sched ||
                new_steps != cur_steps || new_cfg != cur_cfg) {
                wr_i32(p, OFF_METHOD, new_method); wr_i32(p, OFF_SCHED, new_sched);
                wr_i32(p, OFF_STEPS, new_steps);
                memcpy(p + OFF_CFG, &new_cfg, 4);
                smp_applied = 1;
                if (g_calls <= 20)
                    logf_("call %d: [%s] sampler %s/%d/%.1f -> %s/%d/%.1f\n",
                          g_calls, CLS_NAME[cls],
                          METHOD_NAMES[cur_method], cur_steps, cur_cfg,
                          METHOD_NAMES[new_method], new_steps, new_cfg);
            }
        }
    }

    /* ---- (6) 解像度アップスケール ----
     * 新サイズ (nW, nH) の決め方: 「短辺を goal まで上げる拡大率」と
     * 「長辺が lim を超えない拡大率」の小さい方を採用 (縮小はしない)。
     * img2img の場合、アプリは init/mask バッファを元のサイズで確保して
     * いるため、テンポラリへバイリニア拡大してポインタを差し替える
     * (これをしないと本物側が新サイズでバッファ範囲外を読んで落ちる) */
    int scaled = 0, nW = W, nH = H;
    int init_w = 0, init_h = 0, init_c = 0;             /* 差し替え前の init_image (復元用) */
    int mask_w = 0, mask_h = 0, mask_c = 0;             /* 差し替え前の mask_image (復元用) */
    void *init_data = NULL, *mask_data = NULL;          /* 元のピクセルバッファ */
    unsigned char *init_tmp = NULL, *mask_tmp = NULL;   /* 拡大後のテンポラリ (要 free) */
    if (up_on && !up_skip) {
        int goal = g_goal_short, lim = g_max_long;
        if (W > H) {  /* 横長 (背景) は VRAM 対策で低めの上限を使える */
            if (g_goal_short_land > 0) goal = g_goal_short_land;
            if (g_max_long_land   > 0) lim = g_max_long_land;
        }
        int S = W < H ? W : H, L = W < H ? H : W;      /* 短辺 / 長辺 */
        double f1 = (double)goal / (double)S;          /* 短辺を目標にする拡大率 */
        double f2 = (double)lim  / (double)L;          /* 長辺上限までの拡大率 */
        double f = f1 < f2 ? f1 : f2;
        if (f < 1.0) f = 1.0;                          /* 縮小はしない */
        nW = snap((int)(W * f + 0.5)); nH = snap((int)(H * f + 0.5));
        if (nW != W || nH != H) {
            init_tmp = fixup_image(p, OFF_INIT_W, OFF_INIT_H, OFF_INIT_C, OFF_INIT_D,
                                   nW, nH, &init_w, &init_h, &init_c, &init_data);
            mask_tmp = fixup_image(p, OFF_MASK_W, OFF_MASK_H, OFF_MASK_C, OFF_MASK_D,
                                   nW, nH, &mask_w, &mask_h, &mask_c, &mask_data);
            wr_i32(p, OFF_W, nW); wr_i32(p, OFF_H, nH);
            scaled = 1;
        }
    }

    /* 最初の 20 回だけ、この呼び出しで何をしたかをログに残す */
    if (g_calls <= 20) {
        if (scaled)
            logf_("call %d: %dx%d -> %dx%d  [%s]  init=%s(%dx%dx%d) mask=%s(%dx%dx%d)%s\n",
                  g_calls, W, H, nW, nH, CLS_NAME[cls],
                  init_tmp ? "up" : (init_data ? "keep" : "none"), init_w, init_h, init_c,
                  mask_tmp ? "up" : (mask_data ? "keep" : "none"), mask_w, mask_h, mask_c,
                  new_prompt ? "  +prompt" : "");
        else
            logf_("call %d: %dx%d (no scale%s)  [%s]%s\n", g_calls, W, H,
                  up_skip ? ": skip_if" : (!up_on ? ": disabled" : ""),
                  CLS_NAME[cls], new_prompt ? "  +prompt" : "");
    }

    /* ---- (7) 本物の generate_image を呼ぶ ---- */
    void* result = real_generate_image(ctx, params);

    /* ---- (8) 構造体をアプリから渡された状態へ復元し、テンポラリを解放 ---- */
    if (scaled) {
        wr_i32(p, OFF_W, W); wr_i32(p, OFF_H, H);
        if (init_tmp) {
            wr_i32(p, OFF_INIT_W, init_w); wr_i32(p, OFF_INIT_H, init_h);
            wr_ptr(p, OFF_INIT_D, init_data); free(init_tmp);
        }
        if (mask_tmp) {
            wr_i32(p, OFF_MASK_W, mask_w); wr_i32(p, OFF_MASK_H, mask_h);
            wr_ptr(p, OFF_MASK_D, mask_data); free(mask_tmp);
        }
    }
    if (smp_applied) {
        wr_i32(p, OFF_METHOD, saved_method); wr_i32(p, OFF_SCHED, saved_sched);
        wr_i32(p, OFF_STEPS, saved_steps);
        memcpy(p + OFF_CFG, &saved_cfg, 4);
    }
    if (new_prompt) { wr_ptr(p, OFF_PROMPT, old_prompt); free(new_prompt); }
    if (new_neg)    { wr_ptr(p, OFF_NEG, old_neg); free(new_neg); }
    return result;
}

/* DLL エントリポイント。プロセスにロードされた時点で、正しいバックエンドの
 * 本物 DLL を先行ロードしておく (理由は load_real_beside_proxy のコメント参照) */
BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
    (void)r;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        init_mod_paths(h);
        load_real_beside_proxy(h);
    }
    return TRUE;
}

/* ---------------- 単体テストビルド ----------------
 * python -m ziglang cc -target x86_64-windows-gnu -O1 -DPROXY_TEST -o proxy_test.exe proxy.c
 * テスト用 sd_upscale.ini のあるディレクトリで実行する。失敗時は非 0 で終了。 */
#ifdef PROXY_TEST
static int fails = 0;
static void expect(const char* label, const char* got, const char* want) {
    int ok = (got == NULL && want == NULL) ||
             (got != NULL && want != NULL && strcmp(got, want) == 0);
    printf("%-28s %s\n", label, ok ? "OK" : "FAIL");
    if (!ok) {
        printf("   got : %s\n   want: %s\n", got ? got : "(null)", want ? want : "(null)");
        fails++;
    }
}
int main(void) {
    /* init_mod_paths の確認: exe を <ルート>\sdcpp_*\lib\ 相当の場所
     * (2 つ上に InstantaleSDMod フォルダあり) に置いて実行した場合のみ
     * パスが解決される (通常のテスト実行では "" のまま =
     * カレントディレクトリの sd_upscale.ini へフォールバック) */
    init_mod_paths(NULL);
    printf("mod ini path: '%s'\n", g_ini_path);
    load_config();
    logf_("proxy_test: log write check\n");   /* ログ出力先の確認用 */
    printf("mod log path: '%s'\n", g_log_path);
    printf("map_n=%d add_land='%s' negadd_port='%s'\n", g_map_n, g_add[CLS_LANDSCAPE], g_negadd[CLS_PORTRAIT]);

    char* r;
    r = rewrite_prompt("scenery, <lora:LCM_LoRA_Weights_SD15:0.75>, forest", CLS_LANDSCAPE);
    expect("map w/ forced weight", r,
           "scenery, <lora:LCM_LoRA_SDXL:1.0>, forest, <lora:bg_test:0.5>, detailed background");
    free(r);

    r = rewrite_prompt("<lora:HyperSD_1step_Lora>, 1girl, smile", CLS_PORTRAIT);
    expect("off removes tag+comma", r,
           "1girl, smile, <lora:femaleStyle:0.8>, bareheaded");
    free(r);

    r = rewrite_prompt("1boy, knight", CLS_PORTRAIT);
    expect("rule: male lora", r, "1boy, knight, <lora:maleStyle:0.8>");
    free(r);

    r = rewrite_prompt("a woman warrior", CLS_PORTRAIT);
    expect("rule: man !in woman", r, "a woman warrior, <lora:femaleStyle:0.8>");
    free(r);

    r = rewrite_prompt("female mage", CLS_PORTRAIT);
    expect("rule: male !in female", r, "female mage, <lora:femaleStyle:0.8>");
    free(r);

    r = rewrite_prompt("1girl, red hat", CLS_PORTRAIT);
    expect("rule: ! blocks", r, "1girl, red hat, <lora:femaleStyle:0.8>");
    free(r);

    r = rewrite_prompt("dragon lair", CLS_LANDSCAPE);
    expect("rule: any class", r,
           "dragon lair, <lora:bg_test:0.5>, detailed background, dragon scales");
    free(r);

    r = rewrite_prompt("<lora:KeepWeight:0.6>, x", CLS_PORTRAIT);
    expect("map keeps orig weight", r, "<lora:kept_name:0.6>, x");
    free(r);

    r = rewrite_prompt("<lora:unknown_lora:1>, y", CLS_PORTRAIT);
    expect("unmapped passthrough", r, NULL);
    free(r);

    r = rewrite_prompt("plain prompt", CLS_PORTRAIT);
    expect("no cfg -> passthrough", r, NULL);
    free(r);

    r = rewrite_prompt("plain prompt", CLS_SQUARE);
    expect("replace w/ {prompt}", r, "masterpiece, plain prompt, scenery");
    free(r);

    r = rewrite_prompt("<lora:HyperSD_1step_Lora>, 1girl", CLS_SQUARE);
    expect("replace then lora_map", r, "masterpiece, 1girl, scenery");
    free(r);

    r = rewrite_prompt("castle, Medieval, dark fantasy, watercolor, forest", CLS_LANDSCAPE);
    expect("remove tags ci", r,
           "castle, forest, <lora:bg_test:0.5>, detailed background");
    free(r);

    r = rewrite_prompt("castle, watercolor painting", CLS_LANDSCAPE);
    expect("remove: no partial match", r,
           "castle, watercolor painting, <lora:bg_test:0.5>, detailed background");
    free(r);

    r = rewrite_prompt("fixedtag, 1girl", CLS_SQUARE);
    expect("remove before {prompt}", r, "masterpiece, 1girl, scenery");
    free(r);

    r = rewrite_negative("blurry, bad hands", CLS_PORTRAIT);
    expect("neg remove + append", r, "bad hands, worst quality, lowres");
    free(r);

    r = rewrite_negative("orig neg", CLS_SQUARE);
    expect("neg full replace", r, "only this");
    free(r);

    r = rewrite_negative("x", CLS_LANDSCAPE);
    expect("neg {prompt} twice, ci", r, "x + x");
    free(r);

    r = rewrite_negative("bad hands", CLS_PORTRAIT);
    expect("negative append", r, "bad hands, worst quality, lowres");
    free(r);

    r = append_text("", g_negadd[CLS_PORTRAIT]);
    expect("negative append empty", r, "worst quality, lowres");
    free(r);

    int ok = g_smp_method[CLS_LANDSCAPE][0] && ci_eq(g_smp_method[CLS_LANDSCAPE], "euler_a")
          && g_smp_steps[CLS_LANDSCAPE] == 24
          && g_smp_cfg[CLS_LANDSCAPE] > 4.99f && g_smp_cfg[CLS_LANDSCAPE] < 5.01f
          && g_smp_method[CLS_PORTRAIT][0] == 0;
    printf("%-28s %s\n", "sampler cfg parse", ok ? "OK" : "FAIL");
    if (!ok) { printf("   m='%s' s=%d c=%f\n", g_smp_method[CLS_LANDSCAPE], g_smp_steps[CLS_LANDSCAPE], (double)g_smp_cfg[CLS_LANDSCAPE]); fails++; }

    ok = g_enabled_cls[CLS_PORTRAIT] == 1 && g_enabled_cls[CLS_LANDSCAPE] == 0
      && g_enabled_cls[CLS_SQUARE] == 1;
    printf("%-28s %s\n", "enabled_cls parse", ok ? "OK" : "FAIL");
    if (!ok) { printf("   p=%d l=%d s=%d\n", g_enabled_cls[0], g_enabled_cls[1], g_enabled_cls[2]); fails++; }

    ok = upscale_skip_match("pixel art, 1girl", CLS_LANDSCAPE) == 1   /* 共通条件 */
      && upscale_skip_match("a sprite sheet", CLS_SQUARE) == 1        /* 共通条件 2 語目 */
      && upscale_skip_match("1girl, solo", CLS_LANDSCAPE) == 0        /* 不一致 */
      && upscale_skip_match("chibi girl", CLS_PORTRAIT) == 1          /* クラス別条件 */
      && upscale_skip_match("chibi girl, high detail", CLS_PORTRAIT) == 0  /* ! で除外 */
      && upscale_skip_match("chibi girl", CLS_LANDSCAPE) == 0;        /* 他クラスには効かない */
    printf("%-28s %s\n", "upscale skip_if", ok ? "OK" : "FAIL");
    if (!ok) { printf("   any='%s' port='%s'\n", g_skip_any, g_skip_cls[CLS_PORTRAIT]); fails++; }

    ok = name_to_enum("euler_a", METHOD_NAMES, 12) == 0
      && name_to_enum("lcm", METHOD_NAMES, 12) == 9
      && name_to_enum("dpm++2m", METHOD_NAMES, 12) == 5
      && name_to_enum("karras", SCHED_NAMES, 7) == 2
      && name_to_enum("nonsense", METHOD_NAMES, 12) == -1;
    printf("%-28s %s\n", "name_to_enum", ok ? "OK" : "FAIL");
    if (!ok) fails++;

    printf(fails ? "FAILED (%d)\n" : "ALL PASS\n", fails);
    return fails ? 1 : 0;
}
#endif
