#include "tui.h"
#include "config.h"
#include "yaml_parser.h"
#include "node.h"
#include "ssh.h"
#include "theme.h"
#include "history.h"
#include "import_export.h"
#include "util.h"
#include "menu.h"
#include "quick_cmd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ncurses.h>
#include <time.h>
#include <ctype.h>
#include <strings.h>
#include <sys/select.h>
#include <signal.h>

/* ── Constants ── */

#define MAX_TABS 9
#define PING_CACHE_SIZE 128
#define PING_TTL 30
#define SIDEBAR_MIN 28
#define SIDEBAR_MAX 45
#define SIDEBAR_PCT 35

/* ── Tree item types ── */

#define TREE_ROOT  0
#define TREE_GROUP 1
#define TREE_NODE  2

typedef struct {
    int type;
    char *label;
    int group_id;
    int node_id;
    int collapsed;
    int depth;
} tree_item_t;

/* ── Tab structure ── */

typedef struct {
    int active;
    char title[64];
    int node_id;
    ssh_pty_t pty;
    term_buf_t term;
    int exit_code;
} tab_t;

/* ── Focus / State ── */

typedef enum { FOCUS_SIDEBAR, FOCUS_TERMINAL, FOCUS_CMD } focus_t;
typedef enum { STATE_BROWSING, STATE_CONNECTED } conn_state_t;

/* ── Ping cache ── */

typedef struct {
    char host[256];
    int alive;
    time_t ts;
} ping_entry_t;

static ping_entry_t ping_cache[PING_CACHE_SIZE];
static int ping_cache_count = 0;

static int ping_check(const char *host) {
    if (!host || !host[0]) return 0;
    time_t now = time(NULL);
    for (int i = 0; i < ping_cache_count; i++) {
        if (strcmp(ping_cache[i].host, host) == 0) {
            if (now - ping_cache[i].ts < PING_TTL)
                return ping_cache[i].alive;
            goto do_ping;
        }
    }
do_ping:;
    char cmd[512];
#ifdef __APPLE__
    snprintf(cmd, sizeof(cmd), "ping -c 1 -t 1 %s >/dev/null 2>&1", host);
#else
    snprintf(cmd, sizeof(cmd), "ping -c 1 -W 1 %s >/dev/null 2>&1", host);
#endif
    int alive = (system(cmd) == 0);
    if (ping_cache_count < PING_CACHE_SIZE) {
        strncpy(ping_cache[ping_cache_count].host, host,
                sizeof(ping_cache[ping_cache_count].host) - 1);
        ping_cache[ping_cache_count].alive = alive;
        ping_cache[ping_cache_count].ts = now;
        ping_cache_count++;
    }
    return alive;
}

static int ping_cached(const char *host) {
    if (!host || !host[0]) return 0;
    time_t now = time(NULL);
    for (int i = 0; i < ping_cache_count; i++) {
        if (strcmp(ping_cache[i].host, host) == 0) {
            if (now - ping_cache[i].ts < PING_TTL)
                return ping_cache[i].alive;
            return -1;
        }
    }
    return -1;
}

/* ── Global state ── */

static node_list_t full_nodes;
static node_list_t rendered_nodes;
static char filter_key[256] = "";
static int sort_mode = 0;
static int delete_mode = 0;

/* Layout windows */
static WINDOW *menu_win;
static WINDOW *tab_win;
static WINDOW *sidebar_win;
static WINDOW *term_win;
static WINDOW *cmd_win;
static WINDOW *status_win;

/* Layout dimensions */
static int side_w;
static int term_rows;
static int term_cols;

/* Sidebar */
static tree_item_t *tree_items = NULL;
static int tree_count = 0;
static int tree_scroll = 0;
static int tree_sel = 0;
static int sidebar_visible = 1;

/* Tabs */
static tab_t tabs[MAX_TABS];
static int active_tab = 0;
static int tab_count = 0;

/* Focus / State */
static focus_t focus = FOCUS_SIDEBAR;
static conn_state_t conn_state = STATE_BROWSING;

/* Quick cmd */
static quick_cmd_t qc;

/* Resize flag */
static volatile int g_resize_flag = 0;

/* ── Forward declarations ── */

static void rebuild_tree(void);
static void draw_sidebar(void);
static void draw_tab_bar(void);
static void draw_main_details(void);
static void draw_main_terminal(void);
static void draw_cmd_bar(void);
static void draw_status_bar(void);
static void do_add_node(void);
static void do_edit_node(void);
static void do_delete_cur(void);
static void layout_create(void);
static void layout_destroy(void);
static int  tab_create(const node_t *n);
static void tab_close(int idx);
static void tab_switch(int idx);
static void tab_switch_next(void);
static void tab_switch_prev(void);
static void save_group_state(void);
static void load_group_state(void);
static void sigwinch_handler(int sig);
static void show_history(void);

/* ── Shared dialog helpers (unchanged from original) ── */

WINDOW *create_win(int h, int w, const char *title) {
    int max_y, max_x;
    getmaxyx(stdscr, max_y, max_x);
    int sy = (max_y - h) / 2;
    int sx = (max_x - w) / 2;
    WINDOW *win = newwin(h, w, sy, sx);
    if (!win) return NULL;
    box(win, 0, 0);
    wbkgd(win, COLOR_PAIR(5));
    if (title) {
        wattron(win, A_BOLD);
        mvwprintw(win, 0, 2, " %s ", title);
        wattroff(win, A_BOLD);
    }
    return win;
}

void close_win(WINDOW *win) {
    if (!win) return;
    delwin(win);
    touchwin(stdscr);
    refresh();
}

