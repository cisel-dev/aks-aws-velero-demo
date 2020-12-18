BUCKET=velero-01
REGION=eu-west-3
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:latest \
    --bucket $BUCKET \
    --use-restic \
    --secret-file ./credentials-velero \
    --backup-location-config region=$REGION \
    --snapshot-location-config region=$REGION
