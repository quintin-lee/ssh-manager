#ifndef SSH_PTY_H
#define SSH_PTY_H

#include "yaml_parser.h"
#include <sys/types.h>

typedef struct {
    pid_t pid;
    int master_fd;
    int rows, cols;
    int active;
} ssh_pty_t;

int  ssh_pty_start(ssh_pty_t *s, const node_t *n, int rows, int cols);
int  ssh_pty_read(ssh_pty_t *s, char *buf, int size);
int  ssh_pty_write(ssh_pty_t *s, const char *data, int len);
void ssh_pty_stop(ssh_pty_t *s);
void ssh_pty_resize(ssh_pty_t *s, int rows, int cols);
int  ssh_pty_alive(ssh_pty_t *s);

#endif
