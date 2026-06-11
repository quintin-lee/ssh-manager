#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <termios.h>

static struct termios orig_term;
static int term_saved = 0;

void term_echo_off(void) {
    if (!term_saved) {
        tcgetattr(STDIN_FILENO, &orig_term);
        term_saved = 1;
    }
    struct termios t = orig_term;
    t.c_lflag &= ~(ECHO | ICANON);
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
}

void term_echo_on(void) {
    if (term_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_term);
        term_saved = 0;
    }
}

char *ANSI_RED   = NULL;
char *ANSI_GREEN = NULL;
char *ANSI_YELLOW= NULL;
char *ANSI_BLUE  = NULL;
char *ANSI_CYAN  = NULL;
char *ANSI_RESET = NULL;

void util_init(void) {
    ANSI_RED   = strdup("\033[31m");
    ANSI_GREEN = strdup("\033[32m");
    ANSI_YELLOW= strdup("\033[33m");
    ANSI_BLUE  = strdup("\033[34m");
    ANSI_CYAN  = strdup("\033[36m");
    ANSI_RESET = strdup("\033[0m");
}

void util_cleanup(void) {
    free(ANSI_RED);   ANSI_RED   = NULL;
    free(ANSI_GREEN); ANSI_GREEN = NULL;
    free(ANSI_YELLOW);ANSI_YELLOW= NULL;
    free(ANSI_BLUE);  ANSI_BLUE  = NULL;
    free(ANSI_CYAN);  ANSI_CYAN  = NULL;
    free(ANSI_RESET); ANSI_RESET = NULL;
}

char *str_trim(char *s) {
    if (!s) return NULL;
    char *end;
    while (isspace((unsigned char)*s)) s++;
    if (*s == 0) return s;
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) end--;
    *(end + 1) = '\0';
    return s;
}

char *str_tolower(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *lower = malloc(len + 1);
    if (!lower) return NULL;
    for (size_t i = 0; i < len; i++)
        lower[i] = tolower((unsigned char)s[i]);
    lower[len] = '\0';
    return lower;
}

int str_contains_ci(const char *str, const char *substr) {
    if (!str || !substr) return 0;
    char *lstr = str_tolower(str);
    char *lsub = str_tolower(substr);
    if (!lstr || !lsub) { free(lstr); free(lsub); return 0; }
    int result = (strstr(lstr, lsub) != NULL);
    free(lstr);
    free(lsub);
    return result;
}

int str_contains_any_ci(const char *str, const char *substr) {
    return str_contains_ci(str, substr);
}

char *str_safedup(const char *s) {
    if (!s) return NULL;
    return strdup(s);
}

void str_free(char **s) {
    if (s && *s) {
        free(*s);
        *s = NULL;
    }
}

int terminal_width(void) {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_col > 0)
        return w.ws_col;
    char *cols = getenv("COLUMNS");
    if (cols) {
        int n = atoi(cols);
        if (n > 0) return n;
    }
    return 80;
}

int terminal_height(void) {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_row > 0)
        return w.ws_row;
    char *lines = getenv("LINES");
    if (lines) {
        int n = atoi(lines);
        if (n > 0) return n;
    }
    return 24;
}
