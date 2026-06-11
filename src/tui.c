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
#include <termios.h>
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

static void leave_curses(void) {
    def_prog_mode();
    endwin();
    /* Reset terminal to sane cooked mode (onlcr, echo, icanon) */
    struct termios t;
    if (tcgetattr(STDIN_FILENO, &t) == 0) {
        t.c_lflag |= (ECHO | ICANON | ISIG);
        t.c_oflag |= (OPOST | ONLCR);
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
    }
}

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
    getmaxyx(stdscr, h, h);  /* suppress unused warning for width */
    return h - 5;
}

static void draw_header(void) {
    int w;
    getmaxyx(stdscr, w, w);

    int name_w = (w > 100) ? 24 : 16;
    int host_w = (w > 100) ? 26 : 21;

    /* Title bar with background */
    attron(COLOR_PAIR(6));
    mvhline(0, 0, ' ', w);
    mvprintw(0, 0, "  SSH Manager v0.5.3");
    if (filter_key[0]) {
        printw("  过滤: %s", filter_key);
    }
    const char *sort_labels[] = {"组", "名", "状态"};
    printw("  排序:%s", sort_labels[sort_mode % 3]);
    attroff(COLOR_PAIR(6));

    /* Column headers */
    attron(COLOR_PAIR(5) | A_BOLD);
    int col = 0;
    mvprintw(1, col, "%-6s", "S"); col += 6;
    mvprintw(1, col, " │ "); col += 3;
    mvprintw(1, col, "%-4s", "ID"); col += 4;
    mvprintw(1, col, " │ "); col += 3;
    mvprintw(1, col, "%-12s", "Group"); col += 12;
    mvprintw(1, col, " │ "); col += 3;
    mvprintw(1, col, "%-*s", name_w, "Name"); col += name_w;
    mvprintw(1, col, " │ "); col += 3;
    mvprintw(1, col, "%-*s", host_w, "Host:Port"); col += host_w;
    mvprintw(1, col, " │ "); col += 3;
    mvprintw(1, col, "%-5s", "Auth");
    attroff(COLOR_PAIR(5) | A_BOLD);
}