void show_toast(const char *msg, int color_pair) {
    int h, w;
    getmaxyx(stdscr, h, w);
    int len = (int)strlen(msg);
    int sx = (w - len) / 2;
    if (sx < 0) sx = 0;
    attron(COLOR_PAIR(color_pair) | A_BOLD);
    mvprintw(h - 2, sx, "%s", msg);
    attroff(COLOR_PAIR(color_pair) | A_BOLD);
    refresh();
    napms(1500);
}

int show_confirm_dialog(const char *title, const char *msg) {
    int mlen = (int)strlen(msg) + 4;
    int w = mlen < 30 ? 30 : (mlen > 60 ? 60 : mlen);
    int h = 7;
    WINDOW *win = create_win(h, w, title);
    if (!win) return 0;
    mvwprintw(win, 2, (w - (int)strlen(msg)) / 2, "%s", msg);
    wattron(win, A_DIM);
    mvwprintw(win, h - 1, 2, "Y=Yes  N=No");
    wattroff(win, A_DIM);
    wrefresh(win);
    int result = 0;
    while (1) {
        int c = wgetch(win);
        if (c == 'y' || c == 'Y' || c == '\n' || c == KEY_ENTER) { result = 1; break; }
        if (c == 'n' || c == 'N' || c == 'q' || c == 'Q' || c == 27 || c == ERR) break;
    }
    close_win(win);
    return result;
}

/* ── Filter / refresh (adapted from original) ── */

static void filter_nodes(void) {
    free(rendered_nodes.nodes);
    rendered_nodes.nodes = NULL;
    rendered_nodes.count = 0;
    rendered_nodes.capacity = 0;

    if (filter_key[0]) {
        char name_f[256] = "";
        char tag_f[256] = "";
        const char *p = filter_key;
        while (*p) {
            if (*p == '#') {
                p++;
                while (*p && *p != ' ') {
                    size_t len = strlen(tag_f);
                    if (len < sizeof(tag_f) - 2) { tag_f[len] = *p; tag_f[len + 1] = '\0'; }
                    p++;
                }
            } else {
                size_t len = strlen(name_f);
                if (len < sizeof(name_f) - 2) { name_f[len] = *p; name_f[len + 1] = '\0'; }
                p++;
            }
        }
        char *trimmed = str_trim(name_f);
        if (trimmed != name_f) memmove(name_f, trimmed, strlen(trimmed) + 1);

        int has_name = name_f[0];
        int has_tag = tag_f[0];

        for (int i = 0; i < full_nodes.count; i++) {
            node_t *n = &full_nodes.nodes[i];
            int match = 1;
            if (has_name) {
                int nm = 0;
                if (n->name && str_contains_ci(n->name, name_f)) nm = 1;
                if (n->host && str_contains_ci(n->host, name_f)) nm = 1;
                if (!nm) match = 0;
            }
            if (has_tag && match) {
                if (!n->tags || !str_contains_ci(n->tags, tag_f)) match = 0;
            }
            if (match)
                node_list_add(&rendered_nodes, n);
        }
    } else {
        for (int i = 0; i < full_nodes.count; i++)
            node_list_add(&rendered_nodes, &full_nodes.nodes[i]);
    }

    node_list_sort(&rendered_nodes, sort_mode);
}

static void refresh_nodes(void) {
    time_t old_mtime = g_config_mtime;
    config_update_mtime();
    if (g_config_mtime != old_mtime || full_nodes.count == 0) {
        node_list_free(&full_nodes);
        node_list_init(&full_nodes);
        get_all_nodes(g_config_path, NULL, &full_nodes);
    }
    filter_nodes();
    rebuild_tree();
}

/* ── Tree model ── */

static void rebuild_tree(void) {
    for (int i = 0; i < tree_count; i++)
        free(tree_items[i].label);
    free(tree_items);
    tree_items = NULL;
    tree_count = 0;

    int cap = 64;
    tree_items = malloc(sizeof(tree_item_t) * cap);

    if (!filter_key[0]) {
        /* Build tree from groups */
        char last_group[256] = "";
        int group_collapsed = 0;
        for (int i = 0; i < full_nodes.count; i++) {
            node_t *n = &full_nodes.nodes[i];
            const char *grp = n->group && n->group[0] ? n->group : "Default";

            if (strcmp(grp, last_group) != 0) {
                /* Check saved collapse state */
                group_collapsed = 0;
                char fname[512];
                snprintf(fname, sizeof(fname), "%s/.cache/sshm-groups", getenv("HOME") ? getenv("HOME") : "");
                FILE *gf = fopen(fname, "r");
                if (gf) {
                    char line[256];
                    while (fgets(line, sizeof(line), gf)) {
                        char *eq = strchr(line, ':');
                        if (eq) {
                            *eq = '\0';
                            if (strcmp(line, grp) == 0)
                                group_collapsed = atoi(eq + 1);
                        }
                    }
                    fclose(gf);
                }

                if (tree_count >= cap) {
                    cap *= 2;
                    tree_items = realloc(tree_items, sizeof(tree_item_t) * cap);
                }
                tree_items[tree_count].type = TREE_GROUP;
                tree_items[tree_count].label = strdup(grp);
                tree_items[tree_count].group_id = -1;
                tree_items[tree_count].node_id = -1;
                tree_items[tree_count].collapsed = group_collapsed;
                tree_items[tree_count].depth = 1;
                tree_count++;

                strncpy(last_group, grp, sizeof(last_group) - 1);
            }

            if (!group_collapsed) {
                if (tree_count >= cap) {
                    cap *= 2;
                    tree_items = realloc(tree_items, sizeof(tree_item_t) * cap);
                }
                tree_items[tree_count].type = TREE_NODE;
                tree_items[tree_count].label = strdup(n->name ? n->name : "?");
                tree_items[tree_count].group_id = -1;
                tree_items[tree_count].node_id = n->id;
                tree_items[tree_count].collapsed = 0;
                tree_items[tree_count].depth = 2;
                tree_count++;
            }
        }
    } else {
        /* Filter mode: flat list */
        for (int i = 0; i < rendered_nodes.count; i++) {
            node_t *n = &rendered_nodes.nodes[i];
            if (tree_count >= cap) {
                cap *= 2;
                tree_items = realloc(tree_items, sizeof(tree_item_t) * cap);
            }
            tree_items[tree_count].type = TREE_NODE;
            tree_items[tree_count].label = strdup(n->name ? n->name : "?");
            tree_items[tree_count].group_id = -1;
            tree_items[tree_count].node_id = n->id;
            tree_items[tree_count].collapsed = 0;
            tree_items[tree_count].depth = 0;
            tree_count++;
        }
    }

    if (tree_sel >= tree_count) tree_sel = tree_count > 0 ? tree_count - 1 : 0;
}

