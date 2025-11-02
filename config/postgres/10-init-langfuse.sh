#!/bin/bash
set -e

# .env -> backends.yml から渡された $POSTGRES_USER (スーパーユーザー) を使って接続
# .env -> langfuse.yml から渡された $LANGFUSE_DB... 変数を使ってDB作成

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    CREATE USER ${LANGFUSE_DB_USER} WITH PASSWORD '${LANGFUSE_DB_PASS}';
    CREATE DATABASE ${LANGFUSE_DB_NAME};
    GRANT ALL PRIVILEGES ON DATABASE ${LANGFUSE_DB_NAME} TO ${LANGFUSE_DB_USER};
EOSQL