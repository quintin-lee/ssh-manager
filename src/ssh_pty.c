#include "ssh_pty.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <pty.h>
#include <utmp.h>

static const char *expect_script =
    "set timeout 30\n"
    "set pass $env(SSH_PASS)\n"
    "set host $env(SSH_HOST)\n"
    "set port $env(SSH_PORT)\n"
    "set user $env(SSH_USER)\n"
    "set key $env(SSH_KEY)\n"
    "set auth_type $env(SSH_AUTH_TYPE)\n"
    "set exit_code 0\n"
    "\n"
    "set ssh_cmd \"ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p $port $user@$host\"\n"
    "if {$auth_type eq \"key\" && $key ne \"\"} {\n"
    "    set ssh_cmd \"ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -i \\\"$key\\\" -p $port $user@$host\"\n"
    "}\n"
    "\n"
    "eval spawn $ssh_cmd\n"
    "expect {\n"
    "    \"*password:*\" {\n"
    "        send -- \"$pass\\r\"\n"
    "        expect {\n"
    "            \"*password:*\" { puts \"\\033[31mWrong password\\033[0m\"; set exit_code 2 }\n"
    "            \"*Permission denied*\" { puts \"\\033[31mAuth failed\\033[0m\"; set exit_code 2 }\n"
    "            \"*Last login*\" { }\n"
    "            timeout { puts \"\\033[31mTimeout after login\\033[0m\"; set exit_code 1 }\n"
    "        }\n"
    "    }\n"
    "    \"*passphrase*\" {\n"
    "        send -- \"$pass\\r\"\n"
    "        expect {\n"
    "            \"*passphrase*\" { puts \"\\033[31mBad passphrase\\033[0m\"; set exit_code 2 }\n"
    "            \"*Permission denied*\" { puts \"\\033[31mAuth failed\\033[0m\"; set exit_code 2 }\n"
    "            \"*Last login*\" { }\n"
    "            timeout { puts \"\\033[31mTimeout after login\\033[0m\"; set exit_code 1 }\n"
    "        }\n"
    "    }\n"
    "    \"*yes/no*\" { send \"yes\\r\"; exp_continue }\n"
    "    \"*Connection refused*\" { puts \"\\033[31mConnection refused\\033[0m\"; set exit_code 3 }\n"
    "    \"*No route to host*\" { puts \"\\033[31mHost unreachable\\033[0m\"; set exit_code 4 }\n"
    "    \"*Connection timed out*\" { puts \"\\033[31mConnection timed out\\033[0m\"; set exit_code 1 }\n"
    "    \"*Host key verification failed*\" { puts \"\\033[31mHost key failed\\033[0m\"; set exit_code 5 }\n"
    "    \"*Could not resolve hostname*\" { puts \"\\033[31mDNS failed\\033[0m\"; set exit_code 6 }\n"
    "    timeout { puts \"\\033[31mConnection timeout\\033[0m\"; set exit_code 1 }\n"
    "    eof { catch wait result; set exit_code [lindex $result 3] }\n"
    "}\n"
    "if {$exit_code == 0} {\n"
    "    interact\n"
    "    catch wait result; set exit_code [lindex $result 3]\n"
    "}\n"
    "exit $exit_code\n";

int ssh_pty_start(ssh_pty_t *s, const node_t *n, int rows, int cols) {
    if (!n || !n->host || !n->host[0]) return -1;

    struct winsize ws;
    ws.ws_row = rows;
    ws.ws_col = cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    pid_t pid = forkpty(&s->master_fd, NULL, NULL, &ws);
    if (pid == -1) return -1;

    if (pid == 0) {
        setenv("SSH_PASS", n->pass ? n->pass : "", 1);
        setenv("SSH_HOST", n->host, 1);
        char port_str[16];
        snprintf(port_str, sizeof(port_str), "%d", n->port);
        setenv("SSH_PORT", port_str, 1);
        setenv("SSH_USER", n->user ? n->user : "root", 1);
        setenv("SSH_KEY", n->keypath ? n->keypath : "", 1);
        setenv("SSH_AUTH_TYPE", n->type ? n->type : "pass", 1);

        execlp("expect", "expect", "-c", expect_script, (char *)NULL);
        _exit(127);
    }

    s->pid = pid;
    s->rows = rows;
    s->cols = cols;
    s->active = 1;
    return 0;
}

int ssh_pty_read(ssh_pty_t *s, char *buf, int size) {
    if (!s->active) return 0;
    int n = (int)read(s->master_fd, buf, (size_t)size);
    if (n <= 0) {
        s->active = 0;
        return 0;
    }
    return n;
}

int ssh_pty_write(ssh_pty_t *s, const char *data, int len) {
    if (!s->active) return -1;
    return (int)write(s->master_fd, data, (size_t)len);
}

void ssh_pty_stop(ssh_pty_t *s) {
    if (!s->active) return;
    s->active = 0;
    kill(s->pid, SIGHUP);
    usleep(50000);
    kill(s->pid, SIGTERM);
    int status;
    waitpid(s->pid, &status, WNOHANG);
    close(s->master_fd);
}

void ssh_pty_resize(ssh_pty_t *s, int rows, int cols) {
    if (!s->active) return;
    struct winsize ws;
    ws.ws_row = rows;
    ws.ws_col = cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(s->master_fd, TIOCSWINSZ, &ws);
    s->rows = rows;
    s->cols = cols;
}

int ssh_pty_alive(ssh_pty_t *s) {
    if (!s->active) return 0;
    int status;
    pid_t r = waitpid(s->pid, &status, WNOHANG);
    if (r == s->pid) {
        s->active = 0;
        close(s->master_fd);
        return 0;
    }
    return 1;
}
