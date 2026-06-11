#include "term_buf.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define ATTR_BOLD     0x0100
#define ATTR_DIM      0x0200
#define ATTR_REVERSE  0x0400
#define ATTR_UNDERLINE 0x0800
#define ATTR_BLINK    0x1000
#define ATTR_PAIR(n)  ((n) & 0x00FF)

static unsigned build_attr(int pair, int bold, int dim, int rev, int ul, int blink) {
    unsigned a = pair & 0xFF;
    if (bold)  a |= ATTR_BOLD;
    if (dim)   a |= ATTR_DIM;
    if (rev)   a |= ATTR_REVERSE;
    if (ul)    a |= ATTR_UNDERLINE;
    if (blink) a |= ATTR_BLINK;
    return a;
}

static void apply_attr(WINDOW *win, unsigned a) {
    int pair = a & 0xFF;
    unsigned attr = 0;
    if (a & ATTR_BOLD)      attr |= A_BOLD;
    if (a & ATTR_DIM)       attr |= A_DIM;
    if (a & ATTR_REVERSE)   attr |= A_REVERSE;
    if (a & ATTR_UNDERLINE) attr |= A_UNDERLINE;
    if (a & ATTR_BLINK)     attr |= A_BLINK;
    if (pair) attr |= COLOR_PAIR(pair);
    if (attr) wattron(win, attr);
}

static void unapply_attr(WINDOW *win, unsigned a) {
    int pair = a & 0xFF;
    if (a & ATTR_BOLD)      wattroff(win, A_BOLD);
    if (a & ATTR_DIM)       wattroff(win, A_DIM);
    if (a & ATTR_REVERSE)   wattroff(win, A_REVERSE);
    if (a & ATTR_UNDERLINE) wattroff(win, A_UNDERLINE);
    if (a & ATTR_BLINK)     wattroff(win, A_BLINK);
    if (pair) wattroff(win, COLOR_PAIR(pair));
}

static int ansi_to_ncurses_pair(int ansi_fg, int ansi_bg) {
    static const int map[] = {0, 1, 2, 3, 4, 5, 6, 7};
    if (ansi_fg < 0 || ansi_fg > 7) ansi_fg = 7;
    if (ansi_bg < 0 || ansi_bg > 7) ansi_bg = 0;
    return map[ansi_fg];
}

static void clear_row(term_buf_t *tb, int row) {
    int off = row * tb->cols;
    memset(tb->chars + off, 0, (size_t)tb->cols);
    memset(tb->attrs + off, 0, sizeof(unsigned) * (size_t)tb->cols);
}

void term_buf_init(term_buf_t *tb, int rows, int cols) {
    memset(tb, 0, sizeof(*tb));
    tb->rows = rows;
    tb->cols = cols;
    tb->fg = 7;
    tb->bg = 0;
    tb->chars = calloc((size_t)SCROLLBACK_MAX * (size_t)cols, 1);
    tb->attrs = calloc((size_t)SCROLLBACK_MAX * (size_t)cols, sizeof(unsigned));
}

void term_buf_free(term_buf_t *tb) {
    free(tb->chars);
    free(tb->attrs);
    memset(tb, 0, sizeof(*tb));
}

void term_buf_resize(term_buf_t *tb, int rows, int cols) {
    (void)rows;
    tb->cols = cols;
    tb->rows = rows;
}

static void newline(term_buf_t *tb) {
    tb->write_head = (tb->write_head + 1) % SCROLLBACK_MAX;
    clear_row(tb, tb->write_head);
    tb->cursor_x = 0;
    if (tb->filled_rows < SCROLLBACK_MAX)
        tb->filled_rows++;
}

