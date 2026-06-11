#ifndef TUI_H
#define TUI_H

#include <ncurses.h>
#include "yaml_parser.h"
#include "term_buf.h"
#include "ssh_pty.h"

void tui_init(void);
void tui_end(void);
int  tui_interactive_list(void);

/* Shared dialog helpers (unchanged) */
WINDOW *create_win(int h, int w, const char *title);
void close_win(WINDOW *win);
int show_confirm_dialog(const char *title, const char *msg);
void show_toast(const char *msg, int color_pair);

/* Menu callbacks (defined in tui.c) */
void menu_add_node(void);
void menu_edit_node(void);
void menu_delete_node(void);
void menu_undo_delete(void);
void menu_export_cfg(void);
void menu_import_cfg(void);
void menu_theme(void);
void menu_help(void);
void menu_quit(void);
void menu_sort_group(void);
void menu_sort_name(void);
void menu_toggle_sidebar(void);
void menu_about(void);
void menu_import_ssh_cfg(void);
void menu_export_ssh_cfg(void);
void menu_validate_cfg(void);

#endif
