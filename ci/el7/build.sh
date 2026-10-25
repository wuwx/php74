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

[epel-archive]
name=EPEL 7 (archive)
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/
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

echo "== 安装 remi-release 并启用 remi =="
yum -y install --nogpgcheck https://rpms.remirepo.net/enterprise/remi-release-7.rpm
# 随之装上的 epel-release 会写入已失效的 mirrorlist，删掉，继续用上面的归档源
rm -f /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-testing.repo
# EL7 EOL 后 mirrorlist 不可靠，改直连 rpms.remirepo.net
sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=|baseurl=|' \
    -e 's|^gpgcheck=1|gpgcheck=0|' /etc/yum.repos.d/remi*.repo
yum-config-manager --enable remi remi-safe >/dev/null

echo "== 解包 src.rpm =="
# rpm -i 会校验签名，el7 的 rpm 4.11 不认 el8 之后的新算法，rpm2cpio 只读 header 和 payload
SRPM=$(ls /work/.ci/input/*.src.rpm | head -n1)
echo "src.rpm: $SRPM"
rm -rf "$TOPDIR/SOURCES"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SRPMS,SPECS,SOURCES}
(
  cd "$TOPDIR/SOURCES"
  rpm2cpio "$SRPM" | cpio -idm --quiet
)
echo "SOURCES 文件数: $(ls "$TOPDIR/SOURCES" | wc -l)"

cp "$SPEC_SRC" "$TOPDIR/SPECS/php74.spec"
SPEC=$TOPDIR/SPECS/php74.spec

echo "== 校验 spec 实际引用的 Source/Patch 是否齐全 =="
# 展开条件分支后才知道 EL7 到底用哪些补丁
if ! rpmspec -P "$SPEC" >/tmp/expanded.spec; then
  echo "rpmspec 解析 spec 失败"
  exit 1
fi

# 展开后 %{SOURCE2} 已变成绝对路径，直接抓 SOURCES 下的文件名
src_refs=$(grep -oE "${TOPDIR}/SOURCES/[^[:space:]\"';]+" /tmp/expanded.spec |
  sed 's#.*/##' | sort -u || true)
tarball=$(sed -nE 's/^Source0:[[:space:]]*([^[:space:]]+).*/\1/p' /tmp/expanded.spec | sed 's#.*/##')
patch_files=$(sed -nE 's/^%patch[[:space:]]+-P([0-9]+).*/\1/p' /tmp/expanded.spec | sort -u |
  while read -r n; do
    sed -nE "s/^Patch${n}:[[:space:]]*([^[:space:]]+).*/\1/p" /tmp/expanded.spec
  done || true)

missing=0
for f in $patch_files $tarball $src_refs; do
  case "$f" in
    http*|ftp*) continue ;;
  esac
  if [ ! -e "$TOPDIR/SOURCES/$f" ]; then
    echo "缺少: $f"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "src.rpm 内容与仓库 spec 不匹配"
  exit 1
fi
echo "OK: 补丁 $(echo "$patch_files" | wc -w) 个，源文件 $(echo "$src_refs" | wc -w) 个"

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
