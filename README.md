# 可観測性プラットフォーム 導入ガイド

このドキュメントは、Daprベースの可観測性プラットフォームの概念、ツール構成、および具体的なアプリケーションでの利用方法を解説するものです。

このv2スタックは、`setup.sh` を不要にする「名前付きボリューム」への移行、`.env` ファイルによるシークレット管理、および `Langfuse` (LLMOps) やS3ストレージ（`rclone`）をオプションとして柔軟に追加できるモジュラー（分割）構成を特徴としています。

## 0\. 👁️ 可観測性の主要な概念

システムの状態を把握するために、私たちは「3本柱」と呼ばれるデータを収集します。

### メトリクス (Metrics)

  * **概要:** システムの「健康状態」を示す、全体の状況を把握するための**定期的な数値**です。
  * **例:** CPU使用率、メモリ使用量、1秒あたりのリクエスト数、エラー率。

### トレース (Traces)

  * **概要:** 1つのリクエストが、システム内の複数のサービスを通過していく「**全行動記録**」です。リクエストがどこでどれだけ時間を使ったかを追跡します。
  * **例:** ユーザーが「注文ボタン」を押してから完了するまでに、`frontend` (50ms) → `order-service` (300ms) → `payment-service` (500ms) と処理が流れた全工程の記録。

### ログ (Logs)

  * **概要:** システム内で発生した「特定の出来事」を記録した、タイムスタンプ付きの**テキスト**です。
  * **例:** `INFO: User 'admin' logged in.`、`ERROR: Database connection failed.`

-----

## 1\. 🛠️ ツールと役割

この3本柱（およびGenAIの観測）を収集・保存・可視化するために、以下のツール群が連携しています。

### 必須コンポーネント (Base Stack)

| ツール             | ライセンス | 役割                 | 担当するデータ                                                |
| :----------------- | :--------- | :------------------- | :------------------------------------------------------------ |
| **Grafana**        | AGPL v3.0  | **可視化 (UI)**      | 3本柱すべてを閲覧する唯一の画面。                             |
| **Grafana Tempo**  | AGPL v3.0  | **トレースの保存**   | `トレース` を保存する専用DB（デフォルトはローカル）。         |
| **Prometheus**     | Apache 2.0 | **メトリクスの保存** | `メトリクス` を保存する専用DB。                               |
| **OpenSearch**     | Apache 2.0 | **ログの保存**       | `ログ` を保存する専用DB（書庫）。                             |
| **Fluent Bit**     | Apache 2.0 | **ログ収集**         | `ログ` を集めてOpenSearchに配送する。                         |
| **OTel Collector** | Apache 2.0 | **データハブ**       | 全てのデータをDaprやSDKから受け取り、仕分けする「中央受付」。 |

### オプションコンポーネント (Optional Add-ons)

| ツール           | ライセンス | 役割               | 担当するデータ                                             |
| :--------------- | :--------- | :----------------- | :--------------------------------------------------------- |
| **Langfuse**     | MIT        | **可視化 (GenAI)** | **GenAIの `トレース`, `プロンプト`, `評価` を閲覧。**      |
| **PostgreSQL**   | PostgreSQL | **メタデータDB**   | Langfuse, MLflow, Dagster のメタデータ（少量）を保存。     |
| **rclone S3 GW** | MIT        | **ストレージGW**   | Langfuse, Tempo 等の大容量データを Google Drive 等に保存。 |

### データの流れ

1.  **Dapr/SDK** → **OTel Collector**
      * `インフラトレース` → **Tempo** → (デフォルト: ローカル, オプション: rclone S3)
      * `メトリクス` → **Prometheus** (ローカル)
      * `インフラログ` → **Fluent Bit** → **OpenSearch** (ローカル)
2.  **GenAI App (SDK)** → **Langfuse Server** (オプション)
      * `GenAIメタデータ` → **PostgreSQL** (オプション)
      * `GenAIログ本文` → **rclone S3** (オプション)

-----

## 2\. 🚀 起動手順 (プラットフォーム管理者向け)

このスタックはモジュール化されています。`docker compose` コマンドで、必要な `.yml` ファイルを選択して起動します。

### 2.1. 事前準備 (初回のみ)

1.  **リポジトリのクローン:**

    ```bash
    git clone https://git.company.com/observability-platform.git
    cd observability-platform
    ```

