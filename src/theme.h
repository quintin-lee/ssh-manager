#ifndef THEME_H
#define THEME_H

typedef struct {
    const char *name;
    const char *label;
    int red;
    int green;
    int yellow;
    int blue;
    int cyan;
} theme_t;

extern theme_t g_themes[];
extern int g_theme_count;
extern int g_theme_idx;

void theme_apply(int idx);
int theme_choose_interactive(void);

#endif
