#include "tui.h"
#include "config.h"
#include "yaml_parser.h"
#include "node.h"
#include "ssh.h"
#include "theme.h"
#include "history.h"
#include "import_export.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ncurses.h>
#include <time.h>
#include <ctype.h>
#include <strings.h>

#define PING_CACHE_SIZE 128
#define PING_TTL 30

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

static int selected_idx = 0;
static int scroll_offset = 0;
static char filter_key[256] = "";
static int sort_mode = 0;
static int delete_mode = 0;
static node_list_t rendered_nodes;
static node_list_t full_nodes;

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

    if (selected_idx >= rendered_nodes.count)
        selected_idx = rendered_nodes.count > 0 ? rendered_nodes.count - 1 : 0;
}

static void refresh_node_list(void) {
    time_t old_mtime = g_config_mtime;
    config_update_mtime();
    if (g_config_mtime != old_mtime || full_nodes.count == 0) {
        node_list_free(&full_nodes);
        node_list_init(&full_nodes);
        get_all_nodes(g_config_path, NULL, &full_nodes);
    }
    filter_nodes();
}

static int get_visible_height(void) {
    int h;
    getmaxyx(stdscr, h, h);
    return h - 5;
}

/* ── Shared dialog helpers ── */

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
    int len = strlen(msg);
    int sx = (w - len) / 2;
    if (sx < 0) sx = 0;
    attron(COLOR_PAIR(color_pair) | A_BOLD);
    mvprintw(h - 2, sx, "%s", msg);
    attroff(COLOR_PAIR(color_pair) | A_BOLD);
    refresh();
    napms(1500);
}

/* ── Header ── */

static void draw_header(void) {
    int w;
    getmaxyx(stdscr, w, w);

    int name_w = (w > 110) ? 28 : 18;
    int host_w = (w > 110) ? 28 : 22;

    attron(COLOR_PAIR(6));
    mvhline(0, 0, ' ', w);
    mvprintw(0, 2, "SSH Manager");
    if (filter_key[0])
        printw("  # filter:%s", filter_key);
    const char *sort_labels[] = {"group", "name", "none"};
    attron(A_DIM);
    printw("  sort:%s", sort_labels[sort_mode % 3]);
    attroff(A_DIM);
    attroff(COLOR_PAIR(6));

    attron(COLOR_PAIR(5) | A_BOLD);
    int col = 0;
    mvprintw(1, col, " %-5s", "  "); col += 7;
    mvwaddch(stdscr, 1, col, ACS_VLINE); col += 1;
    mvwprintw(stdscr, 1, col, " "); col += 2;
    mvwprintw(stdscr, 1, col, " %-3s", "ID"); col += 5;
    mvwaddch(stdscr, 1, col, ACS_VLINE); col += 1;
    mvwprintw(stdscr, 1, col, " "); col += 2;
    mvwprintw(stdscr, 1, col, " %-12s", "Group"); col += 14;
    mvwaddch(stdscr, 1, col, ACS_VLINE); col += 1;
    mvwprintw(stdscr, 1, col, " "); col += 2;
    mvwprintw(stdscr, 1, col, " %-*s", name_w, "Name"); col += name_w + 2;
    mvwaddch(stdscr, 1, col, ACS_VLINE); col += 1;
    mvwprintw(stdscr, 1, col, " "); col += 2;
    mvwprintw(stdscr, 1, col, " %-*s", host_w, "Host:Port"); col += host_w + 2;
    mvwaddch(stdscr, 1, col, ACS_VLINE); col += 1;
    mvwprintw(stdscr, 1, col, " "); col += 2;
    mvwprintw(stdscr, 1, col, " %-4s", "Type");
    attroff(COLOR_PAIR(5) | A_BOLD);
}

/* ── Node row ── */

