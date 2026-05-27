#!/bin/sh
# One-shot bucket bootstrap for SeaweedFS.
#
# Tempo, Loki, and MLflow all need their buckets to exist before they start
# (the S3 SDKs they use will not auto-create on first write).
#
# Idempotent: running again is a no-op once the buckets exist.

set -eu

ENDPOINT="${S3_ENDPOINT:-http://seaweedfs:8333}"
# Honour AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY from compose env (which
# pulls from S3_ACCESS_KEY / S3_SECRET_KEY in .env). Fall back to `any`
# when nothing is set, matching the default identities config.
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-any}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-any}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Wait for SeaweedFS to respond before issuing mb commands.
i=0
until aws --endpoint-url "$ENDPOINT" s3 ls >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "seaweedfs S3 endpoint never came up at $ENDPOINT"
    exit 1
  fi
  echo "waiting for seaweedfs ($i)..."
  sleep 2
done

for bucket in tempo-traces loki-logs mlflow-artifacts prometheus-blocks; do
  if aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "bucket exists: $bucket"
  else
    aws --endpoint-url "$ENDPOINT" s3 mb "s3://$bucket"
    echo "created bucket: $bucket"
  fi
done

echo "all buckets ready"