2.  **シークレットファイル (.env) の作成 (必須):**
    `docker-compose` ファイル群と同じ階層に `.env` ファイルを作成し、必要なパスワード等を設定します。このファイルは `.gitignore` されており、Gitで管理されません。

    ```bash
    # .env.example があればコピー、なければ手動で作成
    # cp .env.example .env 
    vim .env 
    ```

    *(.envファイルに必要な最小限のキーについては、`docker-compose.backends.yml` や `langfuse.yml` を参照してください)*

3.  **(オプション) rclone の設定:**
    `rclone` S3 ゲートウェイ (Google Drive) を使用する場合は、`config/rclone/rclone.conf` をローカルの `rclone config` コマンドで生成・配置する必要があります。このファイルも `.gitignore` されています。

4.  **(廃止) setup.sh の実行:**
    このv2スタックでは、`setup.sh` は**不要になりました**。`./data` ディレクトリ への書き込み権限設定は、Docker の「名前付きボリューム」機能によって自動的に処理されるため、ホスト側での事前作業は一切必要ありません。

### 2.2. 起動コマンド例

`-f` オプションで、起動したい構成ファイルをすべて指定します。

  * **例1: 基本スタック (デフォルト)**
    (メトリクス、ログ、および **ローカル保存のトレース** が起動)

    ```bash
    docker compose -f docker-compose.base.yml up -d
    ```

  * **例2: 基本スタック + Langfuse (GenAI用)**
    (Langfuse が Postgres と rclone を必要とするため `backends.yml` を含めます)

    ```bash
    docker compose \
      -f docker-compose.base.yml \
      -f docker-compose.backends.yml \
      -f docker-compose.langfuse.yml \
      up -d
    ```

  * **例3: 全部入り (基本 + Langfuse + S3版Tempo)**
    (トレースデータも Google Drive に保存する構成。`tempo-s3.yml` が `base.yml` のTempo定義を上書きします)

    ```bash
    docker compose \
      -f docker-compose.base.yml \
      -f docker-compose.backends.yml \
      -f docker-compose.langfuse.yml \
      -f docker-compose.tempo-s3.yml \
      up -d
    ```

### 2.3. 動作確認

  * `docker compose ps` ですべてのコンテナが `Up (running)` または `Up (healthy)` になっていることを確認します。
  * ブラウザで `http://localhost:3000` (Grafana) を開きます (ID/PW: `admin` / `admin`)。
  * (Langfuse起動時) `http://localhost:3001` (Langfuse) を開きます。
  * `http://localhost:9090` (Prometheus) や `http://localhost:9200` (OpenSearch) も直接確認できます。

-----

## 3\. 📦 新規プロジェクトへの導入方法 (開発者向け)

このセクションは、**新しいマイクロサービスやプロジェクトを開発する際**に、上記で起動した共通可観測性プラットフォームに接続するための手順です。

### 3.1. Dapr と SDK の設定 (インフラ観測性)

Dapr（サービス間）とOpenTelemetry SDK（サービス内部）の両方から、`otel-collector` サービスにデータを送信します。

**1. ネットワークと Dapr の設定 (マクロ観測性)**
プロジェクトの `docker-compose.yml` を設定し、各サービスとDaprサイドカーが、あらかじめ起動している `observability-net` ネットワークに参加するようにします。
`dapr-config.yml` で、`otel` エンドポイントを `otel-collector:4317` に指定します。

**`docker-compose.yml` (プロジェクト側の記述例):**

```yaml
services:
  my-app:
    # ...
    environment:
      - DAPR_HTTP_PORT=3500
      # ★ 3.2で設定するSDKが参照するエンドポイント
      - OTEL_COLLECTOR_ENDPOINT=otel-collector:4317
    networks:
      - default
      - observability-net # ★ 共通ネットワークに参加

  my-app-dapr:
    image: "daprio/daprd:1.12"
    command:
      - "./daprd"
      - "-app-id"
      - "my-app"
      # ...
      - "-config"
      - "/config/dapr-config.yml" # ★ dapr-config.yml を指定
    volumes:
      - ./dapr-config.yml:/config/dapr-config.yml # ★ マウント
    networks:
      - default
      - observability-net # ★ 共通ネットワークに参加
    depends_on:
      - otel-collector # 外部のotel-collectorを認識させる

# 共通ネットワークとサービスを 'external' として定義
networks:
  observability-net:
    external: true
  default:
    driver: bridge

services:
  otel-collector: # depends_on で使うため
    external: true
```

**2. アプリケーション SDK の設定 (ミクロ観測性)**
サービス「内部」の詳細な処理（関数呼び出し、DBクエリ）を可視化するには、アプリケーションコードに **OpenTelemetry (OTel) SDK** を導入します。

