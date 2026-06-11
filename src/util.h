#ifndef UTIL_H
#define UTIL_H

#include <stddef.h>

extern char *ANSI_RED;
extern char *ANSI_GREEN;
extern char *ANSI_YELLOW;
extern char *ANSI_BLUE;
extern char *ANSI_CYAN;
extern char *ANSI_RESET;

void util_init(void);
void util_cleanup(void);

char *str_trim(char *s);
char *str_tolower(const char *s);
int str_contains_ci(const char *str, const char *substr);
int str_contains_any_ci(const char *str, const char *substr);
char *str_safedup(const char *s);
void str_free(char **s);

int terminal_width(void);
int terminal_height(void);

void term_echo_off(void);
void term_echo_on(void);

#endif
