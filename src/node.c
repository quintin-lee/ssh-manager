#include "node.h"
#include "config.h"
#include "tui.h"
#include "util.h"
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>

char *sanitize_yaml_value(const char *val) {
    if (!val || val[0] == '\0') return strdup("\"\"");
    int need_quote = 0;
    if (strchr(val, ':') || strchr(val, '#') || strchr(val, '"') || strchr(val, '\\'))
        need_quote = 1;
    if (val[0] == ' ' || val[strlen(val)-1] == ' ')
        need_quote = 1;
    if (!need_quote) return strdup(val);
    size_t len = strlen(val);
    size_t cap = len * 2 + 3;
    char *out = malloc(cap);
    if (!out) return NULL;
    size_t j = 0;
    out[j++] = '"';
    for (size_t i = 0; i < len; i++) {
        if (val[i] == '\\') out[j++] = '\\';
        if (val[i] == '"') out[j++] = '\\';
        out[j++] = val[i];
    }
    out[j++] = '"';
    out[j] = '\0';
    return out;
}

static int write_node_yaml(FILE *f, const node_t *n) {
    char *s_name = sanitize_yaml_value(n->name ? n->name : "");
    char *s_group = sanitize_yaml_value(n->group ? n->group : "");
    char *s_host = sanitize_yaml_value(n->host ? n->host : "");
    char *s_user = sanitize_yaml_value(n->user ? n->user : "");
    char *s_pass = sanitize_yaml_value(n->pass ? n->pass : "");
    char *s_keypath = sanitize_yaml_value(n->keypath ? n->keypath : "");
    char *s_tags = sanitize_yaml_value(n->tags ? n->tags : "");
    fprintf(f, "  - name: %s\n", s_name);
    fprintf(f, "    group: %s\n", s_group);
    fprintf(f, "    host: %s\n", s_host);
    fprintf(f, "    port: %d\n", n->port);
    fprintf(f, "    user: %s\n", s_user);
    fprintf(f, "    type: %s\n", n->type ? n->type : "pass");
    fprintf(f, "    pass: %s\n", s_pass);
    fprintf(f, "    keypath: %s\n", s_keypath);
    fprintf(f, "    tags: %s\n", s_tags);
    free(s_name); free(s_group); free(s_host);
    free(s_user); free(s_pass); free(s_keypath); free(s_tags);
    return 0;
}