/* ── Layout management ── */

static void layout_create(void) {
    int h, w;
    getmaxyx(stdscr, h, w);

    side_w = w * SIDEBAR_PCT / 100;
    if (side_w < SIDEBAR_MIN) side_w = SIDEBAR_MIN;
    if (side_w > SIDEBAR_MAX) side_w = SIDEBAR_MAX;
    if (!sidebar_visible) side_w = 0;

    int sep = side_w > 0 ? 1 : 0;
    int term_w = w - side_w - sep;

    term_rows = h - 5;
    term_cols = term_w;

    menu_win = subwin(stdscr, 1, w, 0, 0);
    tab_win = subwin(stdscr, 1, w, 1, 0);
    if (side_w > 0)
        sidebar_win = subwin(stdscr, term_rows, side_w, 2, 0);
    else
        sidebar_win = NULL;
    term_win = subwin(stdscr, term_rows, term_w, 2, side_w + sep);
    cmd_win = subwin(stdscr, 1, w, h - 3, 0);
    status_win = subwin(stdscr, 1, w, h - 2, 0);

    keypad(term_win, TRUE);
    if (sidebar_win) keypad(sidebar_win, TRUE);
    keypad(cmd_win, TRUE);
}

static void layout_destroy(void) {
    if (menu_win) delwin(menu_win);
    if (tab_win) delwin(tab_win);
    if (sidebar_win) delwin(sidebar_win);
    if (term_win) delwin(term_win);
    if (cmd_win) delwin(cmd_win);
    if (status_win) delwin(status_win);
    menu_win = tab_win = sidebar_win = term_win = cmd_win = status_win = NULL;
}

/* ── Sidebar drawing ── */

static void draw_sidebar(void) {
    if (!sidebar_win) return;
    int h, w;
    getmaxyx(sidebar_win, h, w);

    werase(sidebar_win);
    box(sidebar_win, 0, 0);

    int y = 1;
    int start = tree_scroll;
    int visible = h - 2;

    for (int i = start; i < tree_count && y < visible + 1; i++, y++) {
        tree_item_t *ti = &tree_items[i];
        int selected = (i == tree_sel);

        if (selected) {
            wattron(sidebar_win, COLOR_PAIR(7) | A_BOLD);
            whline(sidebar_win, ' ', w - 2);
            wmove(sidebar_win, y, 1);
        }

        int x = 1 + ti->depth * 2;
        if (ti->type == TREE_GROUP) {
            mvwprintw(sidebar_win, y, x, "%s %s",
                      ti->collapsed ? "\xe2\x96\xb8" : "\xe2\x96\xbe",
                      ti->label);
        } else if (ti->type == TREE_NODE) {
            /* Status icon */
            node_t *n = NULL;
            for (int j = 0; j < full_nodes.count; j++) {
                if (full_nodes.nodes[j].id == ti->node_id) {
                    n = &full_nodes.nodes[j];
                    break;
                }
            }
            int alive = -1;
            if (n && n->host) {
                int c = ping_cached(n->host);
                alive = (c == -1) ? -1 : c;
            }
            const char *icon;
            int ic;
            if (alive == 1) { icon = "\xe2\x97\x8f"; ic = 2; }
            else if (alive == 0) { icon = "\xe2\x9c\x97"; ic = 1; }
            else { icon = "?"; ic = 3; }

            if (!selected) wattron(sidebar_win, COLOR_PAIR(ic));
            mvwprintw(sidebar_win, y, x, "%s %s", icon, ti->label);
            if (!selected) wattroff(sidebar_win, COLOR_PAIR(ic));
        }

        if (selected)
            wattroff(sidebar_win, COLOR_PAIR(7) | A_BOLD);
    }

    /* Scroll indicator if needed */
    if (tree_count > visible) {
        int pct = (tree_scroll + visible) * 100 / tree_count;
        if (pct > 100) pct = 100;
        wattron(sidebar_win, A_DIM);
        mvwprintw(sidebar_win, h - 1, w - 8, " %d%% ", pct);
        wattroff(sidebar_win, A_DIM);
    }

    wrefresh(sidebar_win);
}

/* ── Tab bar drawing ── */

