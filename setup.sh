#!/bin/bash

# スクリプトがエラーで停止するように設定
set -e

echo "データディレクトリのセットアップを開始します..."

# -d: ディレクトリを作成
# -o: 所有ユーザーをUIDで指定
# -g: 所有グループをGIDで指定
# -m: パーミッションを指定 (755が一般的です)

# Grafana (UID 472)
echo "Grafana (./data/grafana) をセットアップ中 (Owner: 472:472)..."
sudo install -d -o 472 -g 472 -m 755 ./data/grafana

# OpenSearch (UID 1000)
echo "OpenSearch (./data/opensearch) をセットアップ中 (Owner: 1000:1000)..."
sudo install -d -o 1000 -g 1000 -m 755 ./data/opensearch

# Prometheus (UID 65534)
echo "Prometheus (./data/prometheus) をセットアップ中 (Owner: 65534:65534)..."
sudo install -d -o 65534 -g 65534 -m 755 ./data/prometheus

# Grafana Tempo (UID 10001)
echo "Tempo (./data/tempo) をセットアップ中 (Owner: 10001:10001)..."
sudo install -d -o 10001 -g 10001 -m 755 ./data/tempo

echo "セットアップが完了しました。"