static char *read_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    char *buf = malloc(len + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t n = fread(buf, 1, len, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

static int validate_host(const char *host) {
    if (!host || host[0] == '\0') return 0;
    const char *illegal = " ;|&$`(){}<>\"\'";
    for (const char *p = host; *p; p++) {
        if (strchr(illegal, *p)) return 0;
    }
    return 1;
}

static int validate_port(const char *s) {
    if (!s || s[0] == '\0') return 0;
    for (const char *p = s; *p; p++) {
        if (!isdigit((unsigned char)*p)) return 0;
    }
    int port = atoi(s);
    return (port >= 1 && port <= 65535);
}

static int validate_ssh_key(const char *path) {
    if (!path || path[0] == '\0') return 0;
    if (access(path, R_OK) != 0) return 0;
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char buf[256];
    int is_key = 0;
    while (fgets(buf, sizeof(buf), f)) {
        if (strstr(buf, "PRIVATE KEY")) { is_key = 1; break; }
    }
    fclose(f);
    return is_key;
}

char *_deleted_yaml = NULL;

/* ── ncurses form helpers ── */

static char *edit_field_win(WINDOW *win, int y, int x, int max_w,
                            const char *initial, int hidden) {
    int len = initial ? strlen(initial) : 0;
    int cap = max_w + 1;
    char *buf = calloc(cap, 1);
    if (!buf) return NULL;
    if (initial) strncpy(buf, initial, max_w);

    int pos = len;
    curs_set(1);
    while (1) {
        wmove(win, y, x + pos);
        wrefresh(win);
        int c = wgetch(win);
        if (c == '\n' || c == KEY_ENTER) {
            curs_set(0);
            return buf;
        }
        if ((c == KEY_BACKSPACE || c == 127 || c == '\b') && pos > 0) {
            pos--;
            buf[pos] = '\0';
            mvwprintw(win, y, x, "%-*s", max_w, "");
            if (hidden)
                mvwprintw(win, y, x, "%-*s", pos, "");
            else
                mvwprintw(win, y, x, "%s", buf);
        } else if (c >= 32 && c <= 126 && pos < max_w) {
            buf[pos++] = c;
            buf[pos] = '\0';
            if (hidden) {
                mvwprintw(win, y, x, "%-*s", pos, "");
                for (int i = 0; i < pos; i++)
                    mvwaddch(win, y, x + i, '*');
            } else {
                mvwprintw(win, y, x, "%s", buf);
            }
        } else if (c == 27 || c == ERR) {
            curs_set(0);
            free(buf);
            return NULL;
        }
    }
}

static void draw_form(WINDOW *win, const node_t *n, int edit_field) {
    int is_key = (strcmp(n->type, "key") == 0);
    const char *pass_display = (n->pass && n->pass[0]) ? "****" : "(not set)";
    const char *aclabel = is_key ? "Key" : "Pass";
    int y = 2;

    for (int i = 1; i <= 9; i++) {
        int is_editing = (i == edit_field);
        int row = y + i - 1;

        if (is_editing) {
            wattron(win, COLOR_PAIR(7) | A_BOLD);
            mvwprintw(win, row, 2, "[%d]", i);
            wattroff(win, COLOR_PAIR(7) | A_BOLD);
        } else {
            mvwprintw(win, row, 2, "[%d]", i);
        }

        switch (i) {
            case 1: mvwprintw(win, row, 7, "Name   %s", n->name && n->name[0] ? n->name : "(not set)"); break;
            case 2: mvwprintw(win, row, 7, "Group  %s", n->group ? n->group : ""); break;
            case 3: mvwprintw(win, row, 7, "Host   %s", n->host && n->host[0] ? n->host : "(required)"); break;
            case 4: mvwprintw(win, row, 7, "Port   %d", n->port); break;
            case 5: mvwprintw(win, row, 7, "User   %s", n->user ? n->user : "root"); break;
            case 6:
                mvwprintw(win, row, 7, "Auth   ");
                if (is_key) {
                    wattron(win, A_DIM);
                    wprintw(win, "[Pass]");
                    wattroff(win, A_DIM);
                    wattron(win, A_BOLD);
                    wprintw(win, " [Key]");
                    wattroff(win, A_BOLD);
                } else {
                    wattron(win, A_BOLD);
                    wprintw(win, "[Pass]");
                    wattroff(win, A_BOLD);
                    wattron(win, A_DIM);
                    wprintw(win, " [Key]");
                    wattroff(win, A_DIM);
                }
                break;
            case 7:
                if (is_key)
                    mvwprintw(win, row, 7, "Keypath %s", n->keypath && n->keypath[0] ? n->keypath : "(required)");
                else
                    mvwprintw(win, row, 7, "Passwd  %s", pass_display);
                break;
            case 8:
                if (is_key)
                    mvwprintw(win, row, 7, "Phrase  %s", pass_display);
                else
                    mvwprintw(win, row, 7, "Tags    %s", n->tags && n->tags[0] ? n->tags : "(none)");
                break;
            case 9:
                if (is_key)
                    mvwprintw(win, row, 7, "Tags    %s", n->tags && n->tags[0] ? n->tags : "(none)");
                break;
        }
    }

    int h, ww;
    getmaxyx(win, h, ww);
    mvwprintw(win, h - 2, 2, "Enter=save  1-9=edit  q=back");

    if (edit_field > 0) {
        mvwprintw(win, h - 2, 2, "Editing field %d ... Enter=done  ESC=cancel", edit_field);
    }
}

static int form_interactive(node_t *n, const char *title) {
    int h = 16, w = 48;
    int edit_field = 0;

    while (1) {
        WINDOW *win = create_win(h, w, title);
        if (!win) return -1;
        draw_form(win, n, edit_field);

        int save_ready = (n->name && n->name[0] && n->host && n->host[0]);

        if (edit_field > 0) {
            mvwprintw(win, h - 2, 2, "Editing field %d ... Enter=done  ESC=cancel", edit_field);
        } else if (save_ready) {
            int is_key = (strcmp(n->type, "key") == 0);
            if (!is_key || (n->keypath && n->keypath[0]))
                mvwprintw(win, h - 2, 2, "Enter=save  1-9=edit  q=back");
            else
                mvwprintw(win, h - 2, 2, "Fill required fields  1-9=edit  q=back");
        } else {
            mvwprintw(win, h - 2, 2, "Fill required fields  1-9=edit  q=back");
        }

        wrefresh(win);

        int ch = wgetch(win);

        if (edit_field == 0) {
            if (ch == '\n' || ch == KEY_ENTER) {
                int is_key = (strcmp(n->type, "key") == 0);
                if (save_ready && (!is_key || (n->keypath && n->keypath[0]))) {
                    close_win(win);
                    return 0;
                }
                close_win(win);
                continue;
            }
            if (ch == 'q' || ch == 'Q' || ch == 27 || ch == ERR) {
                close_win(win);
                return -1;
            }
            if (ch >= '1' && ch <= '9') {
                int max_field = (strcmp(n->type, "key") == 0) ? 9 : 8;
                if (ch - '0' <= max_field) {
                    edit_field = ch - '0';
                    close_win(win);
                    continue;
                }
            }
            /* left/right for auth toggle */
            if ((ch == KEY_LEFT || ch == KEY_RIGHT) && (ch == KEY_LEFT || ch == 260 || ch == 261)) {
                int is_key = (strcmp(n->type, "key") == 0);
                free(n->type);
                n->type = strdup(is_key ? "pass" : "key");
                close_win(win);
                continue;
            }
            close_win(win);
        } else {
            /* In edit mode for a specific field */
            int is_key = (strcmp(n->type, "key") == 0);
            int input_x = 16;
            int max_w = w - input_x - 4;

            switch (edit_field) {
                case 1: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    char *result = edit_field_win(win, 2, input_x, max_w, n->name, 0);
                    if (result) { free(n->name); n->name = result; }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 2: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    char *result = edit_field_win(win, 3, input_x, max_w, n->group, 0);
                    if (result) { free(n->group); n->group = result[0] ? result : strdup("Default"); if (result[0]) free(result); }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 3: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    wattron(win, COLOR_PAIR(1));
                    mvwprintw(win, h - 2, 2, "Hostname (no spaces/shell chars)");
                    wattroff(win, COLOR_PAIR(1));
                    wrefresh(win);
                    char *result = edit_field_win(win, 4, input_x, max_w, n->host, 0);
                    if (result) {
                        if (validate_host(result)) {
                            free(n->host); n->host = result;
                        } else {
                            show_toast(" Invalid hostname ", 1);
                            free(result);
                        }
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 4: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    char port_str[16];
                    snprintf(port_str, sizeof(port_str), "%d", n->port);
                    char *result = edit_field_win(win, 5, input_x, 8, port_str, 0);
                    if (result) {
                        if (validate_port(result))
                            n->port = atoi(result);
                        else
                            show_toast(" Invalid port (1-65535) ", 1);
                        free(result);
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 5: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    char *result = edit_field_win(win, 6, input_x, max_w, n->user, 0);
                    if (result) {
                        if (validate_host(result))
                            { free(n->user); n->user = result; }
                        else
                            { show_toast(" Invalid username ", 1); free(result); }
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 6: {
                    /* Toggle auth type */
                    free(n->type);
                    n->type = strdup(is_key ? "pass" : "key");
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 7: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    if (is_key) {
                        wattron(win, COLOR_PAIR(1));
                        mvwprintw(win, h - 2, 2, "Path to SSH private key file     ");
                        wattroff(win, COLOR_PAIR(1));
                        wrefresh(win);
                        char *result = edit_field_win(win, 8, input_x, max_w, n->keypath, 0);
                        if (result) {
                            if (validate_ssh_key(result))
                                { free(n->keypath); n->keypath = result; }
                            else
                                { show_toast(" Invalid SSH key ", 1); free(result); }
                        }
                    } else {
                        char *result = edit_field_win(win, 8, input_x, max_w, n->pass, 1);
                        if (result) { free(n->pass); n->pass = result; }
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 8: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    if (is_key) {
                        char *result = edit_field_win(win, 9, input_x, max_w, n->pass, 1);
                        if (result) { free(n->pass); n->pass = result; }
                    } else {
                        char *result = edit_field_win(win, 9, input_x, max_w, n->tags, 0);
                        if (result) { free(n->tags); n->tags = result; }
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
                case 9: {
                    if (ch == 27 || ch == ERR) { edit_field = 0; close_win(win); continue; }
                    if (is_key) {
                        char *result = edit_field_win(win, 10, input_x, max_w, n->tags, 0);
                        if (result) { free(n->tags); n->tags = result; }
                    }
                    edit_field = 0;
                    close_win(win);
                    continue;
                }
            }
            close_win(win);
        }
    }
}

int add_node_interactive(void) {
    node_t n;
    node_init(&n);
    n.name = strdup("");
    n.host = strdup("");
    n.group = strdup("Default");
    n.port = 22;
    n.user = strdup("root");
    n.type = strdup("pass");

    int ret = form_interactive(&n, " Add Node ");
    if (ret != 0) {
        node_free(&n);
        return -1;
    }

    config_backup();

    char *s_name = sanitize_yaml_value(n.name ? n.name : "");
    char *s_group = sanitize_yaml_value(n.group ? n.group : "");
    char *s_host = sanitize_yaml_value(n.host ? n.host : "");
    char *s_user = sanitize_yaml_value(n.user ? n.user : "");
    char *s_pass = sanitize_yaml_value(n.pass ? n.pass : "");
    char *s_keypath = sanitize_yaml_value(n.keypath ? n.keypath : "");
    char *s_tags = sanitize_yaml_value(n.tags ? n.tags : "");

    FILE *f = fopen(g_config_path, "a");
    if (!f) {
        show_toast(" Write config failed ", 1);
        node_free(&n);
        free(s_name); free(s_group); free(s_host);
        free(s_user); free(s_pass); free(s_keypath); free(s_tags);
        return -1;
    }
    fprintf(f, "  - name: %s\n", s_name);
    fprintf(f, "    group: %s\n", s_group);
    fprintf(f, "    host: %s\n", s_host);
    fprintf(f, "    port: %d\n", n.port);
    fprintf(f, "    user: %s\n", s_user);
    fprintf(f, "    type: %s\n", n.type ? n.type : "pass");
    fprintf(f, "    pass: %s\n", s_pass);
    fprintf(f, "    keypath: %s\n", s_keypath);
    fprintf(f, "    tags: %s\n", s_tags);
    fclose(f);

    config_update_mtime();
    config_setup_permissions();

    show_toast(" Node added ", 2);

    node_free(&n);
    free(s_name); free(s_group); free(s_host);
    free(s_user); free(s_pass); free(s_keypath); free(s_tags);
    return 0;
}

int edit_node_interactive(int id) {
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, id, &n) != 0) {
        show_toast(" Node not found ", 1);
        return -1;
    }

    char title[64];
    snprintf(title, sizeof(title), " Edit: %s ", n.name ? n.name : "");

    int ret = form_interactive(&n, title);
    if (ret != 0) {
        node_free(&n);
        return -1;
    }

    config_backup();

    char *content = read_file(g_config_path);
    if (!content) {
        show_toast(" Read config failed ", 1);
        node_free(&n);
        return -1;
    }

    char *tmp_path = strdup("/tmp/sshm_edit_XXXXXX");
    int tmp_fd = mkstemp(tmp_path);
    if (tmp_fd == -1) {
        free(content); free(tmp_path);
        show_toast(" Create temp file failed ", 1);
        node_free(&n);
        return -1;
    }
    FILE *tmp = fdopen(tmp_fd, "w");
    if (!tmp) { close(tmp_fd); free(content); free(tmp_path); return -1; }

    int current_id = 0;
    int skip = 0;
    char *line = content;
    char *next;
    while ((next = strchr(line, '\n')) != NULL) {
        *next = '\0';
        int is_node_start = 0;
        const char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, "- name:", 7) == 0) is_node_start = 1;

        if (is_node_start) {
            current_id++;
            if (current_id == id) {
                skip = 1;
                line = next + 1;
                continue;
            }
            skip = 0;
        }

        if (!skip) {
            fprintf(tmp, "%s\n", line);
        }
        line = next + 1;
    }

    write_node_yaml(tmp, &n);
    fclose(tmp);
    free(content);

    if (rename(tmp_path, g_config_path) != 0) {
        show_toast(" Save failed ", 1);
        unlink(tmp_path);
        free(tmp_path);
        node_free(&n);
        return -1;
    }
    free(tmp_path);

    config_update_mtime();
    config_setup_permissions();

    show_toast(" Node updated ", 2);

    node_free(&n);
    return 0;
}

int delete_node_by_id(int id) {
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, id, &n) != 0) {
        show_toast(" Node not found ", 1);
        return -1;
    }

    char msg[128];
    snprintf(msg, sizeof(msg), "Delete [%s] permanently?", n.name ? n.name : "?");
    if (!show_confirm_dialog(" Delete Node ", msg)) {
        node_free(&n);
        return 0;
    }

    free(_deleted_yaml);
    _deleted_yaml = NULL;

    char *s_name = sanitize_yaml_value(n.name ? n.name : "");
    char *s_group = sanitize_yaml_value(n.group ? n.group : "");
    char *s_host = sanitize_yaml_value(n.host ? n.host : "");
    char *s_user = sanitize_yaml_value(n.user ? n.user : "");
    char *s_pass = sanitize_yaml_value(n.pass ? n.pass : "");
    char *s_keypath = sanitize_yaml_value(n.keypath ? n.keypath : "");

    size_t deleted_len = 256 + strlen(s_name) + strlen(s_group) + strlen(s_host)
                         + strlen(s_user) + strlen(s_pass) + strlen(s_keypath)
                         + (n.tags ? strlen(n.tags) + 16 : 16);
    _deleted_yaml = malloc(deleted_len);
    if (_deleted_yaml) {
        snprintf(_deleted_yaml, deleted_len,
            "  - name: %s\n    group: %s\n    host: %s\n    port: %d\n"
            "    user: %s\n    type: %s\n    pass: %s\n    keypath: %s\n    tags: %s\n",
            s_name, s_group, s_host, n.port, s_user, n.type ? n.type : "pass",
            s_pass, s_keypath, n.tags ? n.tags : "");
    }

    free(s_name); free(s_group); free(s_host);
    free(s_user); free(s_pass); free(s_keypath);

    config_backup();

    char *content = read_file(g_config_path);
    if (!content) {
        show_toast(" Read config failed ", 1);
        node_free(&n);
        return -1;
    }

    char *tmp_path = strdup("/tmp/sshm_del_XXXXXX");
    int tmp_fd = mkstemp(tmp_path);
    if (tmp_fd == -1) {
        free(content); free(tmp_path);
        node_free(&n);
        return -1;
    }
    FILE *tmp = fdopen(tmp_fd, "w");
    if (!tmp) { close(tmp_fd); free(content); free(tmp_path); return -1; }

    int current_id = 0;
    int skip = 0;
    char *line = content;
    char *next;
    while ((next = strchr(line, '\n')) != NULL) {
        *next = '\0';
        int is_node_start = 0;
        const char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, "- name:", 7) == 0) is_node_start = 1;

        if (is_node_start) {
            current_id++;
            if (current_id == id) {
                skip = 1;
                line = next + 1;
                continue;
            }
            skip = 0;
        }

        if (skip && is_node_start && current_id != id) {
            skip = 0;
        }

        if (!skip) {
            if (strspn(line, " \t") == strlen(line) && is_node_start) continue;
            fprintf(tmp, "%s\n", line);
        }
        line = next + 1;
    }
    fclose(tmp);
    free(content);

    if (rename(tmp_path, g_config_path) != 0) {
        show_toast(" Write config failed ", 1);
        unlink(tmp_path);
        free(tmp_path);
        node_free(&n);
        return -1;
    }
    free(tmp_path);

    config_update_mtime();
    config_setup_permissions();

    show_toast(" Node deleted ", 2);

    node_free(&n);
    return 0;
}

