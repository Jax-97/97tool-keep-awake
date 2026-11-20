#!/bin/bash
# 一次性授权：让「电脑不休眠」App 能开关合盖休眠，以后不再要密码
set -u
cd "$(dirname "$0")" || exit 1

HELPER=/usr/local/bin/keepawake-lid
SUDOERS=/etc/sudoers.d/keepawake
USER_NAME="$(whoami)"

clear
echo "──────────────────────────────────────────────"
echo "  电脑不休眠 · 合盖继续运行 · 一次性授权"
echo "──────────────────────────────────────────────"
echo
echo "接下来会让你输入一次开机密码（输入时屏幕不显示，输完回车）。"
echo "只做两件事："
echo "  1. 写一个只改电源设置的辅助脚本 $HELPER"
echo "  2. 给这个脚本加免密码规则（只限这个脚本，别的命令不受影响）"
echo
read -r -p "准备好了按回车继续（Ctrl+C 取消）... " _

if [ "$(id -u)" != "0" ] && ! sudo -n true 2>/dev/null; then
  echo
  echo "请输入开机密码："
  sudo -v || { echo "密码不正确，已取消。"; read -r -p "按回车关闭窗口... " _; exit 1; }
fi

echo
echo "→ 安装辅助脚本..."
sudo mkdir -p /usr/local/bin
sudo tee "$HELPER" >/dev/null <<'EOS'
#!/bin/sh
# 只做一件事：开关合盖休眠（disablesleep），供「电脑不休眠」App 调用
case "$1" in
  0|1)     exec /usr/bin/pmset -a disablesleep "$1" ;;
  status)  /usr/bin/pmset -g | /usr/bin/grep -i SleepDisabled || echo "SleepDisabled 0" ;;
  *)       echo "usage: keepawake-lid 0|1|status"; exit 2 ;;
esac
EOS
sudo chown root:wheel "$HELPER"
sudo chmod 755 "$HELPER"

echo "→ 添加免密码规则..."
sudo tee "$SUDOERS" >/dev/null <<EOS
$USER_NAME ALL=(root) NOPASSWD: $HELPER "", $HELPER 0, $HELPER 1, $HELPER status
EOS
sudo chown root:wheel "$SUDOERS"
sudo chmod 440 "$SUDOERS"

echo "→ 校验配置..."
if ! sudo visudo -c -f "$SUDOERS"; then
  echo "配置校验失败，已回滚。"
  sudo rm -f "$SUDOERS" "$HELPER"
  read -r -p "按回车关闭窗口... " _
  exit 1
fi

echo "→ 自检（不应该再问密码）..."
if sudo -n "$HELPER" status >/dev/null 2>&1; then
  echo "   通过 ✓"
else
  echo "   免密码规则没生效，请把这段输出发给 Hermes。"
  read -r -p "按回车关闭窗口... " _
  exit 1
fi

echo
echo "──────────────────────────────────────────────"
echo "  完成。回到「电脑不休眠」App 点一下「合盖继续运行」即可。"
echo "  （开关关掉、或关掉 App，都会自动恢复合盖休眠）"
echo "──────────────────────────────────────────────"
read -r -p "按回车关闭窗口... " _
