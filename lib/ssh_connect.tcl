# ============================================================================
# ssh_connect.tcl — Expect-based SSH auto-login helper
#
# Called from lib/ssh.sh to automate SSH connections. Receives credentials
# via environment variables set by the calling bash process.
#
# Environment variables consumed:
#   SSH_USER   — SSH login username
#   SSH_HOST   — target hostname/IP
#   SSH_PORT   — target port (default 22)
#   SSH_PASS   — password (may be empty for key auth)
#   SSH_KEY    — path to SSH private key (may be empty)
#
# Exit codes:
#   0 — session ended normally (user exited shell)
#   1 — connection timeout
#   2 — authentication failed (wrong password or permission denied)
#   3 — connection refused
#   4 — host unreachable
#   5 — host key verification failed
#   6 — DNS resolution failed
#
# The __SSH_EXTRA__ placeholder is substituted at runtime by bash for
# additional SSH options (e.g. -i <keypath>). The __PASSPHRASE_BRANCH__
# placeholder inserts expect logic for key passphrase prompts.
# ============================================================================
set timeout 30
set pass $env(SSH_PASS)
set host $env(SSH_HOST)
set port $env(SSH_PORT)
set user $env(SSH_USER)
set key $env(SSH_KEY)
set exit_code 0

spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 __SSH_EXTRA__ -p $port $user@$host
expect {
    "*password:*" {
        send -- "$pass\r"
        expect {
            "*password:*" { puts "密码错误"; set exit_code 2 }
            "*Permission denied*" { puts "认证失败"; set exit_code 2 }
            "*Last login*" { }
            timeout { puts "登录后超时"; set exit_code 1 }
        }
    }__PASSPHRASE_BRANCH__
    "*yes/no*" { send "yes\r"; exp_continue }
    "*Connection refused*" { puts "连接被拒绝"; set exit_code 3 }
    "*No route to host*" { puts "主机不可达"; set exit_code 4 }
    "*Connection timed out*" { puts "连接超时"; set exit_code 1 }
    "*Host key verification failed*" { puts "主机密钥验证失败"; set exit_code 5 }
    "*Could not resolve hostname*" { puts "无法解析主机名"; set exit_code 6 }
    timeout { puts "连接超时"; set exit_code 1 }
    eof { catch wait result; set exit_code [lindex $result 3] }
}
if {$exit_code == 0} {
    interact
    catch wait result; set exit_code [lindex $result 3]
}
exit $exit_code
