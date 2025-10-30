# 社内共通 可観測性プラットフォーム 導入ガイド

このドキュメントは、私たちが構築したDaprベースの可観測性プラットフォームの概念、ツール構成、および具体的なアプリケーションでの利用方法を解説するものです。

* **UI (可視化):** Grafana (AGPL v3.0)
* **トレース:** Grafana Tempo (AGPL v3.0)
* **メトリクス:** Prometheus (Apache 2.0)
* **ログ:** OpenSearch (Apache 2.0)
* **ログ収集:** Fluent Bit (Apache 2.0)
* **データハブ:** OpenTelemetry Collector (Apache 2.0)


## 0. 👁️ 可観測性の主要な概念

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

---

## 2. 🛠️ ツールと役割

この3本柱を収集・保存・可視化するために、以下のツール群が連携しています。

| ツール             | ライセンス | 役割                 | 担当するデータ                                                |
| :----------------- | :--------- | :------------------- | :------------------------------------------------------------ |
| **Grafana**        | AGPL v3.0  | **可視化 (UI)**      | 3本柱すべてを閲覧する唯一の画面。                             |
| **Grafana Tempo**  | AGPL v3.0  | **トレースの保存**   | `トレース` を保存する専用DB。                                 |
| **Prometheus**     | Apache 2.0 | **メトリクスの保存** | `メトリクス` を保存する専用DB。                               |
| **OpenSearch**     | Apache 2.0 | **ログの保存**       | `ログ` を保存する専用DB（書庫）。                             |
| **Fluent Bit**     | Apache 2.0 | **ログ収集**         | `ログ` を集めてOpenSearchに配送する。                         |
| **OTel Collector** | Apache 2.0 | **データハブ**       | 全てのデータをDaprやSDKから受け取り、仕分けする「中央受付」。 |

**データの流れ:**

1.  **Dapr**が `トレース` `メトリクス` を生成 → **OTel Collector** に送信。また、**アプリ (SDK)** が `トレース` `メトリクス` `ログ` を生成 → **OTel Collector** に送信
2.  **OTel Collector** がデータを仕分け
    * `トレース` → **Tempo** へ
    * `メトリクス` → **Prometheus** へ
    * `ログ` → **Fluent Bit** へ
3.  **Fluent Bit** が `ログ` を **OpenSearch** へ
4.  **Grafana** が **Tempo**, **Prometheus**, **OpenSearch** の3つを読み込んで表示

---

## 1. 🚀 起動手順 (プラットフォーム管理者向け)

このセクションは、可観測性スタック（Grafana, Tempo, OpenSearch等）自体をホストマシン（ローカルPCまたは共有サーバー）で起動するためのものです。**全プロジェクト共通で、通常は1回だけ実行します。**

手順2,3は、 `setup.sh` を実行すればよい。

1.  **リポジトリのクローン:**
    ```bash
    git clone [https://git.company.com/observability-platform.git](https://git.company.com/observability-platform.git)
    cd observability-platform
    ```

2.  **データ保存ディレクトリの作成:**
    （このスタックは全データを `./data` ディレクトリに永続化します）
    ```bash
    mkdir -p ./data/grafana
    mkdir -p ./data/opensearch
    mkdir -p ./data/prometheus
    mkdir -p ./data/tempo
    ```

3.  **ディレクトリ権限の設定 (必須):**
    GrafanaとOpenSearchは特定のユーザーIDで実行されるため、ホスト側のディレクトリに書き込み権限を与える必要があります。

    ```bash
    # Grafana (UID 472)
    sudo chown -R 472:472 ./data/grafana

    # OpenSearch (UID 1000)
    sudo chown -R 1000:1000 ./data/opensearch

    # Prometheus (UID 65534)
    sudo chown -R 65534:65534 ./data/prometheus

    # Grafana Tempo (UID 10001)
    sudo chown -R 10001:10001 ./data/tempo
    ```

4.  **スタックの起動:**
    ```bash
    docker compose -f docker-compose.observability.yml up -d
    ```

5.  **動作確認:**
    * `docker compose -f docker-compose.observability.yml ps` ですべてのコンテナが `Up (running)` または `Up (healthy)` になっていることを確認します。
    * ブラウザで `http://localhost:3000` (Grafana) を開きます。
    * ID/PW: `admin` / `admin` でログインします。
    * [⚙️ Administration] > [Data sources] を開き、**Prometheus**, **Tempo**, **OpenSearch** の3つが自動で登録され、「Connection test OK」となっていることを確認します。

---

## 2. 📦 新規プロジェクトへの導入方法 (開発者向け)

