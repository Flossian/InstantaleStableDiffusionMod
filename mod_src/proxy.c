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
 * 設定はすべてゲームルートの sd_upscale.ini で行い、generate_image のたびに
 * 読み直される (ライブリロード、ゲーム再起動不要)。
 *
 * 他のエクスポートはすべて .def のフォワーダ経由で本物の DLL
 * (stable-diffusion-real.dll、ゲームルート直下に置くこと) へ転送される。
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

static const char* METHOD_NAMES[] = { "euler_a", "euler", "heun", "dpm2", "dpm++2s_a",
    "dpm++2m", "dpm++2mv2", "ipndm", "ipndm_v", "lcm", "ddim_trailing", "tcd" };
static const char* SCHED_NAMES[] = { "default", "discrete", "karras", "exponential",
    "ays", "gits", "smoothstep" };

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

typedef void* (*gen_fn)(void*, void*);
typedef char* (*to_str_fn)(const void*);

static HMODULE   g_real = NULL;
static gen_fn    real_generate_image = NULL;
static to_str_fn real_params_to_str  = NULL;
static FILE*     g_log = NULL;
static int       g_calls = 0;
static int       g_prompt_state = 0;  /* 0=未確認, 1=検証済, -1=異常 (機能停止) */

static void logf_(const char* fmt, ...) {
    if (!g_log) g_log = fopen("proxy_resize.log", "a");
    if (!g_log) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(g_log, fmt, ap); va_end(ap);
    fflush(g_log);
}

static int snap(int v) {
    int rnd = g_round >= 8 ? g_round : 8;
    int r = ((v + rnd / 2) / rnd) * rnd;
    if (r < rnd) r = rnd;
    return r;
}

static int ci_eq(const char* a, const char* b) {
    for (; *a && *b; a++, b++) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        if (ca != cb) return 0;
    }
    return *a == *b;
}

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

static int ci_starts(const char* s, const char* pre) {
    for (; *pre; s++, pre++) {
        char ca = *s, cb = *pre;
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (ca != cb) return 0;
    }
    return 1;
}

/* 呼び出しごとに sd_upscale.ini (ゲームの作業ディレクトリ) を読み直し、
 * ゲームを再起動せずに全設定を調整できるようにする。ファイルが無い場合は
 * 数値は現状維持だが、注入テーブルは最後に成功した読み込みの内容が残る。 */
