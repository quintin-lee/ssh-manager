#ifndef TERM_BUF_H
#define TERM_BUF_H

#include <ncurses.h>

#define SCROLLBACK_MAX 1000
#define TAB_STOP 8

typedef struct {
    int rows, cols;
    int cursor_y, cursor_x;
    int scroll_pos;
    int attr;
    int fg, bg;

    char *chars;
    unsigned *attrs;
    int write_head;
    int filled_rows;
} term_buf_t;

void term_buf_init(term_buf_t *tb, int rows, int cols);
void term_buf_free(term_buf_t *tb);
void term_buf_resize(term_buf_t *tb, int rows, int cols);
void term_buf_feed(term_buf_t *tb, const char *data, int len);
void term_buf_scroll(term_buf_t *tb, int delta);
void term_render(term_buf_t *tb, WINDOW *win, int focus);

#endif