このセクションは、**新しいマイクロサービスやプロジェクトを開発する際**に、上記で起動した共通可観測性プラットフォームに接続するための手順です。

### 2.1. ネットワークとDaprの設定 (マクロ観測性)

まず、プロジェクトの `docker-compose.yml` を設定し、Daprが自動的にサービス間通信（マクロ）をトレースできるようにします。

1.  **共通ネットワークへの参加:**
    プロジェクトの `docker-compose.yml` で、各サービスとDaprサイドカーが、あらかじめ起動している `observability-net` ネットワークに参加するように設定します。

2.  **Dapr設定ファイルのコピー:**
    このリポジトリの `project-templates/dapr-config.yml` を、あなたのプロジェクトのルートにコピーします。このファイルは、Daprに「トレースとメトリクスを `otel-collector:4317` に送信する」よう指示します。

3.  **Daprサイドカーの起動:**
    `docker-compose.yml` で、アプリ本体のコンテナ（例: `my-app`）の隣に、Daprサイドカー（`my-app-dapr`）を定義します。

**`docker-compose.yml` (プロジェクト側の記述例):**

```yaml
version: '3.8'

services:
  # 1. 自分のアプリケーション
  my-app:
    build: .
    container_name: my-app
    environment:
      - APP_PORT=8000
      - DAPR_HTTP_PORT=3500
      # ★ 2.2で設定するSDKが参照するエンドポイント
      - OTEL_COLLECTOR_ENDPOINT=otel-collector:4317
    networks:
      - default
      - observability-net # ★ 共通ネットワークに参加

  # 2. アプリに対応するDaprサイドカー
  my-app-dapr:
    image: "daprio/daprd:1.12"
    container_name: my-app-dapr
    command:
      - "./daprd"
      - "-app-id"
      - "my-app"
      - "-app-port"
      - "8000"
      - "-config"
      - "/config/dapr-config.yml" # ★ コピーした設定ファイルを指定
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

---

### 2.2. アプリケーションSDKの設定 (ミクロ観測性)

Daprはサービス「間」の通信しか見えません。サービス「内部」の詳細な処理（関数呼び出し、DBクエリ、内部ロジック）を可視化するには、アプリケーションコードに **OpenTelemetry (OTel) SDK** を導入します。

**目的:**

  * アプリ内部のカスタムスパン（トレース）を **Tempo** に送信する。
  * Pythonの `logging` で出力したログに `trace_id` を自動付与し、**OpenSearch** に送信する。

**Pythonでの共通セットアップ:**
以下のライブラリを `requirements.txt` に追加します。

```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp
```

**`setup_observability.py` (共通モジュール例):**
（この関数をアプリの起動時に1回だけ呼び出します）

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

# OTel Collectorのエンドポイントを環境変数から取得
# (docker-compose.yml で設定した OTEL_COLLECTOR_ENDPOINT)
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
    
    # (オプション) FastAPIなどのライブラリログもキャプチャする
    logging.getLogger("uvicorn.access").addHandler(handler)
    logging.getLogger("uvicorn.error").addHandler(handler)

```

-----

### 2.3. 具体的な利用例 (Python)

#### 2.3.1. FastAPI + 標準ロギング

**目的:** FastAPIのエンドポイント内で `logging.info` を呼ぶと、Daprが生成したトレースIDと自動で紐づくようにします。

**`main.py` (FastAPIの例):**

```python
import logging
from fastapi import FastAPI
from opentelemetry import trace

# 上記の共通モジュールをインポート
from setup_observability import setup_observability

# --- 1. アプリケーションの起動 ---
setup_observability(service_name="my-python-service")

app = FastAPI()
tracer = trace.get_tracer(__name__)

# --- 2. アプリケーションコードでの使用 ---

@app.get("/")
def read_root():
    # 1. 手動でスパン (トレースの一部) を作成
    # Daprが親スパンを生成しているので、これは子スパンになる
    with tracer.start_as_current_span("read_root_span") as span:
        
        # 2. このログは自動的に trace_id と span_id を持つ
        logging.info("ルートエンドポイントが呼び出されました。")
        
        # 3. スパンに属性を追加
        span.set_attribute("http.method", "GET")
        
        internal_processing()
        
        logging.warning("処理が完了しました。")
        return {"hello": "world"}

@tracer.start_as_current_span("internal_processing") # デコレータでも可
def internal_processing():
    """内部の重い処理（ダミー）"""
    logging.info("内部処理を開始します...")
    # ... 重い処理 ...
    logging.info("内部処理が完了しました。")
```