static void draw_node(int row, int idx, int selected, int highlight) {
    (void)highlight;
    if (idx < 0 || idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[idx];
    int w;
    getmaxyx(stdscr, w, w);

    int id_display = idx + 1;
    int name_w = (w > 100) ? 24 : 16;
    int host_w = (w > 100) ? 26 : 21;

    int alive;
    if (idx == selected) {
        alive = ping_check(n->host);
    } else {
        int c = ping_cached(n->host);
        alive = (c == -1) ? -1 : c;
    }
    char alive_ch = (alive == 1) ? 'O' : (alive == 0 ? 'X' : '?');
    int alive_color = (alive == 1) ? 2 : ((alive == 0) ? 1 : 3);

    char sel_mark = (idx == selected) ? '>' : ' ';

    attron(COLOR_PAIR(alive_color));
    char st_str[16];
    snprintf(st_str, sizeof(st_str), "%c %c", sel_mark, alive_ch);
    attroff(COLOR_PAIR(alive_color));

    char id_str[16];
    snprintf(id_str, sizeof(id_str), "%d", id_display);

    int col = 0;
    if (idx == selected) {
        attron(A_REVERSE);
    } else if (idx % 2 == 0) {
        attron(A_DIM);
    }

    /* Status column (6 chars) */
    mvprintw(row, col, "%-6s", st_str); col += 6;
    mvprintw(row, col, " | "); col += 3;

    /* ID column (4 chars) */
    mvprintw(row, col, "%-4s", id_str); col += 4;
    mvprintw(row, col, " | "); col += 3;

    /* Group column (12 chars) */
    mvprintw(row, col, "%-12s", n->group ? n->group : ""); col += 12;
    mvprintw(row, col, " | "); col += 3;

    /* Name column with highlight */
    char *match_pos = NULL;
    if (filter_key[0] && n->name)
        match_pos = strcasestr(n->name, filter_key);

    if (match_pos) {
        int prefix_len = (int)(match_pos - n->name);
        int match_len = (int)strlen(filter_key);
        mvprintw(row, col, "%-*s", name_w, "");  /* clear column */
        mvprintw(row, col, "%.*s", prefix_len, n->name);
        col += prefix_len;
        attron(A_REVERSE);
        printw("%.*s", match_len, match_pos);
        attroff(A_REVERSE);
        col += match_len;
        if (name_w - prefix_len - match_len > 0)
            printw("%-*s", name_w - prefix_len - match_len, match_pos + match_len);
    } else {
        mvprintw(row, col, "%-*s", name_w, n->name ? n->name : "");
    }
    col += name_w;
    mvprintw(row, col, " | "); col += 3;

    /* Host:Port column */
    char hostport[128];
    snprintf(hostport, sizeof(hostport), "%s:%d", n->host ? n->host : "?", n->port);

    /* Check host:port for match */
    match_pos = NULL;
    if (filter_key[0]) {
        char *hp_match = strcasestr(hostport, filter_key);
        if (!hp_match && n->host)
            hp_match = strcasestr(n->host, filter_key);
        match_pos = hp_match ? strcasestr(hostport, filter_key) : NULL;
    }

    if (match_pos) {
        int prefix_len = (int)(match_pos - hostport);
        int match_len = (int)strlen(filter_key);
        mvprintw(row, col, "%-*s", host_w, "");
        mvprintw(row, col, "%.*s", prefix_len, hostport);
        attron(A_REVERSE);
        printw("%.*s", match_len, match_pos);
        attroff(A_REVERSE);
        if (host_w - prefix_len - match_len > 0)
            printw("%-*s", host_w - prefix_len - match_len, match_pos + match_len);
    } else {
        mvprintw(row, col, "%-*s", host_w, hostport);
    }
    col += host_w;
    mvprintw(row, col, " | "); col += 3;

    /* Auth column (5 chars) */
    mvprintw(row, col, "%-5s", n->type ? n->type : "");

    if (idx == selected) {
        attroff(A_REVERSE);
    } else if (idx % 2 == 0) {
        attroff(A_DIM);
    }

    /* Tags suffix */
    if (n->tags && n->tags[0]) {
        attron(COLOR_PAIR(5));
        printw(" [%s]", n->tags);
        attroff(COLOR_PAIR(5));
    }
}

static void draw_footer(int total) {
    int h, w;
    getmaxyx(stdscr, h, w);

    int footer_row = h - 2;
    int visible = get_visible_height();

    /* Separator line above status */
    attron(COLOR_PAIR(5));
    mvhline(footer_row - 1, 0, ACS_HLINE, w);
    attroff(COLOR_PAIR(5));

    /* Status bar */
    if (delete_mode) {
        attron(COLOR_PAIR(1) | A_BOLD);
        mvprintw(footer_row, 0, " [删除模式] ");
        attroff(COLOR_PAIR(1) | A_BOLD);
    } else {
        mvprintw(footer_row, 0, " ");
    }

    attron(COLOR_PAIR(5));
    printw("%d个", total);
    attroff(COLOR_PAIR(5));

    if (total > 0 && selected_idx < rendered_nodes.count) {
        node_t *n = &rendered_nodes.nodes[selected_idx];
        if (n) {
            printw("  ");
            attron(COLOR_PAIR(4) | A_BOLD);
            printw("%s", n->name ? n->name : "?");
            attroff(COLOR_PAIR(4) | A_BOLD);
            int host_up = ping_check(n->host);
            attron(host_up ? COLOR_PAIR(2) : COLOR_PAIR(1));
            printw("@%s", n->host ? n->host : "?");
            attroff(host_up ? COLOR_PAIR(2) : COLOR_PAIR(1));
        }
    }

    /* Right-aligned scroll info */
    if (total > visible) {
        int pct = (scroll_offset + visible) * 100 / total;
        if (pct > 100) pct = 100;
        attron(COLOR_PAIR(5));
        mvprintw(footer_row, w - 12, " %d%% ", pct);
        attroff(COLOR_PAIR(5));
    }

    /* Help bar */
    mvprintw(footer_row + 1, 0, "↑↓/jk选 PgUp/Dn翻页 1-9快连 Enter连 | e编 p预览 s排 | a加 d删 u撤 | x导出 t主题 h帮助 q退");

    /* Scrollbar */
    if (total > visible && visible > 2) {
        int bar_h = visible - 2;
        int bar_pos = (scroll_offset * bar_h) / total;
        int bar_size = (visible * bar_h) / total;
        if (bar_size < 1) bar_size = 1;

        for (int i = 0; i < bar_h; i++) {
            mvprintw(footer_row - bar_h + i, w - 3, " %s",
                     (i >= bar_pos && i < bar_pos + bar_size) ? "█" : "│");
        }
    }
}

static void draw_empty_message(void) {
    int h, w;
    getmaxyx(stdscr, h, w);

    if (filter_key[0]) {
        attron(COLOR_PAIR(3));
        mvprintw(h / 2, w / 2 - 6, " 无匹配节点 ");
        attroff(COLOR_PAIR(3));
    } else {
        const char *lines[] = {
            " ┌─────────────────────┐",
            " │  暂无 SSH 节点      │",
            " │                     │",
            " │  按  a  添加节点    │",
            " │  按  i  从文件导入  │",
            " └─────────────────────┘",
        };
        int n = sizeof(lines) / sizeof(lines[0]);
        int start_row = h / 2 - n / 2;
        int start_col = w / 2 - 12;
        attron(COLOR_PAIR(5));
        for (int i = 0; i < n; i++)
            mvprintw(start_row + i, start_col, "%s", lines[i]);
        attroff(COLOR_PAIR(5));
    }
}

static void handle_enter(void) {
    if (selected_idx < 0 || selected_idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[selected_idx];
    if (!n) return;

    if (delete_mode) {
        leave_curses();
        delete_node_by_id(n->id);
        refresh();
        delete_mode = 0;
        selected_idx = 0;
        scroll_offset = 0;
        refresh_node_list();
        return;
    }

    history_record(n->name, n->host);

    leave_curses();
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

    leave_curses();
    ssh_connect(n);
    refresh();
    refresh_node_list();
}

static void preview_node(void) {
    if (selected_idx < 0 || selected_idx >= rendered_nodes.count) return;
    node_t *n = &rendered_nodes.nodes[selected_idx];
    if (!n) return;

    leave_curses();

    printf("\033[H\033[J");
    printf("\n%s==== 节点详情 ====%s\n\n", ANSI_CYAN, ANSI_RESET);
    printf("  名称: %s%s%s\n", ANSI_YELLOW, n->name ? n->name : "?", ANSI_RESET);
    printf("  分组: %s%s%s\n", ANSI_YELLOW, n->group ? n->group : "", ANSI_RESET);
    printf("  主机: %s%s%s\n", ANSI_GREEN, n->host ? n->host : "", ANSI_RESET);
    printf("  端口: %s%d%s\n", ANSI_GREEN, n->port, ANSI_RESET);
    printf("  用户: %s%s%s\n", ANSI_GREEN, n->user ? n->user : "root", ANSI_RESET);
    printf("  认证: %s%s%s\n", ANSI_YELLOW,
           (strcmp(n->type, "key") == 0) ? "密钥" : "密码", ANSI_RESET);
    if (n->keypath && n->keypath[0])
        printf("  私钥: %s%s%s\n", ANSI_YELLOW, n->keypath, ANSI_RESET);
    if (n->tags && n->tags[0])
        printf("  标签: %s%s%s\n", ANSI_YELLOW, n->tags, ANSI_RESET);

    printf("\n  状态: %s\n", ping_check(n->host) ? "可达" : "不可达");

    printf("\n  %sEnter%s=连接  %se%s=编辑  其他键=返回\n",
           ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET);
    fflush(stdout);

    int c = getchar();
    if (c == '\n') {
        ssh_connect(n);
    } else if (c == 'e' || c == 'E') {
        edit_node_interactive(n->id);
    }
    refresh_node_list();
}

static void show_help(void) {
    leave_curses();

    printf("\033[H\033[J");
    printf("\n%s==== SSH MANAGER 帮助 ====%s\n", ANSI_CYAN, ANSI_RESET);
    printf("\n%s列表导航:%s\n", ANSI_GREEN, ANSI_RESET);
    printf("  %s↑↓/jk%s   - 选择节点, 当前行高亮\n", ANSI_BLUE, ANSI_RESET);
    printf("  %sPgUp/PgDn%s - 翻页滚动\n", ANSI_BLUE, ANSI_RESET);
    printf("  %sEnter%s     - 连接到选中节点\n", ANSI_BLUE, ANSI_RESET);
    printf("  %s输入文字%s  - 实时过滤节点列表\n", ANSI_BLUE, ANSI_RESET);
    printf("  %sESC%s       - 清除过滤条件\n", ANSI_BLUE, ANSI_RESET);
    printf("  %s退格%s      - 删除最后一个过滤字符\n", ANSI_BLUE, ANSI_RESET);
    printf("\n%s快捷键:%s\n", ANSI_GREEN, ANSI_RESET);
    printf("  %sa%s - 添加节点   %sd%s - 删除模式   %se%s - 编辑节点\n",
           ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET);
    printf("  %sp%s - 预览详情   %sx%s - 导出配置   %si%s - 导入\n",
           ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET);
    printf("  %st%s - 主题切换   %sh%s - 帮助       %sq%s - 退出\n",
           ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET, ANSI_BLUE, ANSI_RESET);
    printf("\n%s命令行:%s\n", ANSI_GREEN, ANSI_RESET);
    printf("  sshm prod         - 直接搜索并连接匹配节点\n");
    printf("  sshm --config <f>  - 使用指定配置文件\n");
    printf("  sshm --help        - 显示此帮助\n");
    printf("\n按任意键返回...");
    fflush(stdout);
    getchar();
    refresh_node_list();
}

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
    }

    /* Ensure config is loaded */
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

        /* Auto-scroll */
        if (selected_idx < scroll_offset) scroll_offset = selected_idx;
        if (rendered_nodes.count > 0 && selected_idx >= scroll_offset + visible_h)
            scroll_offset = selected_idx - visible_h + 1;
        if (scroll_offset < 0) scroll_offset = 0;

        /* Redraw */
        erase();
        draw_header();

        int row = 2;
        int total = rendered_nodes.count;
        for (int i = scroll_offset; i < total && row < h - 3; i++) {
            draw_node(row, i, selected_idx, delete_mode ? 2 : 1);
            row++;
        }

        if (total == 0) {
            draw_empty_message();
        }

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
                int target = selected_idx - step;
                selected_idx = target > 0 ? target : 0;
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

            case 27: { /* ESC */
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
                leave_curses();
                add_node_interactive();
                refresh();
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
                        leave_curses();
                        edit_node_interactive(n->id);
                        refresh();
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
                leave_curses();
                theme_choose_interactive();
                refresh();
                refresh_node_list();
                break;

            case 'u':
            case 'U':
                leave_curses();
                undo_delete();
                refresh();
                refresh_node_list();
                break;

            case 'x':
            case 'X':
                leave_curses();
                export_config_interactive();
                refresh();
                break;

            case 'i':
            case 'I':
                leave_curses();
                import_config_interactive();
                refresh();
                refresh_node_list();
                break;

            case 'h':
            case 'H':
                show_help();
                break;

            case 'r':
            case 'R': {
                leave_curses();
                int cnt;
                history_entry_t *entries = history_get_recent(&cnt);
                printf("\033[H\033[J");
                printf("%s==== 最近连接 ====%s\n", ANSI_CYAN, ANSI_RESET);
                printf("\n");
                for (int i = 0; i < cnt; i++) {
                    struct tm *tm = localtime(&entries[i].timestamp);
                    char timebuf[32];
                    strftime(timebuf, sizeof(timebuf), "%m-%d %H:%M", tm);
    char name_buf[17], host_buf[23];
    strncpy(name_buf, entries[i].name ? entries[i].name : "", 16);
    name_buf[16] = '\0';
    strncpy(host_buf, entries[i].host ? entries[i].host : "", 22);
    host_buf[22] = '\0';
    printf("  %2d. %-16s %-22s %s\n", i + 1, name_buf, host_buf, timebuf);
                    history_entry_free(&entries[i]);
                }
                free(entries);
                printf("\n按任意键返回...");
                fflush(stdout);
                getchar();
                refresh();
                break;
            }

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