static void draw_tab_bar(void) {
    int w;
    getmaxyx(tab_win, w, w);

    werase(tab_win);
    wattron(tab_win, COLOR_PAIR(6));
    whline(tab_win, ' ', w);
    wmove(tab_win, 0, 0);

    int x = 1;
    for (int i = 0; i < MAX_TABS && x < w - 10; i++) {
        if (!tabs[i].active) continue;
        int is_active = (i == active_tab);
        char buf[80];
        snprintf(buf, sizeof(buf), " %s ", tabs[i].title);
        int len = (int)strlen(buf);

        if (is_active) {
            wattron(tab_win, COLOR_PAIR(7) | A_BOLD);
            mvwprintw(tab_win, 0, x, "%s", buf);
            wattroff(tab_win, COLOR_PAIR(7) | A_BOLD);
        } else {
            wattron(tab_win, A_DIM);
            mvwprintw(tab_win, 0, x, "%s", buf);
            wattroff(tab_win, A_DIM);
        }
        x += len + 1;
    }

    if (tab_count < MAX_TABS) {
        wattron(tab_win, A_DIM);
        mvwprintw(tab_win, 0, w - 4, "  +  ");
        wattroff(tab_win, A_DIM);
    }

    wattroff(tab_win, COLOR_PAIR(6));
    wrefresh(tab_win);
}

/* ── Main pane: details (browsing mode) ── */

static void draw_main_details(void) {
    werase(term_win);
    box(term_win, 0, 0);

    if (tree_sel < 0 || tree_sel >= tree_count || tree_items[tree_sel].type != TREE_NODE) {
        wattron(term_win, A_DIM);
        mvwprintw(term_win, term_rows / 2 - 1, 2, "Select a server and press Enter to connect");
        wattroff(term_win, A_DIM);
        wrefresh(term_win);
        return;
    }

    int node_id = tree_items[tree_sel].node_id;
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, node_id, &n) != 0) {
        wrefresh(term_win);
        return;
    }

    int alive = ping_check(n.host);
    const char *icon = alive ? "\xe2\x97\x8f" : "\xe2\x9c\x97";
    int ac = (strcmp(n.type, "key") == 0);

    wattron(term_win, A_BOLD);
    mvwprintw(term_win, 1, 2, "Name:  ");
    wattroff(term_win, A_BOLD);
    wprintw(term_win, "%s", n.name ? n.name : "?");

    mvwprintw(term_win, 2, 2, "Group: %s", n.group ? n.group : "");
    mvwprintw(term_win, 3, 2, "Host:  ");
    wattron(term_win, COLOR_PAIR(2));
    wprintw(term_win, "%s", n.host ? n.host : "");
    wattroff(term_win, COLOR_PAIR(2));
    mvwprintw(term_win, 4, 2, "Port:  %d", n.port);
    mvwprintw(term_win, 5, 2, "User:  ");
    wattron(term_win, COLOR_PAIR(2));
    wprintw(term_win, "%s", n.user ? n.user : "root");
    wattroff(term_win, COLOR_PAIR(2));
    mvwprintw(term_win, 6, 2, "Auth:  %s", ac ? "Key" : "Pass");

    int r = 7;
    if (ac && n.keypath && n.keypath[0]) {
        mvwprintw(term_win, r, 2, "Key:   %s", n.keypath);
        r++;
    }
    if (n.tags && n.tags[0]) {
        mvwprintw(term_win, r, 2, "Tags:  ");
        wattron(term_win, COLOR_PAIR(5));
        wprintw(term_win, "%s", n.tags);
        wattroff(term_win, COLOR_PAIR(5));
        r++;
    }

    wattron(term_win, COLOR_PAIR(alive ? 2 : 1));
    mvwprintw(term_win, r, 2, "Stat:  %s %s", icon, alive ? "Reachable" : "Unreachable");
    wattroff(term_win, COLOR_PAIR(alive ? 2 : 1));

    wattron(term_win, A_DIM);
    mvwprintw(term_win, r + 2, 2, "Enter=Connect  e=Edit  d=Delete");
    wattroff(term_win, A_DIM);

    wrefresh(term_win);
    node_free(&n);
}

/* ── Main pane: terminal (connected mode) ── */

static void draw_main_terminal(void) {
    if (active_tab < 0 || active_tab >= MAX_TABS || !tabs[active_tab].active) {
        draw_main_details();
        return;
    }
    tab_t *tab = &tabs[active_tab];
    term_render(&tab->term, term_win, focus == FOCUS_TERMINAL);
    wrefresh(term_win);
}

/* ── Command bar drawing ── */

static void draw_cmd_bar(void) {
    quick_cmd_draw(&qc, cmd_win, focus == FOCUS_CMD);
    wrefresh(cmd_win);
}

/* ── Status bar drawing ── */

static void draw_status_bar(void) {
    int w;
    getmaxyx(status_win, w, w);

    werase(status_win);
    wattron(status_win, COLOR_PAIR(6));
    whline(status_win, ' ', w);
    wattroff(status_win, COLOR_PAIR(6));

    int sel_node_id = -1;
    if (tree_sel >= 0 && tree_sel < tree_count && tree_items[tree_sel].type == TREE_NODE)
        sel_node_id = tree_items[tree_sel].node_id;

    if (conn_state == STATE_CONNECTED && tab_count > 0 && tabs[active_tab].active) {
        wattron(status_win, COLOR_PAIR(2) | A_BOLD);
        mvwprintw(status_win, 0, 1, "Connected: %s", tabs[active_tab].title);
        wattroff(status_win, COLOR_PAIR(2) | A_BOLD);
        mvwprintw(status_win, 0, w / 2, "Ctrl+] disconnect  F3 close tab");
    } else if (delete_mode) {
        wattron(status_win, COLOR_PAIR(1) | A_BOLD);
        mvwprintw(status_win, 0, 1, "DELETE MODE");
        wattroff(status_win, COLOR_PAIR(1) | A_BOLD);
        mvwprintw(status_win, 0, 20, "Enter=confirm delete  d=cancel");
    } else if (sel_node_id > 0) {
        node_t n;
        node_init(&n);
        if (read_node_info(g_config_path, sel_node_id, &n) == 0) {
            mvwprintw(status_win, 0, 1, "%s@%s", n.name ? n.name : "?", n.host ? n.host : "?");
            node_free(&n);
        }
        mvwprintw(status_win, 0, w / 2, "F2 new tab  Tab focus  F10 menu");
    } else {
        wattron(status_win, A_DIM);
        mvwprintw(status_win, 0, 1, "F1 Help  F2 new tab  F10 menu");
        wattroff(status_win, A_DIM);
    }

    int pct = full_nodes.count > 0 ? tree_scroll * 100 / (tree_count > 0 ? tree_count : 1) : 0;
    if (pct > 100) pct = 100;
    wattron(status_win, A_DIM);
    mvwprintw(status_win, 0, w - 10, " %d/%d ", tree_sel + 1, tree_count);
    wattroff(status_win, A_DIM);

    wrefresh(status_win);
}

