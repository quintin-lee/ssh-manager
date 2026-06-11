#ifndef MENU_H
#define MENU_H

#include <ncurses.h>

void menu_bar_init(void);
void menu_bar_draw(WINDOW *win);
int  menu_bar_handle_key(int ch);
int  menu_bar_active(void);

#endif
