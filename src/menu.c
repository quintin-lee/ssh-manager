#include "menu.h"
#include "tui.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_MENUS 10
#define MAX_ITEMS 15

typedef struct {
    const char *label;
    int hotkey;
    const char *items[MAX_ITEMS];
    void (*actions[MAX_ITEMS])(void);
    int item_count;
} menu_def_t;

static menu_def_t g_menus[MAX_MENUS];
static int g_menu_count = 0;
static int g_active = -1;
static int g_sel = 0;
static int g_menu_x[MAX_MENUS];

void menu_bar_init(void) {
    /* Files menu */
    g_menus[0].label = "[F]iles";
    g_menus[0].hotkey = 'F';
    g_menus[0].items[0] = "Export config";
    g_menus[0].actions[0] = menu_export_cfg;
    g_menus[0].items[1] = "Import config";
    g_menus[0].actions[1] = menu_import_cfg;
    g_menus[0].items[2] = NULL;
    g_menus[0].actions[2] = NULL;
    g_menus[0].items[3] = "Export SSH config";
    g_menus[0].actions[3] = menu_export_ssh_cfg;
    g_menus[0].items[4] = "Import SSH config";
    g_menus[0].actions[4] = menu_import_ssh_cfg;
    g_menus[0].items[5] = NULL;
    g_menus[0].actions[5] = NULL;
    g_menus[0].items[6] = "Validate config";
    g_menus[0].actions[6] = menu_validate_cfg;
    g_menus[0].items[7] = NULL;
    g_menus[0].actions[7] = NULL;
    g_menus[0].items[8] = "Quit";
    g_menus[0].actions[8] = menu_quit;
    g_menus[0].item_count = 9;

    /* Edit menu */
    g_menus[1].label = "[E]dit";
    g_menus[1].hotkey = 'E';
    g_menus[1].items[0] = "Add node";
    g_menus[1].actions[0] = menu_add_node;
    g_menus[1].items[1] = "Edit node";
    g_menus[1].actions[1] = menu_edit_node;
    g_menus[1].items[2] = "Delete node";
    g_menus[1].actions[2] = menu_delete_node;
    g_menus[1].items[3] = "Undo delete";
    g_menus[1].actions[3] = menu_undo_delete;
    g_menus[1].item_count = 4;

    /* View menu */
    g_menus[2].label = "[V]iew";
    g_menus[2].hotkey = 'V';
    g_menus[2].items[0] = "Sort by group";
    g_menus[2].actions[0] = menu_sort_group;
    g_menus[2].items[1] = "Sort by name";
    g_menus[2].actions[1] = menu_sort_name;
    g_menus[2].items[2] = NULL;
    g_menus[2].actions[2] = NULL;
    g_menus[2].items[3] = "Theme picker";
    g_menus[2].actions[3] = menu_theme;
    g_menus[2].items[4] = NULL;
    g_menus[2].actions[4] = NULL;
    g_menus[2].items[5] = "Toggle sidebar";
    g_menus[2].actions[5] = menu_toggle_sidebar;
    g_menus[2].item_count = 6;

    /* Tools menu */
    g_menus[3].label = "[T]ools";
    g_menus[3].hotkey = 'T';
    g_menus[3].items[0] = "Import SSH config";
    g_menus[3].actions[0] = menu_import_ssh_cfg;
    g_menus[3].items[1] = "Export SSH config";
    g_menus[3].actions[1] = menu_export_ssh_cfg;
    g_menus[3].items[2] = NULL;
    g_menus[3].actions[2] = NULL;
    g_menus[3].items[3] = "Validate config";
    g_menus[3].actions[3] = menu_validate_cfg;
    g_menus[3].item_count = 4;

    /* Help menu */
    g_menus[4].label = "[H]elp";
    g_menus[4].hotkey = 'H';
    g_menus[4].items[0] = "Help";
    g_menus[4].actions[0] = menu_help;
    g_menus[4].items[1] = "About";
    g_menus[4].actions[1] = menu_about;
    g_menus[4].item_count = 2;

    g_menu_count = 5;
    g_active = -1;
}

static void calc_positions(void) {
    int x = 0;
    for (int i = 0; i < g_menu_count; i++) {
        g_menu_x[i] = x;
        x += (int)strlen(g_menus[i].label) + 2;
    }
}