int undo_delete(void) {
    if (!_deleted_yaml) return -1;

    config_backup();

    FILE *f = fopen(g_config_path, "a");
    if (!f) return -1;
    fprintf(f, "%s", _deleted_yaml);
    fclose(f);

    config_update_mtime();
    config_setup_permissions();

    free(_deleted_yaml);
    _deleted_yaml = NULL;
    return 0;
}

int import_from_ssh_config(const char *ssh_config_path) {
    FILE *f = fopen(ssh_config_path, "r");
    if (!f) {
        fprintf(stderr, "SSH config not found: %s\n", ssh_config_path);
        return -1;
    }

    config_backup();

    int count = 0;
    char line[4096];
    char current_name[1024] = "";
    char current_host[1024] = "";
    char current_port[16] = "22";
    char current_user[256] = "root";
    int in_host = 0;

    while (fgets(line, sizeof(line), f)) {
        char *t = str_trim(line);
        if (!t[0] || t[0] == '#') continue;

        if (strncmp(t, "Host ", 5) == 0) {
            if (in_host && current_name[0] && current_host[0]) {
                FILE *cf = fopen(g_config_path, "a");
                if (cf) {
                    char *sn = sanitize_yaml_value(current_name);
                    char *sh = sanitize_yaml_value(current_host);
                    char *su = sanitize_yaml_value(current_user);
                    fprintf(cf, "  - name: %s\n", sn);
                    fprintf(cf, "    group: Imported\n");
                    fprintf(cf, "    host: %s\n", sh);
                    fprintf(cf, "    port: %s\n", current_port);
                    fprintf(cf, "    user: %s\n", su);
                    fprintf(cf, "    type: key\n");
                    fprintf(cf, "    pass: \"\"\n");
                    fprintf(cf, "    keypath: \"\"\n");
                    fclose(cf);
                    free(sn); free(sh); free(su);
                    count++;
                }
            }

            char *hostname = t + 5;
            while (*hostname == ' ') hostname++;
            char *space = strchr(hostname, ' ');
            if (space) *space = '\0';
            if (strcmp(hostname, "*") == 0) {
                in_host = 0;
                current_name[0] = '\0';
                current_host[0] = '\0';
                continue;
            }
            strncpy(current_name, hostname, sizeof(current_name) - 1);
            current_host[0] = '\0';
            strcpy(current_port, "22");
            strcpy(current_user, "root");
            in_host = 1;
        } else if (in_host && strncmp(t, "HostName ", 9) == 0) {
            strncpy(current_host, t + 9, sizeof(current_host) - 1);
            char *ct = str_trim(current_host);
            if (ct != current_host) memmove(current_host, ct, strlen(ct) + 1);
        } else if (in_host && strncmp(t, "Port ", 5) == 0) {
            strncpy(current_port, t + 5, sizeof(current_port) - 1);
            char *ct = str_trim(current_port);
            if (ct != current_port) memmove(current_port, ct, strlen(ct) + 1);
        } else if (in_host && strncmp(t, "User ", 5) == 0) {
            strncpy(current_user, t + 5, sizeof(current_user) - 1);
            char *ct = str_trim(current_user);
            if (ct != current_user) memmove(current_user, ct, strlen(ct) + 1);
        }
    }

    if (in_host && current_name[0] && current_host[0]) {
        FILE *cf = fopen(g_config_path, "a");
        if (cf) {
            char *sn = sanitize_yaml_value(current_name);
            char *sh = sanitize_yaml_value(current_host);
            char *su = sanitize_yaml_value(current_user);
            fprintf(cf, "  - name: %s\n", sn);
            fprintf(cf, "    group: Imported\n");
            fprintf(cf, "    host: %s\n", sh);
            fprintf(cf, "    port: %s\n", current_port);
            fprintf(cf, "    user: %s\n", su);
            fprintf(cf, "    type: key\n");
            fprintf(cf, "    pass: \"\"\n");
            fprintf(cf, "    keypath: \"\"\n");
            fclose(cf);
            free(sn); free(sh); free(su);
            count++;
        }
    }

    fclose(f);

    config_update_mtime();
    config_setup_permissions();

    if (count > 0)
        printf("Imported %d hosts from %s\n", count, ssh_config_path);
    else
        printf("No importable hosts found\n");

    return count;
}