static void put_char(term_buf_t *tb, char c) {
    int off = tb->write_head * tb->cols + tb->cursor_x;
    if (tb->cursor_x >= tb->cols) return;
    tb->chars[off] = c;
    tb->attrs[off] = build_attr(
        ansi_to_ncurses_pair(tb->fg, tb->bg),
        tb->attr & A_BOLD ? 1 : 0,
        tb->attr & A_DIM ? 1 : 0,
        tb->attr & A_REVERSE ? 1 : 0,
        tb->attr & A_UNDERLINE ? 1 : 0,
        tb->attr & A_BLINK ? 1 : 0
    );
    tb->cursor_x++;
    if (tb->cursor_x >= tb->cols)
        newline(tb);
}

void term_buf_feed(term_buf_t *tb, const char *data, int len) {
    enum { STATE_NORMAL, STATE_ESC, STATE_CSI } st = STATE_NORMAL;
    char csi_buf[64];
    int csi_len = 0;

    for (int i = 0; i < len; i++) {
        unsigned char c = (unsigned char)data[i];

        switch (st) {
            case STATE_NORMAL:
                if (c == '\033') {
                    st = STATE_ESC;
                } else if (c == '\r') {
                    tb->cursor_x = 0;
                } else if (c == '\n') {
                    newline(tb);
                } else if (c == '\b' && tb->cursor_x > 0) {
                    tb->cursor_x--;
                } else if (c == '\t') {
                    int next = (tb->cursor_x / TAB_STOP + 1) * TAB_STOP;
                    while (tb->cursor_x < next && tb->cursor_x < tb->cols)
                        put_char(tb, ' ');
                } else if (c >= 32) {
                    put_char(tb, (char)c);
                }
                break;

            case STATE_ESC:
                if (c == '[') {
                    st = STATE_CSI;
                    csi_len = 0;
                    memset(csi_buf, 0, sizeof(csi_buf));
                } else if (c == ']') {
                    st = STATE_NORMAL;
                } else {
                    st = STATE_NORMAL;
                }
                break;

            case STATE_CSI:
                if (c >= 0x20 && c <= 0x2F) {
                    if (csi_len < (int)sizeof(csi_buf) - 1)
                        csi_buf[csi_len++] = (char)c;
                } else if (c >= 0x30 && c <= 0x7E) {
                    csi_buf[csi_len++] = (char)c;
                    csi_buf[csi_len] = '\0';
                    char final = (char)c;

                    if (final == 'm') {
                        char *p = csi_buf;
                        while (*p && *p >= 0x20 && *p <= 0x2F) p++;
                        if (*p == '\0') {
                            tb->attr = A_NORMAL;
                            tb->fg = 7;
                            tb->bg = 0;
                        } else {
                            char *tok = strtok(p, ";");
                            while (tok) {
                                int val = atoi(tok);
                                if (val == 0) { tb->attr = A_NORMAL; tb->fg = 7; tb->bg = 0; }
                                else if (val == 1) tb->attr |= A_BOLD;
                                else if (val == 2) tb->attr |= A_DIM;
                                else if (val == 4) tb->attr |= A_UNDERLINE;
                                else if (val == 5) tb->attr |= A_BLINK;
                                else if (val == 7) tb->attr |= A_REVERSE;
                                else if (val == 22) tb->attr &= ~A_BOLD;
                                else if (val == 24) tb->attr &= ~A_UNDERLINE;
                                else if (val == 25) tb->attr &= ~A_BLINK;
                                else if (val == 27) tb->attr &= ~A_REVERSE;
                                else if (val >= 30 && val <= 37) tb->fg = val - 30;
                                else if (val == 39) tb->fg = 7;
                                else if (val >= 40 && val <= 47) tb->bg = val - 40;
                                else if (val == 49) tb->bg = 0;
                                else if (val >= 90 && val <= 97) tb->fg = val - 90;
                                else if (val >= 100 && val <= 107) tb->bg = val - 100;
                                tok = strtok(NULL, ";");
                            }
                        }
                    } else if (final == 'K') {
                        int off = tb->write_head * tb->cols + tb->cursor_x;
                        memset(tb->chars + off, 0, (size_t)(tb->cols - tb->cursor_x));
                        memset(tb->attrs + off, 0, sizeof(unsigned) * (size_t)(tb->cols - tb->cursor_x));
                    } else if (final == 'J') {
                        int off = tb->write_head * tb->cols + tb->cursor_x;
                        memset(tb->chars + off, 0, (size_t)(tb->cols - tb->cursor_x));
                        memset(tb->attrs + off, 0, sizeof(unsigned) * (size_t)(tb->cols - tb->cursor_x));
                    } else if (final == 'H' || final == 'f') {
                        int r = 0, c2 = 0;
                        if (csi_buf[0]) sscanf(csi_buf, "%d;%d", &r, &c2);
                        if (r > 0) r--;
                        if (c2 > 0) c2--;
                        tb->cursor_y = r;
                        tb->cursor_x = c2;
                        if (tb->cursor_y < 0) tb->cursor_y = 0;
                        if (tb->cursor_x < 0) tb->cursor_x = 0;
                        if (tb->cursor_x >= tb->cols) tb->cursor_x = tb->cols - 1;
                    } else if (final == 'A') {
                        int n = csi_buf[0] ? atoi(csi_buf) : 1;
                        tb->cursor_y -= n;
                        if (tb->cursor_y < 0) tb->cursor_y = 0;
                    } else if (final == 'B') {
                        int n = csi_buf[0] ? atoi(csi_buf) : 1;
                        tb->cursor_y += n;
                    } else if (final == 'C') {
                        int n = csi_buf[0] ? atoi(csi_buf) : 1;
                        tb->cursor_x += n;
                        if (tb->cursor_x >= tb->cols) tb->cursor_x = tb->cols - 1;
                    } else if (final == 'D') {
                        int n = csi_buf[0] ? atoi(csi_buf) : 1;
                        tb->cursor_x -= n;
                        if (tb->cursor_x < 0) tb->cursor_x = 0;
                    }
                    st = STATE_NORMAL;
                } else {
                    st = STATE_NORMAL;
                }
                break;
        }
    }
}

