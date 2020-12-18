# Generate a self-signed cert
openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout tlsgitlab.key -out tlsgitlab.crt -subj "/CN=gitlab.example.com" -days 365
kubectl -n gitlab create secret tls gitlab-example-com --cert=tlsgitlab.crt --key=tlsgitlab.key

# GitLab Installation via Helm
kubectl create ns gitlab
helm --namespace gitlab install gitlab gitlab/gitlab \
  --set certmanager.install=false \
  --set global.ingress.configureCertmanager=false \
  --set global.ingress.tls.secretName=gitlab-example-com \
  --set global.hosts.domain=example.com \
  --set global.hosts.gitlab.name=gitlab.example.com \
  --set global.hosts.registry.name=registry.example.com \
  --set global.hosts.minio.name=minio.example.com \
  --set gitlab-runner.install=false \
  --set global.minio.enabled=false \
  --set global.appConfig.omniauth.enabled=true \
  --set global.appConfig.omniauth.allowSingleSignOn=true \
  --set global.edition=ce

# Get GitLab web root password
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode ; echo

# Annotate pods to allow Velero to backup their PV with restic
kubectl annotate pod/gitlab-postgresql-0 backup.velero.io/backup-volumes=data -n gitlab
kubectl annotate pod/gitlab-gitaly-0 backup.velero.io/backup-volumes=repo-data -n gitlab