**`setup_observability.py` (共通モジュール例):**

```python
import logging
import os
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk.logs.export import BatchLogRecordProcessor

# docker-compose.yml で設定した OTEL_COLLECTOR_ENDPOINT を参照
OTEL_COLLECTOR_ENDPOINT = os.getenv("OTEL_COLLECTOR_ENDPOINT", "localhost:4317")

def setup_observability(service_name: str):
    """OpenTelemetryのトレースとログをセットアップする"""
    
    resource = Resource(attributes={"service.name": service_name})

    # --- トレース (Tempo行き) のセットアップ ---
    tracer_provider = TracerProvider(resource=resource)
    span_exporter = OTLPSpanExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
    tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))
    trace.set_tracer_provider(tracer_provider)
    
    # --- ログ (OpenSearch行き) のセットアップ ---
    logger_provider = LoggerProvider(resource=resource)
    log_exporter = OTLPLogExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))

    # Python標準のloggingモジュールにOTelハンドラを追加
    handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
    logging.getLogger().addHandler(handler)
```

**`main.py` (FastAPIでの使用例):**

```python
import logging
from fastapi import FastAPI
from opentelemetry import trace
from setup_observability import setup_observability

# --- 1. アプリケーションの起動 ---
setup_observability(service_name="my-python-service")

app = FastAPI()
tracer = trace.get_tracer(__name__)

@app.get("/")
def read_root():
    # 1. 手動でスパンを作成
    with tracer.start_as_current_span("read_root_span") as span:
        # 2. このログは自動的に trace_id と span_id を持つ
        logging.info("ルートエンドポイントが呼び出されました。")
        span.set_attribute("http.method", "GET")
        return {"hello": "world"}
```

### 3.2. GenAI アプリケーション (Langfuse) の設定

`docker-compose.langfuse.yml` を起動している場合、GenAI アプリケーションから Langfuse SDK を使ってトレースを送信できます。

```python
import os
from langfuse import Langfuse

# Langfuse サーバーのホスト (Docker内部からではない場合 localhost)
os.environ["LANGFUSE_HOST"] = "http://localhost:3001" 
# Langfuse プロジェクトの公開鍵・秘密鍵 (UIから取得)
os.environ["LANGFUSE_PUBLIC_KEY"] = "pk-lf-..."
os.environ["LANGFUSE_SECRET_KEY"] = "sk-lf-..."

langfuse = Langfuse()

# LLM呼び出しをトレース
generation = langfuse.generation(
    name="summary-generation",
    input="User prompt...",
    output="LLM response...",
    model="gpt-4"
)
```

### 3.3. MLflow / Dagster との統合

`docker-compose.backends.yml` を起動している場合、MLflow や Dagster のバックエンドとして、`postgres-metadata` (メタデータ用) と `rclone-s3-gateway` (成果物用) を指定できます。

**MLflow (環境変数設定例):**

```bash
# 1. メタデータDB (Postgres) を指定
export MLFLOW_TRACKING_URI="postgresql://mlflow_user:mlflow_pass@postgres-metadata:5432/mlflow_db"

# 2. 成果物ストレージ (rclone S3) を指定
export MLFLOW_S3_ENDPOINT_URL="http://rclone-s3-gateway:9000"
export AWS_ACCESS_KEY_ID="obs-user" # .env の RCLONE_S3_USER
export AWS_SECRET_ACCESS_KEY="obs-password" # .env の RCLONE_S3_PASS
```

**Dagster (`dagster.yaml` 設定例):**

```yaml
# $DAGSTER_HOME/dagster.yaml

run_storage:
  module: dagster_postgres.run_storage
  config:
    postgres_db:
      username: "dagster_user"
      password: "dagster_pass"
      hostname: "postgres-metadata"
      db_name: "dagster_db"
      port: 5432

event_log_storage:
  module: dagster_postgres.event_log
  config:
    postgres_db:
      username: "dagster_user"
      password: "dagster_pass"
      hostname: "postgres-metadata"
      db_name: "dagster_db"
      port: 5432

# (I/O Manager や Compute Log に rclone S3 を設定)
compute_log_storage:
  module: dagster_aws.s3.compute_log_manager
  config:
    bucket: "dagster-logs"
    s3_endpoint: "http://rclone-s3-gateway:9000"
    s3_key: "obs-user"
    s3_secret: "obs-password"
```