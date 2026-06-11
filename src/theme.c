#include "theme.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

theme_t g_themes[] = {
    {"dark",   "深色",   31, 32, 33, 34, 36},
    {"light",  "亮色",   91, 92, 93, 94, 96},
    {"ocean",  "海洋",   36, 34, 37, 36, 34},
    {"sunset", "日落",   31, 33, 35, 33, 31},
    {"forest", "森林",   32, 36, 33, 34, 32},
};
int g_theme_count = sizeof(g_themes) / sizeof(g_themes[0]);
int g_theme_idx = 0;

static void set_ansi_color(char **var, int code) {
    char buf[16];
    snprintf(buf, sizeof(buf), "\033[%dm", code);
    free(*var);
    *var = strdup(buf);
}

void theme_apply(int idx) {
    if (idx < 0 || idx >= g_theme_count) return;
    g_theme_idx = idx;
    set_ansi_color(&ANSI_RED,   g_themes[idx].red);
    set_ansi_color(&ANSI_GREEN, g_themes[idx].green);
    set_ansi_color(&ANSI_YELLOW,g_themes[idx].yellow);
    set_ansi_color(&ANSI_BLUE,  g_themes[idx].blue);
    set_ansi_color(&ANSI_CYAN,  g_themes[idx].cyan);
}

int theme_choose_interactive(void) {
    int sel = 0;

    theme_apply(sel);

    system("stty -icanon -echo min 1 time 0 2>/dev/null");

    while (1) {
        printf("\033[H\033[J");
        printf("\n");
        printf("  %s==== 选择主题 (实时预览) ====%s\n\n", ANSI_CYAN, ANSI_RESET);

        for (int i = 0; i < g_theme_count; i++) {
            char marker = (i == sel) ? '>' : ' ';
            printf("  %c  %s  (%s)\n",
                   marker,
                   g_themes[i].label,
                   g_themes[i].name);
        }
        printf("\n");
        printf("  %s↑↓%s选择  %sEnter%s确认  %sq%s取消\n",
               ANSI_BLUE, ANSI_RESET, ANSI_GREEN, ANSI_RESET, ANSI_RED, ANSI_RESET);
        fflush(stdout);

        char buf[4] = {0};
        int n = read(STDIN_FILENO, buf, 3);

        if (n == 1 && buf[0] == '\n') {
            theme_apply(sel);
            system("stty sane 2>/dev/null");
            return 0;
        }

        if (n == 1 && (buf[0] == 'q' || buf[0] == 'Q')) {
            g_theme_idx = 0;
            system("stty sane 2>/dev/null");
            return 0;
        }

        if (n == 3 && buf[0] == '\033' && buf[1] == '[') {
            if (buf[2] == 'A' && sel > 0) { sel--; theme_apply(sel); }
            if (buf[2] == 'B' && sel < g_theme_count - 1) { sel++; theme_apply(sel); }
        }
    }
}