/* ── Tab management ── */

static int tab_create(const node_t *n) {
    if (!n) return -1;
    int idx = -1;
    for (int i = 0; i < MAX_TABS; i++) {
        if (!tabs[i].active) { idx = i; break; }
    }
    if (idx < 0) {
        show_toast(" Max tabs reached ", 1);
        return -1;
    }

    memset(&tabs[idx], 0, sizeof(tab_t));
    tabs[idx].active = 1;
    snprintf(tabs[idx].title, sizeof(tabs[idx].title), "%s", n->name ? n->name : "?");
    tabs[idx].node_id = n->id;

    term_buf_init(&tabs[idx].term, term_rows, term_cols);

    if (ssh_pty_start(&tabs[idx].pty, n, term_rows, term_cols) != 0) {
        tabs[idx].active = 0;
        show_toast(" Connection failed ", 1);
        return -1;
    }

    tab_count++;
    active_tab = idx;
    conn_state = STATE_CONNECTED;
    focus = FOCUS_TERMINAL;
    return idx;
}

static void tab_close(int idx) {
    if (idx < 0 || idx >= MAX_TABS || !tabs[idx].active) return;
    ssh_pty_stop(&tabs[idx].pty);
    term_buf_free(&tabs[idx].term);
    tabs[idx].active = 0;
    tab_count--;

    if (tab_count == 0) {
        conn_state = STATE_BROWSING;
        focus = FOCUS_SIDEBAR;
        active_tab = 0;
    } else {
        /* Switch to nearest active tab */
        while (!tabs[active_tab].active) {
            active_tab = (active_tab + 1) % MAX_TABS;
        }
    }
}

static void tab_switch(int idx) {
    if (idx < 0 || idx >= MAX_TABS || !tabs[idx].active) return;
    active_tab = idx;
    /* Resize term_buf if terminal dimensions changed */
    if (tabs[idx].term.rows != term_rows || tabs[idx].term.cols != term_cols) {
        term_buf_resize(&tabs[idx].term, term_rows, term_cols);
        ssh_pty_resize(&tabs[idx].pty, term_rows, term_cols);
    }
}

static void tab_switch_next(void) {
    for (int i = 1; i <= MAX_TABS; i++) {
        int idx = (active_tab + i) % MAX_TABS;
        if (tabs[idx].active) { tab_switch(idx); return; }
    }
}

static void tab_switch_prev(void) {
    for (int i = 1; i <= MAX_TABS; i++) {
        int idx = (active_tab - i + MAX_TABS) % MAX_TABS;
        if (tabs[idx].active) { tab_switch(idx); return; }
    }
}

/* ── Group state persistence ── */

static char g_group_state_path[1024] = "";

static void save_group_state(void) {
    if (!g_group_state_path[0]) return;
    FILE *f = fopen(g_group_state_path, "w");
    if (!f) return;
    for (int i = 0; i < tree_count; i++) {
        if (tree_items[i].type == TREE_GROUP)
            fprintf(f, "%s:%d\n", tree_items[i].label, tree_items[i].collapsed);
    }
    fclose(f);
}

static void load_group_state(void) {
    const char *home = getenv("HOME");
    if (home)
        snprintf(g_group_state_path, sizeof(g_group_state_path),
                 "%s/.cache/sshm-groups", home);
}

/* ── SIGWINCH handler ── */

static void sigwinch_handler(int sig) {
    (void)sig;
    g_resize_flag = 1;
}

/* ── Menu callbacks ── */

void menu_add_node(void) { do_add_node(); }
void menu_edit_node(void) { do_edit_node(); }
void menu_delete_node(void) { do_delete_cur(); }
void menu_undo_delete(void) {
    if (undo_delete() == 0) show_toast(" Node restored ", 2);
    else show_toast(" Nothing to restore ", 3);
    refresh_nodes();
}
void menu_export_cfg(void) {
    export_config_interactive();
}
void menu_import_cfg(void) {
    import_config_interactive();
    refresh_nodes();
}
void menu_theme(void) {
    theme_choose_interactive();
}
void menu_help(void) {
    /* TODO: inline help */
    show_toast(" F1=Help ", 5);
}
void menu_quit(void) {
    /* Will be caught in main loop */
}
void menu_sort_group(void) {
    sort_mode = 0;
    refresh_nodes();
}
void menu_sort_name(void) {
    sort_mode = 1;
    refresh_nodes();
}
void menu_toggle_sidebar(void) {
    sidebar_visible = !sidebar_visible;
    g_resize_flag = 1;
}
void menu_about(void) {
    show_toast(" SSH Manager v0.5.3 ", 5);
}
void menu_import_ssh_cfg(void) {
    import_config_interactive();
    refresh_nodes();
}
void menu_export_ssh_cfg(void) {
    export_ssh_config();
}
void menu_validate_cfg(void) {
    node_list_t list;
    if (get_all_nodes(g_config_path, NULL, &list) >= 0) {
        char buf[64];
        snprintf(buf, sizeof(buf), " Config valid: %d nodes ", list.count);
        show_toast(buf, 2);
        node_list_free(&list);
    } else {
        show_toast(" Config invalid ", 1);
    }
}

