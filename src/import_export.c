#include "import_export.h"
#include "config.h"
#include "yaml_parser.h"
#include "tui.h"
#include "util.h"
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char *read_line_win(WINDOW *win, int y, int x, int max_len) {
    char *buf = calloc(max_len + 1, 1);
    if (!buf) return NULL;
    int pos = 0;
    curs_set(1);
    while (1) {
        wmove(win, y, x + pos);
        wrefresh(win);
        int c = wgetch(win);
        if (c == '\n' || c == KEY_ENTER) {
            break;
        } else if ((c == KEY_BACKSPACE || c == 127 || c == '\b') && pos > 0) {
            pos--;
            buf[pos] = '\0';
            mvwprintw(win, y, x, "%-*s", max_len, "");
            mvwprintw(win, y, x, "%s", buf);
        } else if (c >= 32 && c <= 126 && pos < max_len) {
            buf[pos++] = c;
            buf[pos] = '\0';
            mvwprintw(win, y, x, "%s", buf);
        } else if (c == 27 || c == ERR) {
            free(buf);
            curs_set(0);
            return NULL;
        }
    }
    curs_set(0);
    return buf;
}

int export_config_interactive(void) {
    if (!g_config_path) {
        show_toast(" Config not initialized ", 1);
        return -1;
    }

    int h = 8, w = 44;
    WINDOW *win = create_win(h, w, " Export Config ");
    if (!win) return -1;

    mvwprintw(win, 2, 2, "1. Base64 to screen (shareable)");
    mvwprintw(win, 3, 2, "2. Save to file (backup)");
    wattron(win, A_DIM);
    mvwprintw(win, h - 1, 2, "1/2 select  q cancel");
    wattroff(win, A_DIM);
    wrefresh(win);

    int ch = wgetch(win);
    close_win(win);

    if (ch == '1') {
        if (!show_confirm_dialog(" Export Base64 ",
                                 "Warning: contains sensitive data!")) {
            return 0;
        }
        show_toast(" Exporting Base64... ", 5);

        char cmd[4096];
        snprintf(cmd, sizeof(cmd), "base64 < \"%s\" 2>/dev/null", g_config_path);

        def_prog_mode();
        endwin();
        printf("\n--- Base64 Config ---\n");
        fflush(stdout);
        int ret = system(cmd);
        printf("\n--------------------\nPress Enter to continue...");
        fflush(stdout);
        getchar();
        refresh();

        show_toast(ret == 0 ? " Export done " : " Export failed ", ret == 0 ? 2 : 1);
        return ret;
    } else if (ch == '2') {
        WINDOW *pwin = create_win(7, 50, " Export Path ");
        if (!pwin) return -1;
        mvwprintw(pwin, 2, 2, "Path (default: ./ssh-manager-config.yaml):");
        wrefresh(pwin);

        char *path = read_line_win(pwin, 3, 2, 40);
        if (!path) { close_win(pwin); return -1; }
        if (path[0] == '\0') {
            free(path);
            path = strdup("./ssh-manager-config.yaml");
        }
        close_win(pwin);

        char cmd[8192];
        snprintf(cmd, sizeof(cmd), "cp \"%s\" \"%s\" && chmod 600 \"%s\" 2>/dev/null",
                 g_config_path, path, path);
        int ret = system(cmd);
        show_toast(ret == 0 ? " Config exported " : " Export failed ",
                   ret == 0 ? 2 : 1);
        free(path);
        return ret;
    }
    return 0;
}

int import_config_interactive(void) {
    int h = 8, w = 44;
    WINDOW *win = create_win(h, w, " Import Config ");
    if (!win) return -1;

    mvwprintw(win, 2, 2, "1. From Base64 string (clipboard)");
    mvwprintw(win, 3, 2, "2. From file (backup)");
    wattron(win, A_DIM);
    mvwprintw(win, h - 1, 2, "1/2 select  q cancel");
    wattroff(win, A_DIM);
    wrefresh(win);

    int ch = wgetch(win);
    close_win(win);

    if (ch == '1') {
        if (!show_confirm_dialog(" Import Base64 ",
                                 "This will OVERWRITE current config!")) {
            return 0;
        }

        WINDOW *pwin = create_win(7, 50, " Paste Base64 ");
        if (!pwin) return -1;
        mvwprintw(pwin, 2, 2, "Paste Base64 string:");
        wrefresh(pwin);
        char *b64 = read_line_win(pwin, 3, 2, 40);
        close_win(pwin);
        if (!b64 || !b64[0]) {
            show_toast(" Empty input ", 3);
            free(b64);
            return -1;
        }

        config_backup();
        char cmd[131072];
        snprintf(cmd, sizeof(cmd), "echo '%s' | tr -d '[:space:]' | base64 -d > \"%s\" 2>/dev/null",
                 b64, g_config_path);
        free(b64);
        int ret = system(cmd);
        if (ret == 0) {
            config_setup_permissions();
            config_update_mtime();
            show_toast(" Config imported ", 2);
        } else {
            show_toast(" Invalid Base64 ", 1);
        }
        return ret;
    } else if (ch == '2') {
        if (!show_confirm_dialog(" Import File ",
                                 "This will OVERWRITE current config!")) {
            return 0;
        }

        WINDOW *pwin = create_win(7, 50, " File Path ");
        if (!pwin) return -1;
        mvwprintw(pwin, 2, 2, "Path to config file:");
        wrefresh(pwin);
        char *path = read_line_win(pwin, 3, 2, 40);
        close_win(pwin);
        if (!path || !path[0]) {
            show_toast(" No path entered ", 3);
            free(path);
            return -1;
        }

        if (access(path, R_OK) != 0) {
            show_toast(" File not found ", 1);
            free(path);
            return -1;
        }

        FILE *tf = fopen(path, "r");
        int has_nodes = 0;
        if (tf) {
            char buf[256];
            while (fgets(buf, sizeof(buf), tf)) {
                if (strstr(buf, "nodes:")) { has_nodes = 1; break; }
            }
            fclose(tf);
        }
        if (!has_nodes) {
            show_toast(" Not a valid config file ", 1);
            free(path);
            return -1;
        }

        config_backup();
        char cmd[8192];
        snprintf(cmd, sizeof(cmd), "cp \"%s\" \"%s\" && chmod 600 \"%s\" 2>/dev/null",
                 path, g_config_path, g_config_path);
        free(path);
        int ret = system(cmd);
        if (ret == 0) {
            config_update_mtime();
            show_toast(" Config imported ", 2);
        } else {
            show_toast(" Import failed ", 1);
        }
        return ret;
    }
    return 0;
}

int export_ssh_config(void) {
    node_list_t list;
    if (get_all_nodes(g_config_path, NULL, &list) < 0) {
        printf("Failed to parse config\n");
        return -1;
    }

    printf("# Generated by ssh-manager\n");
    for (int i = 0; i < list.count; i++) {
        node_t *n = &list.nodes[i];
        if (!n->host || !n->name) continue;
        printf("\n");
        printf("Host %s\n", n->name);
        printf("    HostName %s\n", n->host);
        printf("    Port %d\n", n->port);
        if (n->group && strcmp(n->group, "Default") != 0) {
            printf("    # Group: %s\n", n->group);
        }
    }
    node_list_free(&list);
    return 0;
}