static void draw_node(int row, int idx, int selected) {
    if (idx < 0 || idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[idx];
    int w;
    getmaxyx(stdscr, w, w);

    int id_display = idx + 1;
    int name_w = (w > 110) ? 28 : 18;
    int host_w = (w > 110) ? 28 : 22;

    int alive;
    if (idx == selected)
        alive = ping_check(n->host);
    else {
        int c = ping_cached(n->host);
        alive = (c == -1) ? -1 : c;
    }

    const char *icon;
    if (alive == 1) icon = "\xe2\x97\x8f";
    else if (alive == 0) icon = "\xe2\x9c\x97";
    else icon = "?";
    int icon_color = (alive == 1) ? 2 : ((alive == 0) ? 1 : 3);

    if (!selected && idx % 2 == 0)
        wattron(stdscr, A_DIM);

    int col = 0;
    mvwprintw(stdscr, row, col, " %s ", selected ? "\xe2\x96\xb6" : " "); col += 4;

    wattron(stdscr, COLOR_PAIR(icon_color));
    wprintw(stdscr, "%s", icon);
    wattroff(stdscr, COLOR_PAIR(icon_color));
    col += 4;
    mvwaddch(stdscr, row, col, ACS_VLINE); col += 3;

    mvwprintw(stdscr, row, col, " %-3d", id_display); col += 5;
    mvwaddch(stdscr, row, col, ACS_VLINE); col += 3;

    mvwprintw(stdscr, row, col, " %-12s", n->group ? n->group : ""); col += 14;
    mvwaddch(stdscr, row, col, ACS_VLINE); col += 3;

    mvwprintw(stdscr, row, col, " ");
    char *match_pos = NULL;
    if (filter_key[0] && n->name)
        match_pos = strcasestr(n->name, filter_key);
    if (match_pos) {
        int prefix_len = (int)(match_pos - n->name);
        int match_len = (int)strlen(filter_key);
        wprintw(stdscr, "%.*s", prefix_len, n->name);
        wattron(stdscr, A_REVERSE);
        wprintw(stdscr, "%.*s", match_len, match_pos);
        wattroff(stdscr, A_REVERSE);
        int rem = name_w - prefix_len - match_len;
        if (rem > 0) wprintw(stdscr, "%-*s", rem, match_pos + match_len);
    } else {
        wprintw(stdscr, "%-*s", name_w, n->name ? n->name : "");
    }
    col += name_w + 2;
    mvwaddch(stdscr, row, col, ACS_VLINE); col += 3;

    char hostport[128];
    snprintf(hostport, sizeof(hostport), "%s:%d", n->host ? n->host : "?", n->port);
    match_pos = NULL;
    if (filter_key[0]) {
        char *hp_match = strcasestr(hostport, filter_key);
        if (!hp_match && n->host)
            hp_match = strcasestr(n->host, filter_key);
        match_pos = hp_match ? strcasestr(hostport, filter_key) : NULL;
    }
    mvwprintw(stdscr, row, col, " ");
    if (match_pos) {
        int prefix_len = (int)(match_pos - hostport);
        int match_len = (int)strlen(filter_key);
        wprintw(stdscr, "%.*s", prefix_len, hostport);
        wattron(stdscr, A_REVERSE);
        wprintw(stdscr, "%.*s", match_len, match_pos);
        wattroff(stdscr, A_REVERSE);
        int rem = host_w - prefix_len - match_len;
        if (rem > 0) wprintw(stdscr, "%-*s", rem, match_pos + match_len);
    } else {
        wprintw(stdscr, "%-*s", host_w, hostport);
    }
    col += host_w + 2;
    mvwaddch(stdscr, row, col, ACS_VLINE); col += 3;

    wprintw(stdscr, " %-4s", n->type ? n->type : "");
    col += 6;

    if (n->tags && n->tags[0]) {
        wattron(stdscr, COLOR_PAIR(5));
        mvwprintw(stdscr, row, col, " %s", n->tags);
        wattroff(stdscr, COLOR_PAIR(5));
    }

    if (idx == selected)
        mvwchgat(stdscr, row, 0, -1, A_BOLD, 7, NULL);
    else if (idx % 2 == 0)
        wattroff(stdscr, A_DIM);
}

/* ── Footer ── */

static void draw_footer(int total) {
    int h, w;
    getmaxyx(stdscr, h, w);
    int footer_row = h - 2;
    int visible = get_visible_height();

    attron(COLOR_PAIR(6) | A_DIM);
    mvhline(footer_row - 1, 0, ACS_HLINE, w);
    attroff(COLOR_PAIR(6) | A_DIM);

    if (delete_mode) {
        attron(COLOR_PAIR(8) | A_BOLD);
        mvprintw(footer_row, 0, " DELETE MODE ");
        attroff(COLOR_PAIR(8) | A_BOLD);
    } else {
        mvprintw(footer_row, 0, " ");
    }

    attron(COLOR_PAIR(5) | A_BOLD);
    printw("%d", total);
    attroff(COLOR_PAIR(5) | A_BOLD);
    printw(" nodes");

    if (total > 0 && selected_idx < rendered_nodes.count) {
        node_t *n = &rendered_nodes.nodes[selected_idx];
        if (n) {
            int live = ping_check(n->host);
            printw("  ");
            wattron(stdscr, COLOR_PAIR(live ? 2 : 1));
            printw(" %s ", live ? "\xe2\x97\x8f" : "\xe2\x9c\x97");
            wattroff(stdscr, COLOR_PAIR(live ? 2 : 1));
            wattron(stdscr, A_BOLD);
            printw("%s", n->name ? n->name : "?");
            wattroff(stdscr, A_BOLD);
            wattron(stdscr, COLOR_PAIR(live ? 4 : 1));
            printw("@%s", n->host ? n->host : "?");
            wattroff(stdscr, COLOR_PAIR(live ? 4 : 1));
        }
    }

    if (total > visible) {
        int pct = (scroll_offset + visible) * 100 / total;
        if (pct > 100) pct = 100;
        attron(COLOR_PAIR(5));
        mvprintw(footer_row, w - 10, " %d%% ", pct);
        attroff(COLOR_PAIR(5));
    }

    attron(COLOR_PAIR(6));
    mvhline(h - 1, 0, ' ', w);
    attroff(COLOR_PAIR(6));
    mvprintw(h - 1, 0, " ");
    attron(COLOR_PAIR(4) | A_DIM);
    printw("\xe2\x86\x91\xe2\x86\x93/jk");
    attroff(COLOR_PAIR(4) | A_DIM);
    printw(" sel ");
    attron(A_DIM);
    printw("| ");
    attroff(A_DIM);
    attron(COLOR_PAIR(4) | A_DIM);
    printw("PgUp/Dn");
    attroff(COLOR_PAIR(4) | A_DIM);
    printw(" pg ");
    attron(A_DIM);
    printw("| ");
    attroff(A_DIM);
    attron(COLOR_PAIR(4) | A_DIM);
    printw("1-9");
    attroff(COLOR_PAIR(4) | A_DIM);
    printw(" con ");
    attron(A_DIM);
    printw("| ");
    attroff(A_DIM);
    attron(COLOR_PAIR(2) | A_DIM);
    printw("e");
    attroff(COLOR_PAIR(2) | A_DIM);
    printw("dit ");
    attron(COLOR_PAIR(3) | A_DIM);
    printw("p");
    attroff(COLOR_PAIR(3) | A_DIM);
    printw("rev ");
    attron(COLOR_PAIR(5) | A_DIM);
    printw("s");
    attroff(COLOR_PAIR(5) | A_DIM);
    printw("ort ");
    attron(A_DIM);
    printw("| ");
    attroff(A_DIM);
    attron(COLOR_PAIR(2) | A_DIM);
    printw("a");
    attroff(COLOR_PAIR(2) | A_DIM);
    printw("dd ");
    attron(COLOR_PAIR(1) | A_DIM);
    printw("d");
    attroff(COLOR_PAIR(1) | A_DIM);
    printw("el ");
    attron(COLOR_PAIR(3) | A_DIM);
    printw("u");
    attroff(COLOR_PAIR(3) | A_DIM);
    printw("ndo ");
    attron(A_DIM);
    printw("| ");
    attroff(A_DIM);
    attron(COLOR_PAIR(5) | A_DIM);
    printw("t");
    attroff(COLOR_PAIR(5) | A_DIM);
    printw("heme ");
    attron(COLOR_PAIR(2) | A_DIM);
    printw("h");
    attroff(COLOR_PAIR(2) | A_DIM);
    printw("elp ");
    attron(COLOR_PAIR(1) | A_DIM);
    printw("q");
    attroff(COLOR_PAIR(1) | A_DIM);
    printw("uit");

    if (total > visible && visible > 2) {
        int bar_h = visible - 2;
        int bar_pos = (scroll_offset * bar_h) / total;
        int bar_size = (visible * bar_h) / total;
        if (bar_size < 1) bar_size = 1;
        for (int i = 0; i < bar_h; i++) {
            mvprintw(footer_row - bar_h + i, w - 4, "%s",
                     (i >= bar_pos && i < bar_pos + bar_size) ? " \xe2\x96\x88" : " \xe2\x94\x82");
        }
    }
}

int show_confirm_dialog(const char *title, const char *msg) {
    int mlen = strlen(msg) + 4;
    int w = mlen < 30 ? 30 : (mlen > 60 ? 60 : mlen);
    int h = 7;
    WINDOW *win = create_win(h, w, title);
    if (!win) return 0;
    mvwprintw(win, 2, (w - strlen(msg)) / 2, "%s", msg);
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

/* ── Empty state ── */

static void draw_empty_message(void) {
    int h, w;
    getmaxyx(stdscr, h, w);

    if (filter_key[0]) {
        attron(COLOR_PAIR(3));
        mvprintw(h / 2, w / 2 - 6, " No matching nodes ");
        attroff(COLOR_PAIR(3));
    } else {
        int bw = 30;
        int bx = (w - bw) / 2;
        int by = h / 2 - 3;
        attron(COLOR_PAIR(5));
        mvhline(by, bx, ACS_HLINE, bw);      mvaddch(by, bx - 1, ACS_ULCORNER); mvaddch(by, bx + bw, ACS_URCORNER);
        mvprintw(by + 1, bx, "   No SSH nodes yet      ");
        mvprintw(by + 2, bx, "                           ");
        mvprintw(by + 3, bx, "   Press ");
        attron(COLOR_PAIR(7) | A_BOLD);
        printw("[a]");
        attroff(COLOR_PAIR(7) | A_BOLD);
        printw(" to add node     ");
        mvprintw(by + 4, bx, "   Press ");
        attron(COLOR_PAIR(7) | A_BOLD);
        printw("[i]");
        attroff(COLOR_PAIR(7) | A_BOLD);
        printw(" to import        ");
        mvhline(by + 5, bx, ACS_HLINE, bw);
        mvaddch(by + 5, bx - 1, ACS_LLCORNER); mvaddch(by + 5, bx + bw, ACS_LRCORNER);
        attroff(COLOR_PAIR(5));
    }
}

/* ── Preview ── */

static void preview_node(void) {
    if (selected_idx < 0 || selected_idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[selected_idx];
    if (!n) return;

    int line_count = 10;
    if (n->keypath && n->keypath[0]) line_count++;
    if (n->tags && n->tags[0]) line_count++;
    int h = line_count + 2;
    if (h > 24) h = 24;
    int w = 46;

    WINDOW *win = create_win(h, w, " Node Details ");
    if (!win) return;

    int alive = ping_check(n->host);
    const char *icon = alive ? "\xe2\x97\x8f" : "\xe2\x9c\x97";
    int ac = (strcmp(n->type, "key") == 0);

    mvwprintw(win, 2, 2, "Name    ");
    wattron(win, A_BOLD);
    wprintw(win, "%s", n->name ? n->name : "?");
    wattroff(win, A_BOLD);

    mvwprintw(win, 3, 2, "Group   %s", n->group ? n->group : "");
    mvwprintw(win, 4, 2, "Host    ");
    wattron(win, COLOR_PAIR(2));
    wprintw(win, "%s", n->host ? n->host : "");
    wattroff(win, COLOR_PAIR(2));
    mvwprintw(win, 5, 2, "Port    %d", n->port);
    mvwprintw(win, 6, 2, "User    ");
    wattron(win, COLOR_PAIR(2));
    wprintw(win, "%s", n->user ? n->user : "root");
    wattroff(win, COLOR_PAIR(2));
    mvwprintw(win, 7, 2, "Auth    %s", ac ? "Key" : "Pass");
    int r = 8;
    if (ac && n->keypath && n->keypath[0]) {
        mvwprintw(win, r, 2, "Keypath %s", n->keypath);
        r++;
    }
    if (n->tags && n->tags[0]) {
        mvwprintw(win, r, 2, "Tags    ");
        wattron(win, COLOR_PAIR(5));
        wprintw(win, "%s", n->tags);
        wattroff(win, COLOR_PAIR(5));
        r++;
    }
    wattron(win, COLOR_PAIR(alive ? 2 : 1));
    mvwprintw(win, r, 2, "Status  %s %s", icon, alive ? "Reachable" : "Unreachable");
    wattroff(win, COLOR_PAIR(alive ? 2 : 1));

    wattron(win, COLOR_PAIR(6));
    mvwhline(win, h - 2, 1, ACS_HLINE, w - 2);
    wattroff(win, COLOR_PAIR(6));
    wattron(win, A_DIM);
    mvwprintw(win, h - 1, 2, "Enter=Connect  e=Edit  q=Back");
    wattroff(win, A_DIM);
    wrefresh(win);

    while (1) {
        int c = wgetch(win);
        if (c == '\n' || c == KEY_ENTER) {
            history_record(n->name, n->host);
            def_prog_mode();
            endwin();
            ssh_connect(n);
            refresh();
            break;
        } else if (c == 'e' || c == 'E') {
            close_win(win);
            edit_node_interactive(n->id);
            return;
        } else if (c == 'q' || c == 'Q' || c == 27 || c == ERR) {
            break;
        }
    }
    close_win(win);
    refresh_node_list();
}

/* ── Help ── */

static void show_help(void) {
    int h = 20, w = 54;
    WINDOW *win = create_win(h, w, " Help ");
    if (!win) return;

    const char *help_lines[] = {
        " NAVIGATION",
        "   Up/Down/jk     Select node",
        "   PgUp/PgDn      Scroll page",
        "   Enter          Connect to selected node",
        "   Type text      Real-time filter",
        "   ESC            Clear filter",
        "   Backspace      Delete filter char",
        "",
        " SHORTCUTS",
        "   a  Add node      d  Delete mode    e  Edit node",
        "   p  Preview node  x  Export config  i  Import config",
        "   t  Theme picker  h  Help            q  Quit",
        "",
        " COMMAND LINE",
        "   sshm <keyword>  Direct search & connect",
        "   sshm --help     Show CLI help",
    };
    int total = sizeof(help_lines) / sizeof(help_lines[0]);
    int max_display = h - 3;
    int scroll = 0;

    while (1) {
        werase(win);
        box(win, 0, 0);
        mvwprintw(win, 0, 2, " Help ");
        for (int i = 0; i < max_display && scroll + i < total; i++) {
            const char *line = help_lines[scroll + i];
            int is_header = (strlen(line) > 2 && line[0] == line[2] && line[0] != ' ');
            if (is_header) {
                wattron(win, COLOR_PAIR(5) | A_BOLD);
                mvwprintw(win, 2 + i, 2, "%s", line);
                wattroff(win, COLOR_PAIR(5) | A_BOLD);
            } else {
                mvwprintw(win, 2 + i, 2, "%s", line);
            }
        }
        wattron(win, A_DIM);
        if (total > max_display)
            mvwprintw(win, h - 1, w - 14, " %d/%d  ", scroll + 1, total);
        mvwprintw(win, h - 1, 2, "q/ESC=back");
        wattroff(win, A_DIM);
        wrefresh(win);

        int c = wgetch(win);
        if (c == 'q' || c == 'Q' || c == 27 || c == ERR) break;
        if ((c == KEY_DOWN || c == 'j') && scroll + max_display < total) scroll++;
        if ((c == KEY_UP || c == 'k') && scroll > 0) scroll--;
    }
    close_win(win);
    refresh_node_list();
}

/* ── History ── */

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

/* ── Handlers ── */

static void handle_enter(void) {
    if (selected_idx < 0 || selected_idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[selected_idx];
    if (!n) return;

    if (delete_mode) {
        def_prog_mode();
        endwin();
        delete_node_by_id(n->id);
        refresh();
        delete_mode = 0;
        selected_idx = 0;
        scroll_offset = 0;
        refresh_node_list();
        return;
    }

    history_record(n->name, n->host);

    def_prog_mode();
    endwin();
    ssh_connect(n);

    refresh();
    refresh_node_list();
}

static void handle_connect_number(int num) {
    int idx = num - 1;
    if (idx < 0 || idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[idx];
    if (!n) return;

    history_record(n->name, n->host);

    def_prog_mode();
    endwin();
    ssh_connect(n);
    refresh();
    refresh_node_list();
}

/* ── Init / Main ── */

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
    curs_set(1);
    endwin();
}

int tui_interactive_list(void) {
    int running = 1;
    selected_idx = 0;
    scroll_offset = 0;
    filter_key[0] = '\0';
    sort_mode = 0;
    delete_mode = 0;

    node_list_init(&rendered_nodes);
    refresh_node_list();

    while (running) {
        int h, w;
        getmaxyx(stdscr, h, w);
        int visible_h = h - 5;

        if (selected_idx < scroll_offset) scroll_offset = selected_idx;
        if (rendered_nodes.count > 0 && selected_idx >= scroll_offset + visible_h)
            scroll_offset = selected_idx - visible_h + 1;
        if (scroll_offset < 0) scroll_offset = 0;

        erase();
        draw_header();

        int row = 2;
        int total = rendered_nodes.count;
        for (int i = scroll_offset; i < total && row < h - 3; i++) {
            draw_node(row, i, selected_idx);
            row++;
        }

        if (total == 0)
            draw_empty_message();

        draw_footer(total);

        move(h - 1, w - 1);
        refresh();

        int ch = getch();

        switch (ch) {
            case KEY_UP:
            case 'k':
            case 'K':
                if (selected_idx > 0) selected_idx--;
                break;

            case KEY_DOWN:
            case 'j':
            case 'J':
                if (selected_idx < total - 1) selected_idx++;
                break;

            case KEY_PPAGE: {
                int step = visible_h > 0 ? visible_h : 10;
                selected_idx = selected_idx - step > 0 ? selected_idx - step : 0;
                break;
            }

            case KEY_NPAGE: {
                int step = visible_h > 0 ? visible_h : 10;
                int target = selected_idx + step;
                selected_idx = target < total - 1 ? target : (total > 0 ? total - 1 : 0);
                break;
            }

            case '\n':
            case KEY_ENTER:
                handle_enter();
                break;

            case 27: {
                int next = getch();
                if (next == ERR) {
                    filter_key[0] = '\0';
                    selected_idx = 0;
                    scroll_offset = 0;
                    refresh_node_list();
                } else if (next == '[') {
                    int dir = getch();
                    if (dir == 'A' && selected_idx > 0) selected_idx--;
                    if (dir == 'B' && selected_idx < total - 1) selected_idx++;
                }
                break;
            }

            case KEY_BACKSPACE:
            case 127:
            case '\b':
                if (filter_key[0]) {
                    filter_key[strlen(filter_key) - 1] = '\0';
                    selected_idx = 0;
                    scroll_offset = 0;
                    refresh_node_list();
                }
                break;

            case 'a':
            case 'A':
                add_node_interactive();
                refresh_node_list();
                break;

            case 'd':
            case 'D':
                delete_mode = !delete_mode;
                selected_idx = 0;
                scroll_offset = 0;
                break;

            case 'e':
            case 'E':
                if (selected_idx >= 0 && selected_idx < rendered_nodes.count) {
                    node_t *n = &rendered_nodes.nodes[selected_idx];
                    if (n) {
                        edit_node_interactive(n->id);
                        refresh_node_list();
                    }
                }
                break;

            case 's':
            case 'S':
                sort_mode = (sort_mode + 1) % 3;
                selected_idx = 0;
                scroll_offset = 0;
                refresh_node_list();
                break;

            case 'p':
            case 'P':
                preview_node();
                break;

            case 't':
            case 'T':
                theme_choose_interactive();
                refresh_node_list();
                break;

            case 'u':
            case 'U':
                if (undo_delete() == 0)
                    show_toast(" Node restored ", 2);
                else
                    show_toast(" Nothing to restore ", 3);
                refresh_node_list();
                break;

            case 'x':
            case 'X':
                export_config_interactive();
                break;

            case 'i':
            case 'I':
                import_config_interactive();
                refresh_node_list();
                break;

            case 'h':
            case 'H':
                show_help();
                break;

            case 'r':
            case 'R':
                show_history();
                break;

            case 'q':
            case 'Q':
                running = 0;
                break;

            case 'g':
                selected_idx = 0;
                scroll_offset = 0;
                break;

            case 'G':
                if (total > 0) {
                    selected_idx = total - 1;
                    scroll_offset = selected_idx - visible_h + 1;
                    if (scroll_offset < 0) scroll_offset = 0;
                }
                break;

            default:
                if (ch >= '1' && ch <= '9') {
                    handle_connect_number(ch - '0');
                } else if (ch >= 32 && ch <= 126) {
                    size_t flen = strlen(filter_key);
                    if (flen < sizeof(filter_key) - 1) {
                        filter_key[flen] = tolower(ch);
                        filter_key[flen + 1] = '\0';
                        selected_idx = 0;
                        scroll_offset = 0;
                        refresh_node_list();
                    }
                }
                break;
        }
    }

    node_list_free(&rendered_nodes);
    tui_end();
    return 0;
}