**結果:** `read_root` へのリクエストトレース（Tempo）と、その処理中に出力されたログ（OpenSearch）が、Grafana上で自動的に紐付けられます。

#### 2.3.2. MLflow との統合

**目的:** MLflowの実験（Run）をトレースとしてTempoに送信します。

**コンセプト:** MLflowは**ネイティブなOpenTelemetryサポート**を持っています。`pip` でSDKをインストールし、環境変数を設定するだけで、`mlflow.start_run` や `mlflow.start_span` が自動的にトレースをOTel Collectorに送信します。

**`train.py` (MLflowの例):**

```python
import mlflow
import os
import logging
from sklearn.ensemble import RandomForestClassifier

# --- 1. OTel Collectorへの接続設定 (環境変数) ---
# Dockerコンテナ起動時、またはコードの先頭で設定

# 私たちのスタックのOTel Collector (gRPC) のエンドポイント
# ★ MLflowはHTTPをデフォルトにすることがあるため、gRPCを明示
os.environ["OTEL_EXPORTER_OTLP_PROTOCOL"] = "grpc"
os.environ["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] = os.getenv("OTEL_COLLECTOR_ENDPOINT", "otel-collector:4317")
os.environ["OTEL_SERVICE_NAME"] = "ml-trainer"

# (もし 2.2 の logging セットアップも実行されていれば、
#  このスクリプトのログも OpenSearch に送信される)
# from setup_observability import setup_observability
# setup_observability(service_name="ml-trainer")

# --- 2. MLflowコード (SDKによるラップは不要) ---

def start_ml_training():
    try:
        # MLflowのRunを開始 (これがOTelの親スパンになる)
        with mlflow.start_run() as run:
            run_id = run.info.run_id
            logging.info(f"MLflow Run (ID: {run_id}) を開始しました。")

            # MLflowの 'span' を使う (これが子スパンになる)
            with mlflow.start_span(name="data_preparation") as s:
                logging.info("データ準備スパン")
                s.set_inputs({"raw_data": "path/to/data"})
                s.set_outputs({"processed_data": "path/to/processed"})

            # ... 学習と評価 ...
            accuracy = 0.95
            mlflow.log_metric("accuracy", accuracy)
            logging.info(f"MLflow Run (ID: {run_id}) が正常に完了しました。")

    except Exception as e:
        logging.error(f"MLflow Run でエラーが発生: {e}", exc_info=True)

if __name__ == "__main__":
    start_ml_training()
```

**結果:** MLflowのRunとSpanが、自動的にTempoにトレースとして記録されます。

#### 2.3.3. Dagster との統合

**目的:** DagsterのOp（処理）やGraph（パイプライン）の実行を、自動的にトレースとして計測します。

**コンセプト:** Dagsterも**ネイティブなOpenTelemetryサポート**を提供しています。`dagster.yaml` を設定するだけで、コードを変更する必要はありません。

**ステップ1: ライブラリのインストール**

```bash
pip install dagster-opentelemetry
```

**ステップ2: `dagster.yaml` の設定**
Dagsterのインスタンス設定ファイル（`$DAGSTER_HOME/dagster.yaml`）に、`telemetry` ブロックを追加します。

```yaml
# $DAGSTER_HOME/dagster.yaml

telemetry:
  opentelemetry:
    enabled: true
    # 'dagster' というサービス名でOTelに登録
    resource_attributes:
      service.name: "dagster" 
    
    # --- OTLP Exporter の設定 ---
    # 送信先はOTel Collector
    otlp_endpoint: "otel-collector:4317" # docker-compose.ymlの環境変数とは無関係
    otlp_protocol: "grpc"
    # (私たちのスタックは認証不要なので headers は空)
    # otlp_headers: {}
```

**ステップ3: Dagsterコード (変更不要)**
DagsterのOpやGraphのコードは、**一切変更する必要がありません**。`context.log` が自動的にトレースと紐付きます。

```python
# my_dagster_project/assets.py
from dagster import op, job

@op
def my_first_op(context):
    # このログは自動的にトレースと紐付き、OpenSearchに送られる
    context.log.info("Dagster Op (my_first_op) が実行されました。")
    return "hello"

@op
def my_second_op(context, input_str):
    context.log.info(f"次の入力を受け取りました: {input_str}")
    return input_str + " world"

@job
def my_pipeline():
    my_second_op(my_first_op())
```

**結果:** `my_pipeline` の実行全体が親スパン、各Opが子スパンとしてTempoに記録され、`context.log` の内容がOpenSearchに記録されます。
