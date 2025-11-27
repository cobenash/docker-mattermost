#!/bin/sh

DATE=$(date +"%Y%m%d_%H%M%S")
FILENAME="mattermost_$DATE.dump"
FILEPATH="/data/$FILENAME"
LOGFILE="/logs/backup_$DATE.log"
CRON_LOG="/logs/cron.log"

echo "[$(date)] Starting PostgreSQL backup..." | tee -a $LOGFILE

####################################
# 1. Log Rotation (cron.log) - Max 5MB
####################################
if [ -f "$CRON_LOG" ]; then
  LOGFILE_SIZE=$(stat -c%s "$CRON_LOG")
  MAXSIZE=$((5 * 1024 * 1024)) # 5MB

  if [ "$LOGFILE_SIZE" -gt "$MAXSIZE" ]; then
    gzip "$CRON_LOG"
    mv "$CRON_LOG.gz" "/logs/cron_$(date +"%Y%m%d_%H%M%S").gz"
    echo "[$(date)] Log rotated due to size > 5MB" > "$CRON_LOG"
  fi
fi

####################################
# 2. Test DB Connection
####################################
pg_isready -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB"
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: PostgreSQL is not ready." | tee -a $LOGFILE
  exit 1
fi

####################################
# 3. Create Dump (Custom Format)
####################################
pg_dump -h postgres -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" -f "$FILEPATH"
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: pg_dump failed." | tee -a $LOGFILE
  rm -f "$FILEPATH"
  exit 1
fi

echo "[$(date)] Backup created: $FILEPATH" | tee -a $LOGFILE

####################################
# 4. Upload to S3
####################################
aws s3 cp "$FILEPATH" "s3://$S3_BUCKET/$S3_PREFIX/$FILENAME"
if [ $? -ne 0 ]; then
  echo "[$(date)] ERROR: S3 upload failed." | tee -a $LOGFILE
  exit 1
fi

echo "[$(date)] Successfully uploaded to S3." | tee -a $LOGFILE

####################################
# 5. KEEP ONLY THE LATEST BACKUP LOCALLY
####################################
echo "[$(date)] Cleaning old local backups..." | tee -a $LOGFILE
ls -t /data/*.dump | awk 'NR>1' | xargs -r rm -f

####################################
# 6. Cleanup Logs older than 7 days
####################################
find /logs -type f -name "backup_*.log" -mtime +7 -exec rm {} \;

echo "[$(date)] Backup completed successfully." | tee -a $LOGFILE
