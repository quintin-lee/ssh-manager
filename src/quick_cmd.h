#ifndef QUICK_CMD_H
#define QUICK_CMD_H

#include <ncurses.h>

typedef struct {
    char buf[1024];
    int pos;
    int send_all;
} quick_cmd_t;

void quick_cmd_init(quick_cmd_t *qc);
void quick_cmd_draw(quick_cmd_t *qc, WINDOW *win, int focus);
int  quick_cmd_handle(quick_cmd_t *qc, int ch);
const char *quick_cmd_get(quick_cmd_t *qc);
int  quick_cmd_has_text(quick_cmd_t *qc);
void quick_cmd_clear(quick_cmd_t *qc);

#endif
