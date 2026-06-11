#include "node.h"
#include "config.h"
#include "util.h"
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

int add_node_interactive(void) {
    node_t n;
    node_init(&n);
    n.name = strdup("");
    n.host = strdup("");
    n.group = strdup("Default");
    n.port = 22;
    n.user = strdup("root");
    n.type = strdup("pass");

    char input[4096];

    while (1) {
        const char *aclabel = (strcmp(n.type, "key") == 0) ? "密钥" : "密码";
        const char *pass_display = (n.pass && n.pass[0]) ? "****" : "(未设置)";
        int is_key = (strcmp(n.type, "key") == 0);

        printf("\033[H\033[J");
        printf("\n%s[添加新节点]%s\n\n", ANSI_BLUE, ANSI_RESET);
        printf("  %s[1]%s 名称: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
               n.name && n.name[0] ? n.name : "(未设置)", ANSI_RESET);
        printf("  %s[2]%s 分组: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, n.group, ANSI_RESET);
        printf("  %s[3]%s 主机: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
               n.host && n.host[0] ? n.host : "(必填)", ANSI_RESET);
        printf("  %s[4]%s 端口: %s%d%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, n.port, ANSI_RESET);
        printf("  %s[5]%s 用户: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, n.user, ANSI_RESET);
        printf("  %s[6]%s 认证: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, aclabel, ANSI_RESET);

        if (is_key) {
            printf("  %s[7]%s 私钥: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.keypath && n.keypath[0] ? n.keypath : "(必填)", ANSI_RESET);
            printf("  %s[8]%s 短语: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, pass_display, ANSI_RESET);
            printf("  %s[9]%s 标签: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.tags && n.tags[0] ? n.tags : "(无)", ANSI_RESET);
        } else {
            printf("  %s[7]%s 密码: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, pass_display, ANSI_RESET);
            printf("  %s[8]%s 标签: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.tags && n.tags[0] ? n.tags : "(无)", ANSI_RESET);
        }

        int tag_max = is_key ? 9 : 8;
        printf("\n");
        if (n.name && n.name[0] && n.host && n.host[0] && (!is_key || (n.keypath && n.keypath[0]))) {
            printf("  %sEnter%s=保存  %s1-%d%s=编辑  %sq%s=取消\n",
                   ANSI_GREEN, ANSI_RESET, ANSI_BLUE, tag_max, ANSI_RESET, ANSI_RED, ANSI_RESET);
        } else {
            printf("  %s1-%d%s=编辑  %sq%s=取消\n",
                   ANSI_BLUE, tag_max, ANSI_RESET, ANSI_RED, ANSI_RESET);
        }

        int ch = getchar();

        /* consume newline from line-buffered cooked input */
        if (ch != '\n' && ch != '\033' && ch != EOF) {
            int c;
            while ((c = getchar()) != '\n' && c != EOF);
        }

        if (ch == '\n') {
            if (n.name && n.name[0] && n.host && n.host[0]) {
                if (is_key && (!n.keypath || !n.keypath[0])) {
                    printf("\n%s私钥路径不能为空%s\n", ANSI_RED, ANSI_RESET);
                    sleep(1);
                    continue;
                }
                break;
            }
            printf("\n%s名称和主机为必填项%s\n", ANSI_RED, ANSI_RESET);
            sleep(1);
            continue;
        }

        if (ch == 'q' || ch == 'Q') {
            printf("\n%s取消添加%s\n", ANSI_YELLOW, ANSI_RESET);
            sleep(1);
            node_free(&n);
            return -1;
        }

        if (ch == '\033') {
            getchar(); getchar();
        }

        switch (ch) {
            case '1': {
                printf("名称: "); fflush(stdout);
                if (fgets(input, sizeof(input), stdin)) {
                    char *t = str_trim(input);
                    if (t[0]) { free(n.name); n.name = strdup(t); }
                }
                break;
            }
            case '2': {
                printf("分组 (Default): "); fflush(stdout);
                if (fgets(input, sizeof(input), stdin)) {
                    char *t = str_trim(input);
                    if (t[0]) { free(n.group); n.group = strdup(t); }
                }
                break;
            }
            case '3': {
                while (1) {
                    printf("主机: "); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) { printf("%s主机不能为空%s\n", ANSI_RED, ANSI_RESET); continue; }
                    if (!validate_host(t)) { printf("%s主机包含非法字符%s\n", ANSI_RED, ANSI_RESET); continue; }
                    free(n.host); n.host = strdup(t);
                    break;
                }
                break;
            }
            case '4': {
                while (1) {
                    char port_str[32];
                    snprintf(port_str, sizeof(port_str), "%d", n.port);
                    printf("端口 (%s): ", port_str); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (!validate_port(t)) { printf("%s端口无效 (1-65535)%s\n", ANSI_RED, ANSI_RESET); continue; }
                    n.port = atoi(t);
                    break;
                }
                break;
            }
            case '5': {
                while (1) {
                    printf("用户 (%s): ", n.user); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (!validate_host(t)) { printf("%s用户名包含非法字符%s\n", ANSI_RED, ANSI_RESET); continue; }
                    free(n.user); n.user = strdup(t);
                    break;
                }
                break;
            }
            case '6': {
                while (1) {
                    printf("认证 (1:密码 2:密钥) [%s]: ", n.type); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (strcmp(t, "1") == 0) { free(n.type); n.type = strdup("pass"); break; }
                    if (strcmp(t, "2") == 0) { free(n.type); n.type = strdup("key"); break; }
                    printf("%s请输入 1 或 2%s\n", ANSI_RED, ANSI_RESET);
                }
                break;
            }
            case '7': {
                if (is_key) {
                    while (1) {
                        printf("私钥路径: "); fflush(stdout);
                        if (!fgets(input, sizeof(input), stdin)) break;
                        char *t = str_trim(input);
                        if (!t[0]) break;
                        if (validate_ssh_key(t)) { free(n.keypath); n.keypath = strdup(t); break; }
                        printf("%s不是有效的SSH私钥或文件不存在%s\n", ANSI_RED, ANSI_RESET);
                    }
                } else {
                    printf("密码: "); fflush(stdout);
                    term_echo_off();
                    if (fgets(input, sizeof(input), stdin)) {
                        term_echo_on();
                        char *t = str_trim(input);
                        if (t[0]) { free(n.pass); n.pass = strdup(t); }
                    } else {
                        term_echo_on();
                    }
                }
                break;
            }
            case '8': {
                if (is_key) {
                    printf("短语: "); fflush(stdout);
                    term_echo_off();
                    if (fgets(input, sizeof(input), stdin)) {
                        term_echo_on();
                        char *t = str_trim(input);
                        if (t[0]) { free(n.pass); n.pass = strdup(t); }
                    } else {
                        term_echo_on();
                    }
                } else {
                    printf("标签(逗号分隔): "); fflush(stdout);
                    if (fgets(input, sizeof(input), stdin)) {
                        char *t = str_trim(input);
                        if (t[0]) { free(n.tags); n.tags = strdup(t); }
                    }
                }
                break;
            }
            case '9': {
                if (is_key) {
                    printf("标签(逗号分隔): "); fflush(stdout);
                    if (fgets(input, sizeof(input), stdin)) {
                        char *t = str_trim(input);
                        if (t[0]) { free(n.tags); n.tags = strdup(t); }
                    }
                }
                break;
            }
        }
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
        printf("%s写入配置文件失败%s\n", ANSI_RED, ANSI_RESET);
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

    printf("%s节点 [%s] 已成功添加。 (%s:%d %s@%s)%s\n",
           ANSI_GREEN, n.name, n.host, n.port, n.user, n.type, ANSI_RESET);
    sleep(1);

    node_free(&n);
    free(s_name); free(s_group); free(s_host);
    free(s_user); free(s_pass); free(s_keypath); free(s_tags);
    return 0;
}

int edit_node_interactive(int id) {
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, id, &n) != 0) {
        printf("%s未找到节点 ID: %d%s\n", ANSI_RED, id, ANSI_RESET);
        sleep(1);
        return -1;
    }

    char input[4096];

    while (1) {
        const char *aclabel = (strcmp(n.type, "key") == 0) ? "密钥" : "密码";
        const char *pass_display = (n.pass && n.pass[0]) ? "****" : "(未设置)";
        int is_key = (strcmp(n.type, "key") == 0);

        printf("\033[H\033[J");
        printf("\n%s[编辑节点: %s%s%s]%s\n\n", ANSI_BLUE, ANSI_YELLOW,
               n.name ? n.name : "(unnamed)", ANSI_BLUE, ANSI_RESET);
        printf("  %s[1]%s 名称: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
               n.name ? n.name : "", ANSI_RESET);
        printf("  %s[2]%s 分组: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, n.group, ANSI_RESET);
        printf("  %s[3]%s 主机: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
               n.host ? n.host : "", ANSI_RESET);
        printf("  %s[4]%s 端口: %s%d%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, n.port, ANSI_RESET);
        printf("  %s[5]%s 用户: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
               n.user ? n.user : "", ANSI_RESET);
        printf("  %s[6]%s 认证: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, aclabel, ANSI_RESET);

        int tag_max;
        if (is_key) {
            printf("  %s[7]%s 私钥: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.keypath && n.keypath[0] ? n.keypath : "(必填)", ANSI_RESET);
            printf("  %s[8]%s 短语: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, pass_display, ANSI_RESET);
            printf("  %s[9]%s 标签: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.tags && n.tags[0] ? n.tags : "(无)", ANSI_RESET);
            tag_max = 9;
        } else {
            printf("  %s[7]%s 密码: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW, pass_display, ANSI_RESET);
            printf("  %s[8]%s 标签: %s%s%s\n", ANSI_GREEN, ANSI_RESET, ANSI_YELLOW,
                   n.tags && n.tags[0] ? n.tags : "(无)", ANSI_RESET);
            tag_max = 8;
        }

        printf("\n");
        if (n.name && n.name[0] && n.host && n.host[0] && (!is_key || (n.keypath && n.keypath[0]))) {
            printf("  %sEnter%s=保存  %s1-%d%s=编辑  %sq%s=取消\n",
                   ANSI_GREEN, ANSI_RESET, ANSI_BLUE, tag_max, ANSI_RESET,
                   ANSI_RED, ANSI_RESET);
        } else {
            printf("  必填项未完成  %s1-%d%s=编辑  %sq%s=取消\n",
                   ANSI_BLUE, tag_max, ANSI_RESET, ANSI_RED, ANSI_RESET);
        }

        int ch = getchar();

        /* consume newline from line-buffered cooked input */
        if (ch != '\n' && ch != '\033' && ch != EOF) {
            int c;
            while ((c = getchar()) != '\n' && c != EOF);
        }

        if (ch == '\n') {
            if (n.name && n.name[0] && n.host && n.host[0]) {
                if (is_key && (!n.keypath || !n.keypath[0])) {
                    printf("\n%s私钥路径不能为空%s\n", ANSI_RED, ANSI_RESET);
                    sleep(1);
                    continue;
                }
                break;
            }
            printf("\n%s名称和主机为必填项%s\n", ANSI_RED, ANSI_RESET);
            sleep(1);
            continue;
        }
        if (ch == 'q' || ch == 'Q') {
            printf("\n%s取消编辑%s\n", ANSI_YELLOW, ANSI_RESET);
            sleep(1);
            node_free(&n);
            return -1;
        }

        if (ch == '\033') {
            getchar(); getchar();
        }

        switch (ch) {
            case '1': {
                printf("名称: "); fflush(stdout);
                if (fgets(input, sizeof(input), stdin)) {
                    char *t = str_trim(input);
                    if (t[0]) { free(n.name); n.name = strdup(t); }
                }
                break;
            }
            case '2': {
                printf("分组: "); fflush(stdout);
                if (fgets(input, sizeof(input), stdin)) {
                    char *t = str_trim(input);
                    if (t[0]) { free(n.group); n.group = strdup(t); }
                    else { free(n.group); n.group = strdup("Default"); }
                }
                break;
            }
            case '3': {
                while (1) {
                    printf("主机: "); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (!validate_host(t)) { printf("%s主机包含非法字符%s\n", ANSI_RED, ANSI_RESET); continue; }
                    free(n.host); n.host = strdup(t);
                    break;
                }
                break;
            }
            case '4': {
                while (1) {
                    char port_str[32];
                    snprintf(port_str, sizeof(port_str), "%d", n.port);
                    printf("端口 (%s): ", port_str); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (!validate_port(t)) { printf("%s端口无效 (1-65535)%s\n", ANSI_RED, ANSI_RESET); continue; }
                    n.port = atoi(t);
                    break;
                }
                break;
            }
            case '5': {
                while (1) {
                    printf("用户 (%s): ", n.user ? n.user : "root"); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (!validate_host(t)) { printf("%s用户名包含非法字符%s\n", ANSI_RED, ANSI_RESET); continue; }
                    free(n.user); n.user = strdup(t);
                    break;
                }
                break;
            }
            case '6': {
                while (1) {
                    printf("认证 (1:密码 2:密钥) [%s]: ", n.type); fflush(stdout);
                    if (!fgets(input, sizeof(input), stdin)) break;
                    char *t = str_trim(input);
                    if (!t[0]) break;
                    if (strcmp(t, "1") == 0) { free(n.type); n.type = strdup("pass"); break; }
                    if (strcmp(t, "2") == 0) { free(n.type); n.type = strdup("key"); break; }
                    printf("%s请输入 1 或 2%s\n", ANSI_RED, ANSI_RESET);
                }
                break;
            }
            case '7': {
                if (is_key) {
                    while (1) {
                        printf("私钥路径: "); fflush(stdout);
                        if (!fgets(input, sizeof(input), stdin)) break;
                        char *t = str_trim(input);
                        if (!t[0]) break;
                        if (validate_ssh_key(t)) { free(n.keypath); n.keypath = strdup(t); break; }
                        printf("%s不是有效的SSH私钥或文件不存在%s\n", ANSI_RED, ANSI_RESET);
                    }
                } else {
                    printf("密码: "); fflush(stdout);
                    term_echo_off();
                    if (fgets(input, sizeof(input), stdin)) {
                        term_echo_on();
                        char *t = str_trim(input);
                        if (t[0]) { free(n.pass); n.pass = strdup(t); }
                    } else {
                        term_echo_on();
                    }
                }
                break;
            }
            case '8': {
                if (is_key) {
                    printf("短语: "); fflush(stdout);
                    term_echo_off();
                    if (fgets(input, sizeof(input), stdin)) {
                        term_echo_on();
                        char *t = str_trim(input);
                        if (t[0]) { free(n.pass); n.pass = strdup(t); }
                    } else {
                        term_echo_on();
                    }
                } else {
                    printf("标签(逗号分隔): "); fflush(stdout);
                    if (fgets(input, sizeof(input), stdin)) {
                        char *t = str_trim(input);
                        if (t[0]) { free(n.tags); n.tags = strdup(t); }
                    }
                }
                break;
            }
            case '9': {
                if (is_key) {
                    printf("标签(逗号分隔): "); fflush(stdout);
                    if (fgets(input, sizeof(input), stdin)) {
                        char *t = str_trim(input);
                        if (t[0]) { free(n.tags); n.tags = strdup(t); }
                    }
                }
                break;
            }
        }
    }

    config_backup();

    char *content = read_file(g_config_path);
    if (!content) {
        printf("%s读取配置文件失败%s\n", ANSI_RED, ANSI_RESET);
        node_free(&n);
        return -1;
    }

    char *tmp_path = strdup("/tmp/sshm_edit_XXXXXX");
    int tmp_fd = mkstemp(tmp_path);
    if (tmp_fd == -1) {
        free(content); free(tmp_path);
        printf("%s创建临时文件失败%s\n", ANSI_RED, ANSI_RESET);
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
        printf("%s保存失败%s\n", ANSI_RED, ANSI_RESET);
        unlink(tmp_path);
        free(tmp_path);
        node_free(&n);
        return -1;
    }
    free(tmp_path);

    config_update_mtime();
    config_setup_permissions();
    printf("%s节点已更新: %s%s\n", ANSI_GREEN, n.name, ANSI_RESET);
    sleep(1);

    node_free(&n);
    return 0;
}

int delete_node_by_id(int id) {
    node_t n;
    node_init(&n);
    if (read_node_info(g_config_path, id, &n) != 0) {
        printf("%s无效 ID: %d (未找到节点)%s\n", ANSI_RED, id, ANSI_RESET);
        sleep(1);
        return -1;
    }

    printf("确认永久删除节点 [%s] ? (y/n): ", n.name ? n.name : "");
    fflush(stdout);
    char c = getchar();
    while (getchar() != '\n');

    if (c != 'y' && c != 'Y') {
        printf("%s取消删除操作%s\n", ANSI_YELLOW, ANSI_RESET);
        sleep(1);
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
        printf("%s读取配置文件失败%s\n", ANSI_RED, ANSI_RESET);
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
        printf("%s写入配置文件失败%s\n", ANSI_RED, ANSI_RESET);
        unlink(tmp_path);
        free(tmp_path);
        node_free(&n);
        return -1;
    }
    free(tmp_path);

    config_update_mtime();
    config_setup_permissions();
    printf("%s节点 [%s] 已成功删除。%s\n", ANSI_GREEN,
           n.name ? n.name : "", ANSI_RESET);
    sleep(1);
    node_free(&n);
    return 0;
}

int undo_delete(void) {
    if (!_deleted_yaml) {
        printf("\n%s没有可恢复的节点%s\n", ANSI_YELLOW, ANSI_RESET);
        sleep(1);
        return -1;
    }

    config_backup();

    FILE *f = fopen(g_config_path, "a");
    if (!f) {
        printf("%s恢复失败%s\n", ANSI_RED, ANSI_RESET);
        return -1;
    }
    fprintf(f, "%s", _deleted_yaml);
    fclose(f);

    config_update_mtime();
    config_setup_permissions();

    printf("%s节点已恢复%s\n", ANSI_GREEN, ANSI_RESET);
    free(_deleted_yaml);
    _deleted_yaml = NULL;
    sleep(1);
    return 0;
}

int import_from_ssh_config(const char *ssh_config_path) {
    FILE *f = fopen(ssh_config_path, "r");
    if (!f) {
        printf("%sSSH config not found: %s%s\n", ANSI_RED, ssh_config_path, ANSI_RESET);
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
        printf("%s从 %s 导入了 %d 个主机%s\n", ANSI_GREEN, ssh_config_path, count, ANSI_RESET);
    else
        printf("%s未找到可导入的主机条目%s\n", ANSI_YELLOW, ANSI_RESET);

    return count;
}
