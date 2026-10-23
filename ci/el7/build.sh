#!/bin/bash
# 在 centos:7 容器内构建 php74.spec；由 .github/workflows/build-el7.yml 调用。
set -euo pipefail

SPEC_SRC=/work/php74.spec
OUT_DIR=/work/dist
TOPDIR=/root/rpmbuild

echo "== 配置 EL7 软件源（全部已 EOL / 归档） =="
rm -f /etc/yum.repos.d/*.repo
cat >/etc/yum.repos.d/ci.repo <<'EOF'
[centos-os]
name=CentOS-7.9.2009 - OS
baseurl=http://vault.centos.org/7.9.2009/os/$basearch/
gpgcheck=0

[centos-updates]
name=CentOS-7.9.2009 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/
gpgcheck=0

[centos-extras]
name=CentOS-7.9.2009 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/
gpgcheck=0

[epel]
name=EPEL 7 (archive)
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/
gpgcheck=0

[remi-safe]
name=Remi's EL7 safe
baseurl=https://rpms.remirepo.net/enterprise/7/safe/$basearch/
gpgcheck=0

[remi-php74]
name=Remi's EL7 php74
baseurl=https://rpms.remirepo.net/enterprise/7/php74/$basearch/
gpgcheck=0

[ol7-instantclient21]
name=Oracle Instant Client 21 for OL7
baseurl=https://yum.oracle.com/repo/OracleLinux/OL7/oracle/instantclient21/$basearch/
gpgcheck=0
EOF

echo "== 补齐 rpm 4.11 缺失的 bcond 宏 =="
mkdir -p /etc/rpm/macros.d
cat >/etc/rpm/macros.d/macros.bcond <<'EOF'
%{!?bcond_with:%define bcond_with() %{expand:%%{?_with_%{1}:%%global with_%{1} 1}}}
%{!?bcond_without:%define bcond_without() %{expand:%%{!?_without_%{1}:%%global with_%{1} 1}}}
EOF

yum -y install yum-plugin-ovl || echo "yum-plugin-ovl 不可用，继续"
yum -y install yum-utils rpm-build tar xz which

echo "== 取 el8 容器解出的 SOURCES =="
SRPM_TREE=/work/.ci/srpm
[ -d "$SRPM_TREE/SOURCES" ] || { echo "缺少 $SRPM_TREE/SOURCES，先跑解包步骤"; exit 1; }
rm -rf "$TOPDIR/SOURCES"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SRPMS,SPECS}
cp -a "$SRPM_TREE/SOURCES" "$TOPDIR/SOURCES"

cp "$SPEC_SRC" "$TOPDIR/SPECS/php74.spec"
SPEC=$TOPDIR/SPECS/php74.spec

echo "== 校验 spec 实际引用的 Source/Patch 是否齐全 =="
# 展开条件分支后才知道 EL7 到底用哪些补丁
rpmspec -P "$SPEC" >/tmp/expanded.spec

: >/tmp/needed.txt
sed -nE 's/^%patch[[:space:]]+-P([0-9]+).*/\1/p' /tmp/expanded.spec | sort -u |
  while read -r n; do
    sed -nE "s/^Patch${n}:[[:space:]]*([^[:space:]]+).*/\1/p" "$SPEC"
  done >>/tmp/needed.txt
grep -oE '%\{SOURCE[0-9]+\}' /tmp/expanded.spec | sort -u | tr -d '{}' | sed 's/^SOURCE//' |
  while read -r n; do
    sed -nE "s/^Source${n}:[[:space:]]*([^[:space:]]+).*/\1/p" "$SPEC"
  done >>/tmp/needed.txt
sed -nE 's/^Source0:[[:space:]]*([^[:space:]]+).*/\1/p' "$SPEC" | xargs -r basename >>/tmp/needed.txt

missing=0
while read -r f; do
  case "$f" in
    http*|ftp*) continue ;;
  esac
  if [ ! -e "$TOPDIR/SOURCES/$f" ]; then
    echo "缺少: $f"
    missing=1
  fi
done </tmp/needed.txt
if [ "$missing" -ne 0 ]; then
  echo "src.rpm 内容与仓库 spec 不匹配"
  exit 1
fi

echo "== 安装 BuildRequires =="
yum-builddep -y "$SPEC"
# oci8 的 BuildRequires 在 %if %{with_oci8} 内，yum-builddep 不认 --with
yum -y install oracle-instantclient-devel

echo "== 开始构建（跳过 %check） =="
rpmbuild -ba --nocheck --with oci8 \
  --define "_topdir $TOPDIR" \
  --define "dist .el7" \
  "$SPEC"

echo "== 收集产物 =="
mkdir -p "$OUT_DIR"
cp "$TOPDIR"/RPMS/*/*.rpm "$OUT_DIR"/
cp "$TOPDIR"/SRPMS/*.src.rpm "$OUT_DIR"/ 2>/dev/null || true
ls -l "$OUT_DIR"
