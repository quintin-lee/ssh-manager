#include "config.h"
#include "yaml_parser.h"
#include "node.h"
#include "ssh.h"
#include "import_export.h"
#include "util.h"
#include "tui.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#include <locale.h>
#include <signal.h>

static const char *VERSION = "0.5.3";

static void sigint_cleanup(int sig) {
    (void)sig;
    system("stty sane 2>/dev/null");
    _exit(1);
}

static int cmd_available(const char *name) {
    char buf[256];
    snprintf(buf, sizeof(buf), "command -v %s >/dev/null 2>&1", name);
    return system(buf) == 0;
}

static void print_version(void) {
    printf("SSH Manager v%s\n", VERSION);
}

static void print_help(void) {
    printf("SSH Manager v%s - SSH connection management tool\n", VERSION);
    printf("\n");
    printf("Usage:\n");
    printf("  sshm [keyword]        Search & connect directly\n");
    printf("  sshm                   Interactive mode (arrow keys, real-time filter)\n");
    printf("\n");
    printf("Options:\n");
    printf("  --help, -h            Show this help message\n");
    printf("  --version, -v         Show version information\n");
    printf("  --config <path>       Use specified config file\n");
    printf("  --validate            Validate config file syntax\n");
    printf("  --import-ssh-config f Import Host entries from SSH config\n");
    printf("  --export-ssh-config   Export nodes to SSH config format\n");
    printf("\n");
    printf("Interactive keys:\n");
    printf("  ↑↓  Navigate   Enter  Connect    type  Filter\n");
    printf("  a   Add node    d     Delete     e     Export\n");
    printf("  i   Import      h     Help       q     Quit\n");
    printf("\n");
    printf("Environment:\n");
    printf("  SSH_MANAGER_CONFIG    Path to config file\n");
}

static int cmd_validate(void) {
    node_list_t list;
    int count = get_all_nodes(g_config_path, NULL, &list);
    if (count >= 0) {
        printf("%s配置有效: %d 个节点%s\n", ANSI_GREEN, count, ANSI_RESET);
        node_list_free(&list);
        return 0;
    } else {
        printf("%s配置解析失败%s\n", ANSI_RED, ANSI_RESET);
        return 1;
    }
}

static int cmd_direct_connect(const char *keyword) {
    node_list_t list;
    int count = get_all_nodes(g_config_path, keyword, &list);
    if (count == 0) {
        fprintf(stderr, "%s无匹配节点: %s%s\n", ANSI_RED, keyword, ANSI_RESET);
        node_list_free(&list);
        return 1;
    }

    if (count == 1) {
        node_t *n = &list.nodes[0];
        printf("连接: %s (%s:%d)\n", n->name, n->host, n->port);
        int ret = ssh_connect(n);
        node_list_free(&list);
        return ret;
    }

    printf("%s找到 %d 个匹配节点:%s\n", ANSI_YELLOW, count, ANSI_RESET);
    for (int i = 0; i < count; i++) {
        node_t *n = &list.nodes[i];
        printf("  [%d] %s (%s:%d) [%s]\n", n->id, n->name, n->host, n->port, n->group);
    }
    printf("\n请运行 %ssshm%s 进入交互界面选择，或输入更精确的关键词\n", ANSI_GREEN, ANSI_RESET);
    node_list_free(&list);
    return 1;
}

int main(int argc, char *argv[]) {
    setlocale(LC_ALL, "");
    signal(SIGINT, sigint_cleanup);
    util_init();
    atexit(util_cleanup);

    if (!cmd_available("expect")) {
        fprintf(stderr, "错误: expect 未安装 (需要用于 SSH 自动连接)\n");
        return 1;
    }

    /* Seed random for temp files */
    srand(time(NULL) ^ (getpid() << 16));

    /* Default config from env or local */
    char *env_conf = getenv("SSH_MANAGER_CONFIG");
    if (env_conf) {
        g_config_path = strdup(env_conf);
    } else {
        char cwd[1024];
        if (getcwd(cwd, sizeof(cwd))) {
            g_config_path = malloc(strlen(cwd) + 32);
            sprintf(g_config_path, "%s/config.yaml", cwd);
        } else {
            g_config_path = strdup("config.yaml");
        }
    }

    /* Long options */
    static struct option long_opts[] = {
        {"help",              no_argument,       0, 'h'},
        {"version",           no_argument,       0, 'v'},
        {"config",            required_argument, 0, 'c'},
        {"validate",          no_argument,       0, 'V'},
        {"import-ssh-config", required_argument, 0, 'i'},
        {"export-ssh-config", no_argument,       0, 'E'},
        {0, 0, 0, 0}
    };

    int opt;
    int do_validate = 0;
    int do_export_ssh = 0;
    const char *import_ssh_path = NULL;

    while ((opt = getopt_long(argc, argv, "hvc:Vi:E", long_opts, NULL)) != -1) {
        switch (opt) {
            case 'h':
                print_help();
                exit(0);
            case 'v':
                print_version();
                exit(0);
            case 'c':
                free(g_config_path);
                g_config_path = strdup(optarg);
                break;
            case 'V':
                do_validate = 1;
                break;
            case 'i':
                import_ssh_path = optarg;
                break;
            case 'E':
                do_export_ssh = 1;
                break;
            default:
                fprintf(stderr, "Unknown option. Use --help for usage.\n");
                exit(1);
        }
    }

    /* Initialize config */
    if (config_resolve() != 0) {
        fprintf(stderr, "Failed to initialize config\n");
        exit(1);
    }
    config_setup_permissions();

    /* Handle commands */
    if (do_validate) {
        return cmd_validate();
    }

    if (import_ssh_path) {
        return import_from_ssh_config(import_ssh_path) >= 0 ? 0 : 1;
    }

    if (do_export_ssh) {
        return export_ssh_config();
    }

    /* Remaining args = direct keyword search */
    if (optind < argc) {
        return cmd_direct_connect(argv[optind]);
    }

    /* Interactive mode */
    tui_init();
    int ret = tui_interactive_list();
    return ret;
}
