#include "ssh.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

static const char *expect_script_tpl =
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
    "            \"*password:*\" { puts \"密码错误\"; set exit_code 2 }\n"
    "            \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }\n"
    "            \"*Last login*\" { }\n"
    "            timeout { puts \"登录后超时\"; set exit_code 1 }\n"
    "        }\n"
    "    }\n"
    "    \"*passphrase*\" {\n"
    "        send -- \"$pass\\r\"\n"
    "        expect {\n"
    "            \"*passphrase*\" { puts \"密钥短语错误\"; set exit_code 2 }\n"
    "            \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }\n"
    "            \"*Last login*\" { }\n"
    "            timeout { puts \"登录后超时\"; set exit_code 1 }\n"
    "        }\n"
    "    }\n"
    "    \"*yes/no*\" { send \"yes\\r\"; exp_continue }\n"
    "    \"*Connection refused*\" { puts \"连接被拒绝\"; set exit_code 3 }\n"
    "    \"*No route to host*\" { puts \"主机不可达\"; set exit_code 4 }\n"
    "    \"*Connection timed out*\" { puts \"连接超时\"; set exit_code 1 }\n"
    "    \"*Host key verification failed*\" { puts \"主机密钥验证失败\"; set exit_code 5 }\n"
    "    \"*Could not resolve hostname*\" { puts \"无法解析主机名\"; set exit_code 6 }\n"
    "    timeout { puts \"连接超时\"; set exit_code 1 }\n"
    "    eof { catch wait result; set exit_code [lindex $result 3] }\n"
    "}\n"
    "if {$exit_code == 0} {\n"
    "    interact\n"
    "    catch wait result; set exit_code [lindex $result 3]\n"
    "}\n"
    "exit $exit_code\n";

int ssh_connect(const node_t *node) {
    if (!node || !node->host || node->host[0] == '\0') {
        printf("%s无效节点: 缺少主机信息%s\n", ANSI_RED, ANSI_RESET);
        return 1;
    }

    printf("%s>>> 连接中: %s (%s)...%s\n", ANSI_YELLOW,
           node->name ? node->name : "?", node->host, ANSI_RESET);
    fflush(stdout);

    /* Set environment variables for expect script */
    setenv("SSH_PASS", node->pass ? node->pass : "", 1);
    setenv("SSH_HOST", node->host, 1);
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", node->port);
    setenv("SSH_PORT", port_str, 1);
    setenv("SSH_USER", node->user ? node->user : "root", 1);
    setenv("SSH_KEY", node->keypath ? node->keypath : "", 1);
    setenv("SSH_AUTH_TYPE", node->type ? node->type : "pass", 1);

    pid_t pid = fork();
    if (pid == -1) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        execlp("expect", "expect", "-c", expect_script_tpl, (char *)NULL);
        perror("execlp expect");
        _exit(127);
    }

    int status;
    waitpid(pid, &status, 0);

    /* Clean up sensitive env vars */
    unsetenv("SSH_PASS");
    unsetenv("SSH_HOST");
    unsetenv("SSH_PORT");
    unsetenv("SSH_USER");
    unsetenv("SSH_KEY");
    unsetenv("SSH_AUTH_TYPE");

    if (WIFEXITED(status)) {
        int exit_code = WEXITSTATUS(status);
        if (exit_code != 0) {
            switch (exit_code) {
                case 1: printf("%s连接超时%s\n", ANSI_RED, ANSI_RESET); break;
                case 2: printf("%s认证失败%s\n", ANSI_RED, ANSI_RESET); break;
                case 3: printf("%s连接被拒绝%s\n", ANSI_RED, ANSI_RESET); break;
                case 4: printf("%s主机不可达%s\n", ANSI_RED, ANSI_RESET); break;
                case 5: printf("%s主机密钥验证失败%s\n", ANSI_RED, ANSI_RESET); break;
                case 6: printf("%s无法解析主机名%s\n", ANSI_RED, ANSI_RESET); break;
                default: printf("%s连接异常退出 (%d)%s\n", ANSI_RED, exit_code, ANSI_RESET); break;
            }
        }
        return exit_code;
    }

    return 1;
}
