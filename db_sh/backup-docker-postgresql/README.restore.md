# pgbackup-docker 恢复指南

备份文件是 `pg_dump -Fc` 的自定义格式，可直接用 `pg_restore` 恢复到容器内 PostgreSQL。

## 基础恢复（覆盖已有库）
```bash
# 替换路径/容器/用户/库名/密码
DUMP_FILE="/home/user/backups/postgres/pgbackup_trade-postgresql_MyDB_20240101_120000.dump"
CONTAINER="trade-postgresql"
DB_USER="sean"
DB_NAME="MyDB"
DB_PASSWORD="1dU4JDFW7OyeMrfm"

cat "$DUMP_FILE" \
  | docker exec -i -e "PGPASSWORD=$DB_PASSWORD" "$CONTAINER" \
      pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists
```
- `--clean --if-exists` 会在导入前清理对象，适合覆盖式恢复。
- 如果库不存在，先在容器里创建：`docker exec "$CONTAINER" createdb -U "$DB_USER" "$DB_NAME"`.

## 导入到新库（留存旧库）
```bash
NEW_DB="MyDB_restored"
docker exec "$CONTAINER" createdb -U "$DB_USER" "$NEW_DB"
cat "$DUMP_FILE" \
  | docker exec -i -e "PGPASSWORD=$DB_PASSWORD" "$CONTAINER" \
      pg_restore -U "$DB_USER" -d "$NEW_DB"
```

## 只恢复特定 schema/table（可选）
```bash
# 只恢复某个 schema
pg_restore_opts="--schema=public"
# 或只恢复单表
# pg_restore_opts="--table=public.my_table"

cat "$DUMP_FILE" \
  | docker exec -i -e "PGPASSWORD=$DB_PASSWORD" "$CONTAINER" \
      pg_restore -U "$DB_USER" -d "$DB_NAME" $pg_restore_opts --clean --if-exists
```

## 查看 dump 内容（不导入）
```bash
pg_restore -l "$DUMP_FILE" | head
```

## 说明
- 使用与你备份时相同的 `DB_USER/DB_NAME/CONTAINER_NAME/DB_PASSWORD`。可直接复用 `config.env` 里的值。
- 若开启了 `PG_DUMP_OPTIONS`（默认 `-Z9` 压缩），恢复命令不需要额外解压，`pg_restore` 会自动处理。
- 恢复操作前建议先备份当前库或导入到新库验证。 