/* ── Action helpers ── */

static void do_add_node(void) {
    add_node_interactive();
    refresh_nodes();
}

static void do_edit_node(void) {
    if (tree_sel < 0 || tree_sel >= tree_count) return;
    if (tree_items[tree_sel].type != TREE_NODE) return;
    edit_node_interactive(tree_items[tree_sel].node_id);
    refresh_nodes();
}

static void do_delete_cur(void) {
    if (tree_sel < 0 || tree_sel >= tree_count) return;
    if (tree_items[tree_sel].type != TREE_NODE) return;
    delete_node_by_id(tree_items[tree_sel].node_id);
    refresh_nodes();
}

static void do_connect_selected(void) {
    if (tree_sel < 0 || tree_sel >= tree_count) return;
    if (tree_items[tree_sel].type != TREE_NODE) return;
    int node_id = tree_items[tree_sel].node_id;
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, node_id, &n) != 0) return;

    history_record(n.name, n.host);
    tab_create(&n);
    node_free(&n);
}

/* ── Main browsing loop ── */

static int browsing_loop(void) {
    int running = 1;

    while (running && conn_state == STATE_BROWSING) {
        if (g_resize_flag) {
            layout_destroy();
            layout_create();
            refresh_nodes();
            g_resize_flag = 0;
        }

        int h;
        getmaxyx(stdscr, h, h);

        /* Auto-scroll sidebar */
        int sb_h = h - 5;
        if (sidebar_win) {
            int sb_visible = sb_h - 2;
            if (tree_sel < tree_scroll) tree_scroll = tree_sel;
            if (tree_sel >= tree_scroll + sb_visible)
                tree_scroll = tree_sel - sb_visible + 1;
            if (tree_scroll < 0) tree_scroll = 0;
        }

        /* Draw */
        erase();
        menu_bar_draw(menu_win);
        draw_tab_bar();
        draw_sidebar();
        draw_main_details();
        draw_cmd_bar();
        draw_status_bar();
        refresh();

        int ch = getch();

        /* Menu takes priority */
        if (menu_bar_active()) {
            menu_bar_handle_key(ch);
            continue;
        }

        /* Global hotkeys */
        if (ch == KEY_F(10)) { menu_bar_handle_key(ch); continue; }
            if (ch == KEY_F(1)) { /* TODO: show help popup */ continue; }
            if (ch == KEY_F(2)) { do_connect_selected(); continue; }
        if (ch == '\t') {
            focus = (focus + 1) % 3;
            if (focus == FOCUS_TERMINAL && tab_count == 0)
                focus = FOCUS_CMD;
            if (focus == FOCUS_CMD)
                quick_cmd_init(&qc);
            continue;
        }

        /* Sidebar keys */
        if (focus == FOCUS_SIDEBAR) {
            switch (ch) {
                case KEY_UP: case 'k': case 'K':
                    if (tree_sel > 0) tree_sel--;
                    break;
                case KEY_DOWN: case 'j': case 'J':
                    if (tree_sel < tree_count - 1) tree_sel++;
                    break;
                case KEY_LEFT:
                    if (tree_sel >= 0 && tree_sel < tree_count && tree_items[tree_sel].type == TREE_GROUP) {
                        tree_items[tree_sel].collapsed = 1;
                        rebuild_tree();
                    }
                    break;
                case KEY_RIGHT:
                    if (tree_sel >= 0 && tree_sel < tree_count && tree_items[tree_sel].type == TREE_GROUP) {
                        tree_items[tree_sel].collapsed = 0;
                        rebuild_tree();
                    }
                    break;
                case '\n': case KEY_ENTER:
                    do_connect_selected();
                    break;
                case 'a': case 'A': do_add_node(); break;
                case 'e': case 'E': do_edit_node(); break;
                case 'd': case 'D': delete_mode = !delete_mode; break;
                case 'u': case 'U':
                    if (undo_delete() == 0) show_toast(" Node restored ", 2);
                    else show_toast(" Nothing to restore ", 3);
                    refresh_nodes();
                    break;
                case 's': case 'S':
                    sort_mode = (sort_mode + 1) % 3;
                    refresh_nodes();
                    break;
                case 't': case 'T': theme_choose_interactive(); refresh_nodes(); break;
                case 'x': case 'X': export_config_interactive(); break;
                case 'i': case 'I': import_config_interactive(); refresh_nodes(); break;
                case 'h': case 'H': /* TODO: help */ break;
                case 'r': case 'R': show_history(); break;
                case 'q': case 'Q': running = 0; break;
                case 27: {
                    int next = getch();
                    if (next == ERR) {
                        filter_key[0] = '\0';
                        refresh_nodes();
                    } else if (next == '[') {
                        int dir = getch();
                        if (dir == 'A' && tree_sel > 0) tree_sel--;
                        if (dir == 'B' && tree_sel < tree_count - 1) tree_sel++;
                    } else {
                        menu_bar_handle_key(next);
                    }
                    break;
                }
                case KEY_BACKSPACE: case 127: case '\b':
                    if (filter_key[0]) {
                        filter_key[strlen(filter_key) - 1] = '\0';
                        refresh_nodes();
                    }
                    break;
                default:
                    if (ch >= 32 && ch <= 126) {
                        size_t flen = strlen(filter_key);
                        if (flen < sizeof(filter_key) - 1) {
                            filter_key[flen] = tolower(ch);
                            filter_key[flen + 1] = '\0';
                            refresh_nodes();
                        }
                    }
                    break;
            }
        } else if (focus == FOCUS_CMD) {
            int r = quick_cmd_handle(&qc, ch);
            if (r == 2) {
                /* Enter: send command to active tab */
                if (tab_count > 0 && qc.send_all) {
                    for (int i = 0; i < MAX_TABS; i++) {
                        if (tabs[i].active) {
                            ssh_pty_write(&tabs[i].pty, qc.buf, qc.pos);
                            ssh_pty_write(&tabs[i].pty, "\n", 1);
                        }
                    }
                } else if (active_tab >= 0 && tabs[active_tab].active) {
                    ssh_pty_write(&tabs[active_tab].pty, qc.buf, qc.pos);
                    ssh_pty_write(&tabs[active_tab].pty, "\n", 1);
                }
                quick_cmd_clear(&qc);
            } else if (r == 3 || r == 0) {
                focus = FOCUS_SIDEBAR;
            }
        }
    }
    return running ? 0 : 1;
}

