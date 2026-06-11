#include "history.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
#include <pwd.h>

#define HISTORY_MAX 20
#define HISTORY_DISPLAY 10

static const char *history_path(void) {
    static char path[1024];
    static int initialized = 0;
    if (!initialized) {
        char *home = getenv("HOME");
        if (!home) {
            struct passwd *pw = getpwuid(getuid());
            home = pw ? pw->pw_dir : "/tmp";
        }
        snprintf(path, sizeof(path), "%s/.cache/ssh-manager-history", home);
        char dir[1024];
        snprintf(dir, sizeof(dir), "%s/.cache", home);
        mkdir(dir, 0700);
        initialized = 1;
    }
    return path;
}

static void trim_trailing_newline(char *s) {
    size_t len = strlen(s);
    while (len > 0 && (s[len - 1] == '\n' || s[len - 1] == '\r'))
        s[--len] = '\0';
}

void history_record(const char *name, const char *host) {
    const char *path = history_path();
    time_t now = time(NULL);

    FILE *f = fopen(path, "r");
    char **lines = NULL;
    int line_count = 0;

    if (f) {
        char buf[4096];
        while (fgets(buf, sizeof(buf), f)) {
            trim_trailing_newline(buf);
            char entry[4096];
            snprintf(entry, sizeof(entry), "%s|%s|%ld", name, host, (long)now);

            if (strcmp(buf, entry) == 0) continue;

            lines = realloc(lines, (line_count + 1) * sizeof(char *));
            lines[line_count++] = strdup(buf);
        }
        fclose(f);
    }

    char new_entry[4096];
    snprintf(new_entry, sizeof(new_entry), "%s|%s|%ld", name, host, (long)now);

    lines = realloc(lines, (line_count + 1) * sizeof(char *));
    lines[line_count++] = strdup(new_entry);

    f = fopen(path, "w");
    if (f) {
        int start = line_count > HISTORY_MAX ? line_count - HISTORY_MAX : 0;
        for (int i = start; i < line_count; i++) {
            fprintf(f, "%s\n", lines[i]);
        }
        fclose(f);
    }

    for (int i = 0; i < line_count; i++)
        free(lines[i]);
    free(lines);
}

history_entry_t *history_get_recent(int *count) {
    *count = 0;
    const char *path = history_path();
    FILE *f = fopen(path, "r");
    if (!f) return NULL;

    char **bufs = NULL;
    int n = 0;
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        trim_trailing_newline(line);
        bufs = realloc(bufs, (n + 1) * sizeof(char *));
        bufs[n++] = strdup(line);
    }
    fclose(f);

    int take = n > HISTORY_DISPLAY ? HISTORY_DISPLAY : n;
    if (take == 0) { free(bufs); return NULL; }

    history_entry_t *entries = calloc(take, sizeof(history_entry_t));
    for (int i = 0; i < take; i++) {
        int idx = n - 1 - i;
        if (idx < 0) break;
        char *name_s = bufs[idx];
        char *host_s = strchr(name_s, '|');
        if (host_s) {
            *host_s++ = '\0';
            char *ts_s = strchr(host_s, '|');
            if (ts_s) {
                *ts_s++ = '\0';
                entries[i].name = strdup(name_s);
                entries[i].host = strdup(host_s);
                entries[i].timestamp = atol(ts_s);
                (*count)++;
            }
        }
    }

    for (int i = 0; i < n; i++) free(bufs[i]);
    free(bufs);
    return entries;
}

void history_entry_free(history_entry_t *entry) {
    if (entry) {
        free(entry->name);
        free(entry->host);
    }
}
