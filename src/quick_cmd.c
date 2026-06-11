#include "quick_cmd.h"
#include <string.h>
#include <ctype.h>

#define CMD_BUF_SIZE 1024

void quick_cmd_init(quick_cmd_t *qc) {
    memset(qc, 0, sizeof(*qc));
}

static int draw_width(int term_w) {
    int cw = term_w - 16;
    if (cw < 10) cw = 10;
    if (cw > CMD_BUF_SIZE - 1) cw = CMD_BUF_SIZE - 1;
    return cw;
}

void quick_cmd_draw(quick_cmd_t *qc, WINDOW *win, int focus) {
    int max_x;
    getmaxyx(win, max_x, max_x);

    wattron(win, COLOR_PAIR(6));
    whline(win, ' ', max_x);
    wmove(win, 0, 0);
    wattroff(win, COLOR_PAIR(6));

    mvwprintw(win, 0, 1, "Quick Cmd:");

    int cw = draw_width(max_x);
    int bx = 12;
    mvwaddch(win, 0, bx, '[');
    if (focus) {
        wattron(win, A_REVERSE);
        mvwprintw(win, 0, bx + 1, "%-*s", cw, qc->buf);
        wattroff(win, A_REVERSE);
    } else {
        mvwprintw(win, 0, bx + 1, "%-*s", cw, qc->buf);
    }
    mvwaddch(win, 0, bx + 1 + cw, ']');

    int send_x = bx + cw + 3;
    if (qc->send_all) {
        wattron(win, COLOR_PAIR(2) | A_BOLD);
        mvwprintw(win, 0, send_x, "[Send All]");
        wattroff(win, COLOR_PAIR(2) | A_BOLD);
    } else {
        wattron(win, A_DIM);
        mvwprintw(win, 0, send_x, "[Tab:Send]");
        wattroff(win, A_DIM);
    }
}

int quick_cmd_handle(quick_cmd_t *qc, int ch) {
    int cw = draw_width(80);

    if (ch == '\n' || ch == KEY_ENTER) {
        return 2;
    }
    if (ch == 27 || ch == ERR) {
        return 3;
    }
    if (ch == '\t') {
        qc->send_all = !qc->send_all;
        return 1;
    }
    if ((ch == KEY_BACKSPACE || ch == 127 || ch == '\b') && qc->pos > 0) {
        qc->pos--;
        qc->buf[qc->pos] = '\0';
        return 1;
    }
    if (ch >= 32 && ch <= 126 && qc->pos < cw) {
        qc->buf[qc->pos++] = (char)ch;
        qc->buf[qc->pos] = '\0';
        return 1;
    }
    return 0;
}

const char *quick_cmd_get(quick_cmd_t *qc) {
    return qc->buf;
}

int quick_cmd_has_text(quick_cmd_t *qc) {
    return qc->pos > 0;
}

void quick_cmd_clear(quick_cmd_t *qc) {
    qc->pos = 0;
    qc->buf[0] = '\0';
}
