#!/usr/bin/env bash
set -euo pipefail

# =========================================================================
#  Laboratorio 6 - GitOps: preparacion de GCP (equivalente al bootstrap de
#  Azure de la guia). Se ejecuta UNA SOLA VEZ y A MANO desde Cloud Shell.
#
#  Crea: 3 proyectos, el bucket del estado de Terraform, la cuenta de
#  servicio, el Workload Identity Pool con su provider OIDC de GitHub,
#  las 4 "credenciales federadas" y los permisos minimos.
# =========================================================================

# ---- Cambie solo estas lineas (respete mayusculas y minusculas) ----------
GH_USER="JuanLeal05"
GH_REPO="PENU-gitops-lab"
SUFIJO="juanleal"           # se pega a los IDs de proyecto: deben ser unicos
BILLING_ACCOUNT=""         # obtengalo con: gcloud billing accounts list
REGION="us-central1"
# -------------------------------------------------------------------------

PROJ_STATE="gitops-state-${SUFIJO}"
PROJ_DEV="gitops-dev-${SUFIJO}"
PROJ_PROD="gitops-prod-${SUFIJO}"
SA_NAME="sa-gitops-github"
SA_EMAIL="${SA_NAME}@${PROJ_STATE}.iam.gserviceaccount.com"
POOL="gh-pool"
PROVIDER="gh-provider"
BUCKET_TFSTATE="tfstate-gitops-${SUFIJO}"

if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "Falta BILLING_ACCOUNT. Ejecute: gcloud billing accounts list"
  exit 1
fi

echo "1/6 Proyectos"
for p in "$PROJ_STATE" "$PROJ_DEV" "$PROJ_PROD"; do
  gcloud projects create "$p" --name="$p" 2>/dev/null || echo "   ($p ya existe)"
  gcloud billing projects link "$p" --billing-account="$BILLING_ACCOUNT" >/dev/null
done

echo "2/6 APIs necesarias"
gcloud services enable \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  storage.googleapis.com cloudresourcemanager.googleapis.com \
  --project="$PROJ_STATE"
for p in "$PROJ_DEV" "$PROJ_PROD"; do
  gcloud services enable storage.googleapis.com cloudresourcemanager.googleapis.com \
    --project="$p"
done

echo "3/6 Bucket del estado de Terraform"
# Equivale al contenedor tfstate de Azure: versionado, acceso uniforme y
# bloqueo de acceso publico. El bloqueo de concurrencia es nativo del backend gcs.
gcloud storage buckets create "gs://${BUCKET_TFSTATE}" \
  --project="$PROJ_STATE" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention 2>/dev/null \
  || echo "   (el bucket ya existe)"
gcloud storage buckets update "gs://${BUCKET_TFSTATE}" --versioning

echo "4/6 Cuenta de servicio (la 'identidad administrada')"
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJ_STATE" --display-name="GitOps GitHub Actions" 2>/dev/null \
  || echo "   (la cuenta ya existe)"

echo "5/6 Workload Identity Federation (OIDC con GitHub)"
gcloud iam workload-identity-pools create "$POOL" \
  --project="$PROJ_STATE" --location="global" \
  --display-name="GitHub Actions" 2>/dev/null || echo "   (el pool ya existe)"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$PROJ_STATE" --location="global" --workload-identity-pool="$POOL" \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository=='${GH_USER}/${GH_REPO}'" \
  2>/dev/null || echo "   (el provider ya existe)"

POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL" \
  --project="$PROJ_STATE" --location="global" --format="value(name)")

# GitHub ahora emite el "sub" del JWT con identificadores numericos
# (repo:USUARIO@ID/REPO@ID:...). Los leemos de la API publica para que la
# condicion coincida exactamente. Se registran los dos formatos (con y sin
# identificadores) por compatibilidad, igual que el script original de Azure.
GH_JSON=$(curl -fsS "https://api.github.com/repos/${GH_USER}/${GH_REPO}") || {
  echo "No encontre github.com/${GH_USER}/${GH_REPO}. Cree primero el repositorio (publico) y revise GH_USER y GH_REPO."
  exit 1
}
OWNER=$(echo "$GH_JSON" | jq -r .owner.login); OWNER_ID=$(echo "$GH_JSON" | jq -r .owner.id)
REPO=$(echo "$GH_JSON" | jq -r .name); REPO_ID=$(echo "$GH_JSON" | jq -r .id)

PREFIX_ID="repo:${OWNER}@${OWNER_ID}/${REPO}@${REPO_ID}"
PREFIX_NOMBRE="repo:${OWNER}/${REPO}"

# Las cuatro "credenciales federadas": un binding por cada subject que
# GitHub puede emitir. Nadie mas puede suplantar la cuenta de servicio.
# Se otorgan DOS roles por cada combinacion: workloadIdentityUser autoriza
# quien puede intentar actuar como la identidad; serviceAccountTokenCreator
# autoriza a pedir el token en si. Owner del proyecto NO incluye este
# segundo permiso por defecto, asi que hay que concederlo explicitamente.
for PREFIJO in "$PREFIX_ID" "$PREFIX_NOMBRE"; do
  for SUBJ in "pull_request" "ref:refs/heads/main" "environment:dev" "environment:prod"; do
    MEMBER="principal://iam.googleapis.com/${POOL_ID}/subject/${PREFIJO}:${SUBJ}"
    gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
      --project="$PROJ_STATE" \
      --role="roles/iam.workloadIdentityUser" \
      --member="$MEMBER" \
      >/dev/null
    gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
      --project="$PROJ_STATE" \
      --role="roles/iam.serviceAccountTokenCreator" \
      --member="$MEMBER" \
      >/dev/null
    echo "   subject autorizado: ${PREFIJO}:${SUBJ}"
  done
done

echo "6/6 Permisos minimos"
# Equivale a 'Contributor solo sobre rg-gitops-dev y rg-gitops-prod'.
for p in "$PROJ_DEV" "$PROJ_PROD"; do
  gcloud projects add-iam-policy-binding "$p" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin" >/dev/null
done
# Equivale a 'Storage Blob Data Contributor solo sobre el contenedor tfstate'.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_TFSTATE}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin" >/dev/null

PROVIDER_FULL="${POOL_ID}/providers/${PROVIDER}"

echo
echo "Cree estas seis variables en GitHub (Settings > Secrets and variables"
echo "> Actions > pestana Variables):"
echo "  GCP_WIF_PROVIDER    = ${PROVIDER_FULL}"
echo "  GCP_SERVICE_ACCOUNT = ${SA_EMAIL}"
echo "  GCP_PROJECT_DEV     = ${PROJ_DEV}"
echo "  GCP_PROJECT_PROD    = ${PROJ_PROD}"
echo "  GCP_REGION          = ${REGION}"
echo "  TFSTATE_BUCKET      = ${BUCKET_TFSTATE}"