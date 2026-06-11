#include "import_export.h"
#include "config.h"
#include "yaml_parser.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int export_config_interactive(void) {
    if (!g_config_path) {
        printf("%s配置文件未初始化%s\n", ANSI_RED, ANSI_RESET);
        sleep(1);
        return -1;
    }

    printf("\n--- %s配置导出选项%s ---\n", ANSI_BLUE, ANSI_RESET);
    printf("1) %s屏幕输出 Base64%s (适合复制分享)\n", ANSI_YELLOW, ANSI_RESET);
    printf("2) %s保存到文件%s (适合备份)\n", ANSI_YELLOW, ANSI_RESET);
    printf("%s选择导出方式 (1/2): %s", ANSI_GREEN, ANSI_RESET);
    fflush(stdout);

    char choice = getchar();
    while (getchar() != '\n');

    switch (choice) {
        case '1': {
            FILE *f = fopen(g_config_path, "r");
            if (!f) {
                printf("%s导出失败：无法读取配置文件%s\n", ANSI_RED, ANSI_RESET);
                sleep(2);
                return -1;
            }

            char cmd[4096];
            snprintf(cmd, sizeof(cmd), "base64 < \"%s\" | tr -d '\\n'", g_config_path);

            printf("\n--- %sBASE64 配置导出%s ---\n", ANSI_BLUE, ANSI_RESET);
            printf("%s注意：此内容包含敏感的密码信息，请妥善保管！%s\n\n", ANSI_YELLOW, ANSI_RESET);
            fflush(stdout);

            int ret = system(cmd);

            printf("\n------------------------\n");
            printf("按任意键返回...");
            fflush(stdout);
            getchar();
            fclose(f);
            return ret;
        }
        case '2': {
            char path[4096] = "./ssh-manager-config.yaml";
            printf("请输入导出文件路径 (默认: ./ssh-manager-config.yaml): ");
            fflush(stdout);
            if (fgets(path, sizeof(path), stdin)) {
                char *t = str_trim(path);
                if (t[0] == '\0') strcpy(path, "./ssh-manager-config.yaml");
                else { memmove(path, t, strlen(t) + 1); }
            }

            char cmd[8192];
            snprintf(cmd, sizeof(cmd), "cp \"%s\" \"%s\" && chmod 600 \"%s\" 2>/dev/null",
                     g_config_path, path, path);
            if (system(cmd) == 0) {
                printf("%s配置已导出到: %s%s\n", ANSI_GREEN, path, ANSI_RESET);
            } else {
                printf("%s导出失败%s\n", ANSI_RED, ANSI_RESET);
            }
            sleep(2);
            return 0;
        }
        default:
            printf("%s无效选择%s\n", ANSI_RED, ANSI_RESET);
            sleep(1);
            return -1;
    }
}

int import_config_interactive(void) {
    printf("\n--- %s配置导入选项%s ---\n", ANSI_BLUE, ANSI_RESET);
    printf("1) %s从 Base64 字符串导入%s (从剪贴板)\n", ANSI_YELLOW, ANSI_RESET);
    printf("2) %s从文件导入%s (从备份文件)\n", ANSI_YELLOW, ANSI_RESET);
    printf("%s选择导入方式 (1/2): %s", ANSI_GREEN, ANSI_RESET);
    fflush(stdout);

    char choice = getchar();
    while (getchar() != '\n');

    switch (choice) {
        case '1': {
            printf("%s从 Base64 字符串导入%s\n", ANSI_BLUE, ANSI_RESET);
            printf("%s警告：此操作将覆盖现有配置！%s\n", ANSI_YELLOW, ANSI_RESET);
            printf("是否继续? (y/n): ");
            fflush(stdout);
            char c = getchar();
            while (getchar() != '\n');
            if (c != 'y' && c != 'Y') {
                printf("%s取消导入操作%s\n", ANSI_YELLOW, ANSI_RESET);
                sleep(1);
                return 0;
            }

            char b64[65536];
            printf("粘贴 BASE64 内容: ");
            fflush(stdout);
            if (!fgets(b64, sizeof(b64), stdin)) return -1;
            char *t = str_trim(b64);
            if (!t[0]) {
                printf("%s输入为空，导入失败%s\n", ANSI_RED, ANSI_RESET);
                sleep(1);
                return -1;
            }

            config_backup();

            char cmd[131072];
            snprintf(cmd, sizeof(cmd), "echo '%s' | tr -d '[:space:]' | base64 -d > \"%s\" 2>/dev/null",
                     t, g_config_path);
            if (system(cmd) == 0) {
                config_setup_permissions();
                printf("%s配置导入成功%s\n", ANSI_GREEN, ANSI_RESET);
            } else {
                printf("%s无效的 BASE64 格式%s\n", ANSI_RED, ANSI_RESET);
                sleep(1);
                return -1;
            }
            sleep(1);
            config_update_mtime();
            return 0;
        }
        case '2': {
            printf("%s从文件导入%s\n", ANSI_BLUE, ANSI_RESET);
            printf("%s警告：此操作将覆盖现有配置！%s\n", ANSI_YELLOW, ANSI_RESET);
            printf("是否继续? (y/n): ");
            fflush(stdout);
            char c = getchar();
            while (getchar() != '\n');
            if (c != 'y' && c != 'Y') {
                printf("%s取消导入操作%s\n", ANSI_YELLOW, ANSI_RESET);
                sleep(1);
                return 0;
            }

            char path[4096];
            printf("请输入配置文件路径: ");
            fflush(stdout);
            if (!fgets(path, sizeof(path), stdin)) return -1;
            char *tp = str_trim(path);
            if (!tp[0]) return -1;
            memmove(path, tp, strlen(tp) + 1);

            if (access(path, R_OK) != 0) {
                printf("%s文件不存在: %s%s\n", ANSI_RED, path, ANSI_RESET);
                sleep(2);
                return -1;
            }

            FILE *tf = fopen(path, "r");
            int has_nodes = 0;
            char buf[256];
            if (tf) {
                while (fgets(buf, sizeof(buf), tf)) {
                    char *tb = str_trim(buf);
                    if (strcmp(tb, "nodes:") == 0) { has_nodes = 1; break; }
                }
                fclose(tf);
            }

            if (!has_nodes) {
                printf("%s验证失败：文件可能不是有效的SSH管理器配置文件%s\n", ANSI_RED, ANSI_RESET);
                sleep(2);
                return -1;
            }

            config_backup();

            char cmd[8192];
            snprintf(cmd, sizeof(cmd), "cp \"%s\" \"%s\" && chmod 600 \"%s\" 2>/dev/null",
                     path, g_config_path, g_config_path);
            if (system(cmd) == 0) {
                printf("%s配置从文件导入成功: %s%s\n", ANSI_GREEN, path, ANSI_RESET);
            } else {
                printf("%s导入失败%s\n", ANSI_RED, ANSI_RESET);
            }
            config_update_mtime();
            sleep(2);
            return 0;
        }
        default:
            printf("%s无效选择%s\n", ANSI_RED, ANSI_RESET);
            sleep(1);
            return -1;
    }
}

int export_ssh_config(void) {
    node_list_t list;
    if (get_all_nodes(g_config_path, NULL, &list) < 0) {
        printf("%s无法解析配置%s\n", ANSI_RED, ANSI_RESET);
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
