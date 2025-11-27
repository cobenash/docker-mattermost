#!/bin/bash

DATE=$(date +"%Y%m%d_%H%M%S")
FILENAME="mattermost_$DATE.dump"
FILEPATH="/data/$FILENAME"
LOGFILE="/logs/backup_$DATE.log"

echo "[$(date)] Starting PostgreSQL backup..." | tee -a $LOGFILE

# 1. 測試連線是否正常
pg_isready -h postgres -U $POSTGRES_USER
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: PostgreSQL is not ready." | tee -a $LOGFILE
  exit 1
fi

# 2. 開始備份（custom format，最穩定）
pg_dump -h postgres -U $POSTGRES_USER -Fc $POSTGRES_DB -f $FILEPATH
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: pg_dump failed." | tee -a $LOGFILE
  rm -f $FILEPATH
  exit 1
fi

echo "[$(date)] Backup created: $FILEPATH" | tee -a $LOGFILE

# 3. 上傳至 S3
aws s3 cp $FILEPATH s3://$S3_BUCKET/$S3_PREFIX/$FILENAME
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: S3 upload failed." | tee -a $LOGFILE
  exit 1
fi

echo "[$(date)] Successfully uploaded to S3." | tee -a $LOGFILE

# 4. 自動清除 7 天前的本地備份
find /data -type f -mtime +7 -exec rm {} \;

echo "[$(date)] Backup completed successfully." | tee -a $LOGFILE
