#include "config.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <pwd.h>
#include <time.h>

char *g_config_path = NULL;
time_t g_config_mtime = 0;

static char *_get_home_dir(void) {
    char *home = getenv("HOME");
    if (home) return home;
    struct passwd *pw = getpwuid(getuid());
    return pw ? pw->pw_dir : NULL;
}

static int _ensure_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) return 0;
        return -1;
    }
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "mkdir -p '%s' 2>/dev/null", path);
    return system(cmd);
}

static int _file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0 && S_ISREG(st.st_mode));
}

static int _file_readable(const char *path) {
    return (access(path, R_OK) == 0);
}

static int _dir_writable(const char *path) {
    return (access(path, W_OK) == 0);
}

static int _copy_file(const char *src, const char *dst) {
    FILE *fin = fopen(src, "r");
    if (!fin) return -1;
    FILE *fout = fopen(dst, "w");
    if (!fout) { fclose(fin); return -1; }
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fin)) > 0)
        fwrite(buf, 1, n, fout);
    fclose(fin);
    fclose(fout);
    return 0;
}

static int _touch_config(const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fprintf(f, "nodes:\n");
    fclose(f);
    chmod(path, 0600);
    return 0;
}

int config_resolve(void) {
    char *home = _get_home_dir();
    if (!home) {
        fprintf(stderr, "Cannot determine home directory\n");
        return -1;
    }

    char user_conf[1024];
    snprintf(user_conf, sizeof(user_conf), "%s/.config/ssh-manager/config.yaml", home);

    char user_conf_dir[1024];
    snprintf(user_conf_dir, sizeof(user_conf_dir), "%s/.config/ssh-manager", home);

    _ensure_dir(user_conf_dir);

    if (!g_config_path) {
        g_config_path = strdup(user_conf);
    }

    /* If user config exists, prefer it (match Bash behavior) */
    if (_file_exists(user_conf)) {
        free(g_config_path);
        g_config_path = strdup(user_conf);
        config_update_mtime();
        return 0;
    }

    int is_etc = (strstr(g_config_path, "/etc/") == g_config_path);

    if (is_etc) {
        if (_file_exists(g_config_path)) {
            if (!_file_readable(g_config_path)) {
                fprintf(stderr, "Error: system config %s is not readable\n", g_config_path);
                return -1;
            }
            if (!_file_exists(user_conf)) {
                if (_copy_file(g_config_path, user_conf) == 0) {
                    chmod(user_conf, 0600);
                    free(g_config_path);
                    g_config_path = strdup(user_conf);
                } else {
                    fprintf(stderr, "Warning: using read-only system config\n");
                }
            } else {
                free(g_config_path);
                g_config_path = strdup(user_conf);
            }
        } else {
            _ensure_dir(user_conf_dir);
            _touch_config(user_conf);
            free(g_config_path);
            g_config_path = strdup(user_conf);
        }
    } else {
        char conf_dir[1024];
        snprintf(conf_dir, sizeof(conf_dir), "%s", g_config_path);
        char *slash = strrchr(conf_dir, '/');
        if (slash) *slash = '\0';
        else snprintf(conf_dir, sizeof(conf_dir), ".");

        if (!_dir_writable(conf_dir)) {
            if (_dir_writable(user_conf_dir)) {
                free(g_config_path);
                g_config_path = strdup(user_conf);
            } else {
                fprintf(stderr, "Error: directory %s is not writable\n", conf_dir);
                return -1;
            }
        }

        if (!_file_exists(g_config_path)) {
            if (_touch_config(g_config_path) != 0) {
                fprintf(stderr, "Error: cannot create config %s\n", g_config_path);
                return -1;
            }
        } else if (!_file_readable(g_config_path)) {
            fprintf(stderr, "Error: config %s is not readable\n", g_config_path);
            return -1;
        }
    }

    config_update_mtime();
    return 0;
}

int config_setup_permissions(void) {
    if (!g_config_path || !_file_exists(g_config_path))
        return 0;
    return chmod(g_config_path, 0600);
}

int config_backup(void) {
    if (!g_config_path || !_file_exists(g_config_path))
        return 0;
    char backup[1024];
    snprintf(backup, sizeof(backup), "%s.bak.%ld", g_config_path, (long)time(NULL));
    return _copy_file(g_config_path, backup);
}

int config_update_mtime(void) {
    if (!g_config_path) return -1;
    struct stat st;
    if (stat(g_config_path, &st) != 0) return -1;
    g_config_mtime = st.st_mtime;
    return 0;
}