void term_buf_scroll(term_buf_t *tb, int delta) {
    int max_scroll = tb->filled_rows > tb->rows ? tb->filled_rows - tb->rows : 0;
    tb->scroll_pos += delta;
    if (tb->scroll_pos < 0) tb->scroll_pos = 0;
    if (tb->scroll_pos > max_scroll) tb->scroll_pos = max_scroll;
}

void term_render(term_buf_t *tb, WINDOW *win, int focus) {
    int rows, cols;
    getmaxyx(win, rows, cols);

    int display_rows = rows < tb->rows ? rows : tb->rows;
    int start_row;
    if (tb->filled_rows < SCROLLBACK_MAX) {
        start_row = tb->scroll_pos;
    } else {
        start_row = (tb->write_head + 1 + tb->scroll_pos) % SCROLLBACK_MAX;
    }

    for (int r = 0; r < display_rows; r++) {
        int src = (start_row + r) % SCROLLBACK_MAX;
        wmove(win, r, 0);
        int buf_off = src * tb->cols;

        for (int c = 0; c < cols && c < tb->cols; c++) {
            unsigned a = tb->attrs[buf_off + c];
            char ch = tb->chars[buf_off + c];
            int cursor_here = (focus && r == tb->cursor_y && c == tb->cursor_x);

            if (cursor_here) {
                apply_attr(win, a);
                waddch(win, ch ? ch : ' ');
                unapply_attr(win, a);
                wattroff(win, A_REVERSE);
            } else if (ch) {
                apply_attr(win, a);
                waddch(win, ch);
                unapply_attr(win, a);
            } else {
                waddch(win, ' ');
            }
        }
        wclrtoeol(win);

        /* Cursor beyond last column */
        if (focus && r == tb->cursor_y && tb->cursor_x >= cols)
            mvwaddch(win, r, cols - 1, ' ' | A_REVERSE);
    }
}