void menu_bar_draw(WINDOW *win) {
    calc_positions();
    int max_x;
    getmaxyx(win, max_x, max_x);

    wattron(win, COLOR_PAIR(6));
    whline(win, ' ', max_x);
    wmove(win, 0, 0);

    for (int i = 0; i < g_menu_count; i++) {
        int x = g_menu_x[i];
        if (i == g_active)
            wattron(win, COLOR_PAIR(7) | A_BOLD);
        mvwprintw(win, 0, x, "%s", g_menus[i].label);
        wattroff(win, COLOR_PAIR(7) | A_BOLD);
    }

    wattroff(win, COLOR_PAIR(6));

    if (g_active >= 0) {
        menu_def_t *m = &g_menus[g_active];
        int max_w = 0;
        for (int i = 0; i < m->item_count; i++) {
            if (!m->items[i]) continue;
            int len = (int)strlen(m->items[i]);
            if (len > max_w) max_w = len;
        }
        int dw = max_w + 4;
        int dh = m->item_count + 2;
        int dx = g_menu_x[g_active];
        int dy = 1;

        if (dx + dw > max_x) dx = max_x - dw;
        if (dx < 0) dx = 0;

        WINDOW *drop = subwin(win, dh, dw, dy, dx);
        if (!drop) return;

        wbkgd(drop, COLOR_PAIR(5));
        box(drop, 0, 0);
        int y = 1;
        for (int i = 0; i < m->item_count; i++) {
            if (!m->items[i]) {
                mvwaddch(drop, y, 1, ACS_HLINE);
                for (int c = 2; c < dw - 1; c++)
                    mvwaddch(drop, y, c, ACS_HLINE);
                y++;
                continue;
            }
            if (i == g_sel) {
                wattron(drop, COLOR_PAIR(7) | A_BOLD);
                mvwprintw(drop, y, 2, "%-*s", max_w, m->items[i]);
                wattroff(drop, COLOR_PAIR(7) | A_BOLD);
            } else {
                mvwprintw(drop, y, 2, "%-*s", max_w, m->items[i]);
            }
            y++;
        }
        wrefresh(drop);
        delwin(drop);
    }
}

static int find_menu_by_hotkey(int ch) {
    int lower = tolower(ch);
    for (int i = 0; i < g_menu_count; i++) {
        if (tolower(g_menus[i].hotkey) == lower)
            return i;
    }
    return -1;
}

int menu_bar_handle_key(int ch) {
    if (g_active < 0) {
        if (ch == KEY_F(10)) { g_active = 0; g_sel = 0; return 1; }
        int idx = find_menu_by_hotkey(ch);
        if (idx >= 0) { g_active = idx; g_sel = 0; return 1; }
        return 0;
    }

    menu_def_t *m = &g_menus[g_active];

    switch (ch) {
        case 27: case ERR:
            g_active = -1;
            return 1;
        case KEY_LEFT:
            g_active--;
            if (g_active < 0) g_active = g_menu_count - 1;
            g_sel = 0;
            return 1;
        case KEY_RIGHT:
            g_active = (g_active + 1) % g_menu_count;
            g_sel = 0;
            return 1;
        case KEY_UP:
            do {
                g_sel--;
                if (g_sel < 0) g_sel = m->item_count - 1;
            } while (!m->items[g_sel]);
            return 1;
        case KEY_DOWN:
            do {
                g_sel = (g_sel + 1) % m->item_count;
            } while (!m->items[g_sel]);
            return 1;
        case '\n': case KEY_ENTER:
            if (m->actions[g_sel]) {
                void (*fn)(void) = m->actions[g_sel];
                g_active = -1;
                fn();
            }
            return 1;
        default: {
            int idx = find_menu_by_hotkey(ch);
            if (idx >= 0 && idx != g_active) { g_active = idx; g_sel = 0; return 1; }
            int lower = tolower(ch);
            for (int i = 0; i < m->item_count; i++) {
                if (!m->items[i]) continue;
                if (m->items[i][0] && tolower((unsigned char)m->items[i][0]) == lower) {
                    g_sel = i;
                    if (m->actions[i]) {
                        void (*fn)(void) = m->actions[i];
                        g_active = -1;
                        fn();
                    }
                    return 1;
                }
            }
            return 1;
        }
    }
}

int menu_bar_active(void) {
    return g_active >= 0;
}
