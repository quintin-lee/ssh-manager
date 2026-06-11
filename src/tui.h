#ifndef TUI_H
#define TUI_H

#include <ncurses.h>

void tui_init(void);
void tui_end(void);
int tui_interactive_list(void);

WINDOW *create_win(int h, int w, const char *title);
void close_win(WINDOW *win);
int show_confirm_dialog(const char *title, const char *msg);
void show_toast(const char *msg, int color_pair);

#endif