/* ── History screen (popup, reused from original) ── */

static void show_history(void) {
    int cnt;
    history_entry_t *entries = history_get_recent(&cnt);
    if (cnt > 20) cnt = 20;

    int h = (cnt + 5 > 24) ? 24 : cnt + 5;
    int w = 52;
    WINDOW *win = create_win(h, w, " Recent Connections ");
    if (!win) { free(entries); return; }

    wattron(win, A_DIM);
    mvwprintw(win, 2, 2, "%-4s  %-16s  %-22s  %s", "#", "Name", "Host", "Time");
    wattroff(win, A_DIM);

    int max_items = h - 5;
    int items = cnt > max_items ? max_items : cnt;
    for (int i = 0; i < items; i++) {
        struct tm *tm = localtime(&entries[i].timestamp);
        char timebuf[32];
        strftime(timebuf, sizeof(timebuf), "%m-%d %H:%M", tm);
        char name_buf[17], host_buf[23];
        strncpy(name_buf, entries[i].name ? entries[i].name : "", 16);
        name_buf[16] = '\0';
        strncpy(host_buf, entries[i].host ? entries[i].host : "", 22);
        host_buf[22] = '\0';
        mvwprintw(win, 3 + i, 2, "%-4d  %-16s  %-22s  %s", i + 1, name_buf, host_buf, timebuf);
    }

    wattron(win, A_DIM);
    mvwprintw(win, h - 1, 2, "q/ESC=back");
    wattroff(win, A_DIM);
    wrefresh(win);

    while (1) {
        int c = wgetch(win);
        if (c == 'q' || c == 'Q' || c == 27 || c == ERR) break;
    }

    for (int i = 0; i < cnt; i++) history_entry_free(&entries[i]);
    free(entries);
    close_win(win);
}

/* ── Main connected loop ── */

