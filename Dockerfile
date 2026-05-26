# 模拟项目要求的 Linux 嵌入式环境 [cite: 4]
FROM ubuntu:22.04

# 设置环境变量，避免安装时的交互弹窗
ENV DEBIAN_FRONTEND=noninteractive

# 安装成员 A 和 B 脚本运行的核心工具 
RUN apt-get update && apt-get install -y \
    cron \
    bash \
    sed \
    gawk \
    mailutils \
    && rm -rf /var/lib/apt/lists/*

# 设置项目专用的工作目录
WORKDIR /app/Linux-Course-Project

# 将本地当前目录下的所有脚本和配置拷贝进镜像 [cite: 16, 30]
COPY . .

# 赋予所有 .sh 脚本执行权限
RUN chmod +x *.sh

# 启动 cron 守护进程，支持项目的 7x24 小时运行目标 [cite: 12, 18]
CMD ["cron", "-f"]
