# php74

CentOS / RHEL 7 上的 PHP 7.4.33 RPM 构建仓库。spec 基于 remi 的源码包改写，在官方停止维护后继续回补安全补丁。

## 结构

| 路径 | 说明 |
| --- | --- |
| `php74.spec` | 唯一的 spec，版本由顶部 `%global upver` / `Release` 控制 |
| `ci/el7/build.sh` | 在 `centos:7` 容器内执行 `rpmbuild` 的完整脚本 |
| `.github/workflows/build-el7.yml` | CI：拉取上游 src.rpm → 构建 → 上传产物 / 推送 package_cloud |

## 构建

CI 会在打 `v*` tag 时自动运行，也可以在 Actions 页面手动 `workflow_dispatch` 触发，并勾选是否推送到 package_cloud（仓库 `wuwx/php74/el/7`）。

本地复现方式与 CI 一致：需要 Docker，并把上游源码包放到 `.ci/input/`。

```bash
mkdir -p .ci/input dist
curl -fsSLO --output-dir .ci/input https://rpms.remirepo.net/SRPMS/php-7.4.33-31.remi.src.rpm
docker run --rm -v "$PWD:/work" -w /work centos:7 bash ci/el7/build.sh
```

产物输出到 `dist/*.rpm`，包含 `php`、`php-cli`、`php-fpm`、`php-common`、`php-devel`、`php-opcache`、`php-litespeed` 及各扩展子包（gd、intl、mbstring、oci8、pdo-*、soap、xml 等）。

构建脚本会先展开 spec，逐一核对引用的 `Source` / `Patch` 是否都在 src.rpm 中，再安装 BuildRequires。为了绕过 EL7 已 EOL 的仓库问题，脚本内置了 vault 归档源和 remi 直连配置；rpm 4.11 缺失的 `bcond_*` 宏也在脚本里补上。

## spec 要点

- 版本固定为 7.4.33，`Release` 与 remi 保持一致，便于对照补丁来源。
- `Patch200+` 为累积的安全补丁（CVE / GHSA），`Patch1~91` 为发行版适配补丁。
- EL7 相关条件分支：Oracle Instant Client 使用 21，不启用 `icu`、`openssl3` 补丁，PCRE 使用源码内置而非系统库。
- `oci8` 默认不构建，需 `--with oci8`（CI 已默认开启）；`zts` 仅在 x86_64 打开；`litespeed` 始终构建。
- CI 用 `--nocheck` 跳过 `%check`，测试补丁（`Patch300+`）仍保留在 spec 中供手动验证。

## 升级上游基线

1. 修改 `%global upver` 与 `Release`。
2. 更新 `.github/workflows/build-el7.yml` 中的 src.rpm 下载地址。
3. 同步 `Patch*` 声明与 `%prep` 中的 `%patch` 顺序。
4. 本地跑一次 `ci/el7/build.sh`，确认脚本的源文件校验通过。
