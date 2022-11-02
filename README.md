# ssh-manager

基于 expect 工具实现 ssh 自动登陆服务器, 管理服务器 ssh 连接

## 1. ArchLinux/Manjaro 发行版打包

```shell
git clone https://github.com/quintin-lee/ssh-manager.git

cd ssh-manager
makepkg
```

## 2. 安装

``` shell
sudo pacman -U 包名

在 PATH 中加入 /usr/local/ssh-manager
```

## 3. 使用

### 3.1 配置

在 /usr/local/ssh-manager/host.conf 文件中添加 ssh 连接信息, 如下：

```shell
# server            host/ip             user            possword            port
localhost           127.0.0.1           root            123456              22
```

### 3.2 连接

运行 ssh-connect, 选择要练的服务器即可自动连接到服务器

```shell
$ ssh-connect
1) localhost
Enter a number[1-1]:1
spawn ssh root@192.168.28.93 -p 22
The authenticity of host '192.168.28.93 (192.168.28.93)' can't be established.
ED25519 key fingerprint is SHA256:g56ErKDN0Ypa1o3kx7DVFb3l2uDcPMJQQAN8muLeocE.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.28.93' (ED25519) to the list of known hosts.
root@192.168.28.93's password: 
Activate the web console with: systemctl enable --now cockpit.socket

Last login: Wed Oct 26 03:28:24 2022 from 192.168.4.182
[root@bogon ~]# export TERM=xterm
[root@bogon ~]#
```
