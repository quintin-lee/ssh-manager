#include "theme.h"
#include "tui.h"
#include "util.h"
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

theme_t g_themes[] = {
    {"dark",   "Dark",   31, 32, 33, 34, 36},
    {"light",  "Light",  91, 92, 93, 94, 96},
    {"ocean",  "Ocean",  36, 34, 37, 36, 34},
    {"sunset", "Sunset", 31, 33, 35, 33, 31},
    {"forest", "Forest", 32, 36, 33, 34, 32},
};
int g_theme_count = sizeof(g_themes) / sizeof(g_themes[0]);
int g_theme_idx = 0;

static void set_ansi_color(char **var, int code) {
    char buf[16];
    snprintf(buf, sizeof(buf), "\033[%dm", code);
    free(*var);
    *var = strdup(buf);
}

static int ansi_to_ncurses(int ansi) {
    switch (ansi % 10) {
        case 0: return COLOR_BLACK;
        case 1: return COLOR_RED;
        case 2: return COLOR_GREEN;
        case 3: return COLOR_YELLOW;
        case 4: return COLOR_BLUE;
        case 5: return COLOR_MAGENTA;
        case 6: return COLOR_CYAN;
        case 7: return COLOR_WHITE;
        default: return COLOR_WHITE;
    }
}

void theme_apply(int idx) {
    if (idx < 0 || idx >= g_theme_count) return;
    g_theme_idx = idx;
    set_ansi_color(&ANSI_RED,   g_themes[idx].red);
    set_ansi_color(&ANSI_GREEN, g_themes[idx].green);
    set_ansi_color(&ANSI_YELLOW,g_themes[idx].yellow);
    set_ansi_color(&ANSI_BLUE,  g_themes[idx].blue);
    set_ansi_color(&ANSI_CYAN,  g_themes[idx].cyan);

    int codes[5] = {g_themes[idx].red, g_themes[idx].green, g_themes[idx].yellow, g_themes[idx].blue, g_themes[idx].cyan};
    for (int i = 0; i < 5; i++)
        init_pair(i + 1, ansi_to_ncurses(codes[i]), COLOR_BLACK);
}

int theme_choose_interactive(void) {
    int sel = g_theme_idx;
    theme_apply(sel);

    touchwin(stdscr);
    refresh();

    int h = g_theme_count + 6;
    int w = 38;
    int sample_colors[] = {1, 2, 3, 4, 5};
    WINDOW *win = NULL;

    while (1) {
        win = create_win(h, w, " Select Theme ");
        if (!win) return -1;

        for (int i = 0; i < g_theme_count; i++) {
            const char *marker = (i == sel) ? "\xe2\x96\xb6" : " ";
            int is_sel = (i == sel);
            if (is_sel) {
                wattron(win, COLOR_PAIR(7) | A_BOLD);
                mvwprintw(win, 2 + i, 2, "%s %-12s", marker, g_themes[i].label);
                wattroff(win, COLOR_PAIR(7) | A_BOLD);
            } else {
                mvwprintw(win, 2 + i, 2, "%s %-12s", marker, g_themes[i].label);
            }
            for (int s = 0; s < 5; s++) {
                wattron(win, COLOR_PAIR(sample_colors[s]));
                wprintw(win, " ");
                wattroff(win, COLOR_PAIR(sample_colors[s]));
            }
        }

        wattron(win, A_DIM);
        mvwprintw(win, h - 2, 2, "Up/Down select  Enter confirm  q cancel");
        wattroff(win, A_DIM);
        wrefresh(win);

        int c = wgetch(win);
        close_win(win);

        if (c == '\n' || c == KEY_ENTER) {
            return 0;
        }
        if (c == 'q' || c == 'Q' || c == 27 || c == ERR) {
            theme_apply(g_theme_idx);
            touchwin(stdscr);
            refresh();
            return 0;
        }
        int changed = 0;
        if ((c == KEY_UP || c == 'k') && sel > 0) { sel--; changed = 1; }
        if ((c == KEY_DOWN || c == 'j') && sel < g_theme_count - 1) { sel++; changed = 1; }
        if (changed) {
            theme_apply(sel);
            touchwin(stdscr);
            refresh();
        }
    }
}
