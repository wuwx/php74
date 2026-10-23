#!/bin/bash
# src.rpm 是 el8 打的，el7 的 rpm 4.11 读不了，改用 el8 容器展开 SOURCES。
set -euo pipefail

INPUT_DIR=/work/.ci/input
OUT_DIR=/work/.ci/srpm

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

SRPM=$(ls "$INPUT_DIR"/*.src.rpm | head -n1)
echo "src.rpm: $SRPM"
rpm -i --nodeps --nosignature --define "_topdir $OUT_DIR" "$SRPM"

echo "SOURCES 文件数: $(ls "$OUT_DIR/SOURCES" | wc -l)"