static void load_config(void) {
    FILE* f = fopen("sd_upscale.ini", "r");
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

static void ensure_real(void) {
    if (real_generate_image) return;
    g_real = GetModuleHandleA("stable-diffusion-real.dll");
    if (!g_real) g_real = LoadLibraryA("stable-diffusion-real.dll");
    if (g_real) {
        real_generate_image = (gen_fn)GetProcAddress(g_real, "generate_image");
        real_params_to_str  = (to_str_fn)GetProcAddress(g_real, "sd_img_gen_params_to_str");
    }
}

static int rd_i32(unsigned char* p, int off) { int v; memcpy(&v, p + off, 4); return v; }
static void wr_i32(unsigned char* p, int off, int v) { memcpy(p + off, &v, 4); }
static void* rd_ptr(unsigned char* p, int off) { void* v; memcpy(&v, p + off, sizeof v); return v; }
static void wr_ptr(unsigned char* p, int off, void* v) { memcpy(p + off, &v, sizeof v); }

/* -------- 安全なメモリ検査 (zig cc では SEH が使えないため) -------- */

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

static int lora_active(void) {
    if (g_map_n > 0 || g_rule_n > 0) return 1;
    for (int i = 0; i < 3; i++)
        if (g_add[i][0] || g_negadd[i][0] || g_repl[i][0] || g_negrepl[i][0] ||
            g_rm[i][0] || g_negrm[i][0]) return 1;
    return 0;
}

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

__declspec(dllexport) void* generate_image(void* ctx, void* params) {
    ensure_real();
    g_calls++;
    if (!real_generate_image || !params) return real_generate_image ? real_generate_image(ctx, params) : NULL;

    load_config();

    unsigned char* p = (unsigned char*)params;
    int W = rd_i32(p, OFF_W), H = rd_i32(p, OFF_H);
    if (W < 64 || W > 8192 || H < 64 || H > 8192) return real_generate_image(ctx, params);
    int cls = (W > H) ? CLS_LANDSCAPE : (W < H ? CLS_PORTRAIT : CLS_SQUARE);

    /* ---- アップスケールのスキップ判定 ----
     * プロンプト書き換えでポインタが差し替わる前に、ゲーム本来のプロンプトに
     * 対して skip_if を評価しておく。プロンプトが検証できない場合 (prompt_ok
     * が偽) は判定できないため、スキップせず通常どおり動作する */
    int up_on = g_enabled && g_enabled_cls[cls];
    int up_skip = 0;
    if (up_on && (g_skip_any[0] || g_skip_cls[cls][0]) && prompt_ok(p)) {
        const char* pr = (const char*)rd_ptr(p, OFF_PROMPT);
        if (pr && upscale_skip_match(pr, cls)) up_skip = 1;
    }

    /* ---- LoRA / プロンプト注入 ---- */
    char *np = NULL, *nn = NULL;
    void *op = NULL, *on = NULL;
    if (lora_active() && prompt_ok(p)) {
        op = rd_ptr(p, OFF_PROMPT);
        if (op) {
            np = rewrite_prompt((const char*)op, cls);
            if (np) wr_ptr(p, OFF_PROMPT, np);
        }
        on = rd_ptr(p, OFF_NEG);
        if (on && (g_negadd[cls][0] || g_negrepl[cls][0] || g_negrm[cls][0])) {
            int nlen;
            if (str_readable((const char*)on, 65536, &nlen)) {
                nn = rewrite_negative((const char*)on, cls);
                if (nn) wr_ptr(p, OFF_NEG, nn);
            }
        }
        if ((np || nn) && g_calls <= 8) {
            if (np) logf_("call %d: [%s] prompt rewritten: %.300s%s\n",
                          g_calls, CLS_NAME[cls], np, strlen(np) > 300 ? "..." : "");
            if (nn) logf_("call %d: [%s] negative rewritten: %.200s%s\n",
                          g_calls, CLS_NAME[cls], nn, strlen(nn) > 200 ? "..." : "");
        }
    }

    /* ---- サンプラー上書き ---- */
    int   sv_method = 0, sv_sched = 0, sv_steps = 0;
    float sv_cfg = 0.0f;
    int   smp_applied = 0;
    if (g_smp_state >= 0 &&
        (g_smp_method[cls][0] || g_smp_sched[cls][0] || g_smp_steps[cls] || g_smp_cfg[cls] > 0.0f)) {
        int cur_m = rd_i32(p, OFF_METHOD), cur_s = rd_i32(p, OFF_STEPS), cur_sc = rd_i32(p, OFF_SCHED);
        float cur_c; memcpy(&cur_c, p + OFF_CFG, 4);
        if (cur_m < 0 || cur_m > 11 || cur_s < 1 || cur_s > 500 || cur_sc < 0 || cur_sc > 6 ||
            !(cur_c >= 0.0f && cur_c <= 50.0f)) {
            if (g_smp_state == 0)
                logf_("sampler: layout sanity check failed (m=%d s=%d sc=%d cfg=%.2f), override disabled\n",
                      cur_m, cur_s, cur_sc, cur_c);
            g_smp_state = -1;
        } else {
            g_smp_state = 1;
            sv_method = cur_m; sv_steps = cur_s; sv_sched = cur_sc; sv_cfg = cur_c;
            int nm = cur_m, nsc = cur_sc, ns = cur_s;
            float nc = cur_c;
            if (g_smp_method[cls][0]) {
                int e = name_to_enum(g_smp_method[cls], METHOD_NAMES, 12);
                if (e >= 0) nm = e;
                else if (g_calls <= 8) logf_("sampler: unknown method '%s' ignored\n", g_smp_method[cls]);
            }
            if (g_smp_sched[cls][0]) {
                int e = name_to_enum(g_smp_sched[cls], SCHED_NAMES, 7);
                if (e >= 0) nsc = e;
                else if (g_calls <= 8) logf_("sampler: unknown scheduler '%s' ignored\n", g_smp_sched[cls]);
            }
            if (g_smp_steps[cls])      ns = g_smp_steps[cls];
            if (g_smp_cfg[cls] > 0.0f) nc = g_smp_cfg[cls];
            if (nm != cur_m || nsc != cur_sc || ns != cur_s || nc != cur_c) {
                wr_i32(p, OFF_METHOD, nm); wr_i32(p, OFF_SCHED, nsc); wr_i32(p, OFF_STEPS, ns);
                memcpy(p + OFF_CFG, &nc, 4);
                smp_applied = 1;
                if (g_calls <= 20)
                    logf_("call %d: [%s] sampler %s/%d/%.1f -> %s/%d/%.1f\n",
                          g_calls, CLS_NAME[cls],
                          METHOD_NAMES[cur_m], cur_s, cur_c, METHOD_NAMES[nm], ns, nc);
            }
        }
    }

    /* ---- 解像度アップスケール ---- */
    int scaled = 0, nW = W, nH = H;
    int iw = 0, ih = 0, ic = 0, mw = 0, mh = 0, mc = 0;
    void *id = NULL, *md = NULL;
    unsigned char *ni = NULL, *nm = NULL;
    if (up_on && !up_skip) {
        int gs = g_goal_short, ml = g_max_long;
        if (W > H) {  /* 横長 (背景) は VRAM 対策で低めの上限を使える */
            if (g_goal_short_land > 0) gs = g_goal_short_land;
            if (g_max_long_land   > 0) ml = g_max_long_land;
        }
        int S = W < H ? W : H, L = W < H ? H : W;
        double f1 = (double)gs / (double)S, f2 = (double)ml / (double)L;
        double f = f1 < f2 ? f1 : f2;
        if (f < 1.0) f = 1.0;
        nW = snap((int)(W * f + 0.5)); nH = snap((int)(H * f + 0.5));
        if (nW != W || nH != H) {
            ni = fixup_image(p, OFF_INIT_W, OFF_INIT_H, OFF_INIT_C, OFF_INIT_D, nW, nH, &iw, &ih, &ic, &id);
            nm = fixup_image(p, OFF_MASK_W, OFF_MASK_H, OFF_MASK_C, OFF_MASK_D, nW, nH, &mw, &mh, &mc, &md);
            wr_i32(p, OFF_W, nW); wr_i32(p, OFF_H, nH);
            scaled = 1;
        }
    }

    if (g_calls <= 20) {
        if (scaled)
            logf_("call %d: %dx%d -> %dx%d  [%s]  init=%s(%dx%dx%d) mask=%s(%dx%dx%d)%s\n",
                  g_calls, W, H, nW, nH, CLS_NAME[cls],
                  ni ? "up" : (id ? "keep" : "none"), iw, ih, ic,
                  nm ? "up" : (md ? "keep" : "none"), mw, mh, mc,
                  np ? "  +prompt" : "");
        else
            logf_("call %d: %dx%d (no scale%s)  [%s]%s\n", g_calls, W, H,
                  up_skip ? ": skip_if" : (!up_on ? ": disabled" : ""),
                  CLS_NAME[cls], np ? "  +prompt" : "");
    }

    void* result = real_generate_image(ctx, params);

    /* 構造体をアプリから渡された状態へ復元し、テンポラリを解放する */
    if (scaled) {
        wr_i32(p, OFF_W, W); wr_i32(p, OFF_H, H);
        if (ni) { wr_i32(p, OFF_INIT_W, iw); wr_i32(p, OFF_INIT_H, ih); wr_ptr(p, OFF_INIT_D, id); free(ni); }
        if (nm) { wr_i32(p, OFF_MASK_W, mw); wr_i32(p, OFF_MASK_H, mh); wr_ptr(p, OFF_MASK_D, md); free(nm); }
    }
    if (smp_applied) {
        wr_i32(p, OFF_METHOD, sv_method); wr_i32(p, OFF_SCHED, sv_sched); wr_i32(p, OFF_STEPS, sv_steps);
        memcpy(p + OFF_CFG, &sv_cfg, 4);
    }
    if (np) { wr_ptr(p, OFF_PROMPT, op); free(np); }
    if (nn) { wr_ptr(p, OFF_NEG, on); free(nn); }
    return result;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
    (void)r;
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(h);
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
    load_config();
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
