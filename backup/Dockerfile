FROM alpine:3.21

RUN apk add --no-cache bash dcron postgresql16-client tar gzip findutils curl jq

WORKDIR /app

COPY crontab /etc/crontabs/root
COPY entrypoint.sh backup-db.sh backup-n8n-data.sh export-workflows.sh /app/
RUN chmod +x /app/entrypoint.sh /app/backup-db.sh /app/backup-n8n-data.sh /app/export-workflows.sh

ENTRYPOINT ["/app/entrypoint.sh"]