static int connected_loop(void) {
    int running = 1;

    while (running && conn_state == STATE_CONNECTED && tab_count > 0) {
        if (g_resize_flag) {
            layout_destroy();
            layout_create();
            for (int i = 0; i < MAX_TABS; i++) {
                if (tabs[i].active) {
                    term_buf_resize(&tabs[i].term, term_rows, term_cols);
                    ssh_pty_resize(&tabs[i].pty, term_rows, term_cols);
                }
            }
            g_resize_flag = 0;
        }

        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(STDIN_FILENO, &rfds);
        int max_fd = STDIN_FILENO;

        for (int i = 0; i < MAX_TABS; i++) {
            if (tabs[i].active) {
                FD_SET(tabs[i].pty.master_fd, &rfds);
                if (tabs[i].pty.master_fd > max_fd)
                    max_fd = tabs[i].pty.master_fd;
            }
        }

        struct timeval tv = {0, 80000};
        int sel_ret = select(max_fd + 1, &rfds, NULL, NULL, &tv);

        if (sel_ret > 0) {
            /* Read PTY output for all tabs */
            for (int i = 0; i < MAX_TABS; i++) {
                if (!tabs[i].active) continue;
                if (FD_ISSET(tabs[i].pty.master_fd, &rfds)) {
                    char buf[4096];
                    int n = ssh_pty_read(&tabs[i].pty, buf, sizeof(buf));
                    if (n > 0) {
                        term_buf_feed(&tabs[i].term, buf, n);
                    } else {
                        /* Session ended */
                        tab_close(i);
                    }
                }
            }

            /* Handle keyboard input */
            if (FD_ISSET(STDIN_FILENO, &rfds)) {
                int ch = getch();

                /* Menu activation */
                if (menu_bar_active()) {
                    menu_bar_handle_key(ch);
                    continue;
                }
                if (ch == KEY_F(10)) { menu_bar_handle_key(ch); continue; }

                /* ESC: Alt+number for tabs, or forward to terminal */
                if (ch == 27) {
                    nodelay(stdscr, TRUE);
                    int next = getch();
                    nodelay(stdscr, FALSE);
                    if (next >= '1' && next <= '9') {
                        int idx = next - '1';
                        if (idx >= 0 && idx < MAX_TABS && tabs[idx].active) {
                            tab_switch(idx);
                        }
                    } else if (next == ERR) {
                        if (tabs[active_tab].active)
                            ssh_pty_write(&tabs[active_tab].pty, "\033", 1);
                    }
                    continue;
                }

                /* Global connection keys */
                if (ch == 0x1D || ch == KEY_F(3)) {
                    tab_close(active_tab);
                    if (tab_count == 0) break;
                    continue;
                }
                if (ch == KEY_F(2)) { do_connect_selected(); continue; }
                if (ch == KEY_PPAGE) { tab_switch_prev(); continue; }
                if (ch == KEY_NPAGE) { tab_switch_next(); continue; }
                if (ch == '\t') {
                    focus = (focus + 1) % 3;
                    if (focus == FOCUS_CMD) quick_cmd_init(&qc);
                    continue;
                }

                /* Per-focus handling */
                if (focus == FOCUS_TERMINAL) {
                    if (tabs[active_tab].active)
                        ssh_pty_write(&tabs[active_tab].pty, (char*)&ch, 1);
                } else if (focus == FOCUS_CMD) {
                    int r = quick_cmd_handle(&qc, ch);
                    if (r == 2) {
                        if (qc.send_all) {
                            for (int i = 0; i < MAX_TABS; i++) {
                                if (tabs[i].active) {
                                    ssh_pty_write(&tabs[i].pty, qc.buf, qc.pos);
                                    ssh_pty_write(&tabs[i].pty, "\n", 1);
                                }
                            }
                        } else if (tabs[active_tab].active) {
                            ssh_pty_write(&tabs[active_tab].pty, qc.buf, qc.pos);
                            ssh_pty_write(&tabs[active_tab].pty, "\n", 1);
                        }
                        quick_cmd_clear(&qc);
                    } else if (r == 3 || r == 0) {
                        focus = FOCUS_TERMINAL;
                    }
                } else if (focus == FOCUS_SIDEBAR) {
                    switch (ch) {
                        case KEY_UP: if (tree_sel > 0) tree_sel--; break;
                        case KEY_DOWN: if (tree_sel < tree_count - 1) tree_sel++; break;
                        case '\n': case KEY_ENTER: do_connect_selected(); break;
                        case 'e': case 'E': do_edit_node(); break;
                        case 'd': case 'D': delete_mode = !delete_mode; break;
                        case 'u': case 'U':
                            if (undo_delete() == 0) show_toast(" Node restored ", 2);
                            else show_toast(" Nothing to restore ", 3);
                            refresh_nodes();
                            break;
                        case 'a': case 'A': do_add_node(); break;
                        case 's': case 'S':
                            sort_mode = (sort_mode + 1) % 3;
                            refresh_nodes();
                            break;
                        default: break;
                    }
                }
            }
        }

        /* Redraw */
        erase();
        menu_bar_draw(menu_win);
        draw_tab_bar();
        draw_sidebar();
        draw_main_terminal();
        draw_cmd_bar();
        draw_status_bar();
        refresh();
    }

    return running ? 0 : 1;
}

/* ── Initialization / main entry ── */

void tui_init(void) {
    initscr();
    raw();
    noecho();
    keypad(stdscr, TRUE);
    curs_set(0);
    nodelay(stdscr, FALSE);

    if (has_colors()) {
        start_color();
        init_pair(1, COLOR_RED, COLOR_BLACK);
        init_pair(2, COLOR_GREEN, COLOR_BLACK);
        init_pair(3, COLOR_YELLOW, COLOR_BLACK);
        init_pair(4, COLOR_BLUE, COLOR_BLACK);
        init_pair(5, COLOR_CYAN, COLOR_BLACK);
        init_pair(6, COLOR_WHITE, COLOR_BLUE);
        init_pair(7, COLOR_BLACK, COLOR_GREEN);
        init_pair(8, COLOR_WHITE, COLOR_RED);
    }

    signal(SIGWINCH, sigwinch_handler);

    load_group_state();

    if (!g_config_path) {
        if (config_resolve() != 0) {
            endwin();
            fprintf(stderr, "Failed to resolve config\n");
            exit(1);
        }
        config_setup_permissions();
    }
}

void tui_end(void) {
    save_group_state();
    for (int i = 0; i < MAX_TABS; i++) {
        if (tabs[i].active) {
            ssh_pty_stop(&tabs[i].pty);
            term_buf_free(&tabs[i].term);
        }
    }
    for (int i = 0; i < tree_count; i++)
        free(tree_items[i].label);
    free(tree_items);
    /* rendered_nodes shares char* pointers with full_nodes — free full_nodes only */
    rendered_nodes.count = 0;
    free(rendered_nodes.nodes);
    rendered_nodes.nodes = NULL;
    node_list_free(&full_nodes);
    layout_destroy();
    curs_set(1);
    endwin();
}

int tui_interactive_list(void) {
    memset(tabs, 0, sizeof(tabs));
    memset(&qc, 0, sizeof(qc));
    tree_sel = 0;
    tree_scroll = 0;
    focus = FOCUS_SIDEBAR;
    conn_state = STATE_BROWSING;
    tab_count = 0;
    active_tab = 0;
    filter_key[0] = '\0';
    sort_mode = 0;
    delete_mode = 0;
    sidebar_visible = 1;

    node_list_init(&rendered_nodes);
    refresh_nodes();

    layout_create();

    /* Initialize menu bar */
    menu_bar_init();

    int exit_code = 0;

    while (1) {
        if (conn_state == STATE_BROWSING) {
            int r = browsing_loop();
            if (r != 0) { exit_code = r; break; }
            /* If browsing_loop returned 0 but conn_state changed to connected,
               fall through to connected_loop */
        }
        if (conn_state == STATE_CONNECTED) {
            int r = connected_loop();
            if (r != 0) { exit_code = r; break; }
        }
        if (conn_state == STATE_BROWSING) break;
    }

    tui_end();
    return exit_code;
}
