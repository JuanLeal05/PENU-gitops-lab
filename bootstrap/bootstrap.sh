#!/usr/bin/env bash
set -euo pipefail

# ---- Cambie solo estas dos líneas (respete mayúsculas y minúsculas) ----
GH_USER="su-usuario-github"
GH_REPO="gitops-lab"
# -------------------------------------------------------------------------

LOC="eastus2"
RG_STATE="rg-gitops-state"
RG_DEV="rg-gitops-dev"
RG_PROD="rg-gitops-prod"
SA="stgitops$(openssl rand -hex 4)"
IDN="id-gitops-github"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "1/5 Grupos de recursos"
for rg in "$RG_STATE" "$RG_DEV" "$RG_PROD"; do
  az group create --name "$rg" --location "$LOC" --output none
done

echo "2/5 Almacenamiento del estado de Terraform"
az storage account create --resource-group "$RG_STATE" --name "$SA" \
  --location "$LOC" --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false \
  --allow-shared-key-access false --output none
az storage account blob-service-properties update \
  --resource-group "$RG_STATE" --account-name "$SA" \
  --enable-versioning true --output none
az storage container-rm create --resource-group "$RG_STATE" \
  --storage-account "$SA" --name tfstate --output none

echo "3/5 Identidad administrada"
az identity create --resource-group "$RG_STATE" --name "$IDN" \
  --location "$LOC" --output none
CLIENT_ID=$(az identity show -g "$RG_STATE" -n "$IDN" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -g "$RG_STATE" -n "$IDN" \
  --query principalId -o tsv)

echo "4/5 Credenciales federadas para GitHub"
# GitHub ahora emite el subject con identificadores numéricos
# (repo:USUARIO@ID/REPO@ID:...). Los leemos de la API pública para que la
# credencial coincida exactamente, con las mayúsculas correctas.
GH_JSON=$(curl -fsS "https://api.github.com/repos/${GH_USER}/${GH_REPO}") || {
  echo "No encontré github.com/${GH_USER}/${GH_REPO}. Cree primero el repositorio (público) y revise GH_USER y GH_REPO."
  exit 1
}
OWNER=$(echo "$GH_JSON" | jq -r .owner.login); OWNER_ID=$(echo "$GH_JSON" | jq -r .owner.id)
REPO=$(echo "$GH_JSON" | jq -r .name);         REPO_ID=$(echo "$GH_JSON" | jq -r .id)
# Se registran los dos formatos (con y sin identificadores) por compatibilidad.
declare -A PREFIX=(
  [id]="repo:${OWNER}@${OWNER_ID}/${REPO}@${REPO_ID}"
  [nombre]="repo:${OWNER}/${REPO}"
)
declare -A CONTEXT=(
  [pull-request]="pull_request"
  [rama-main]="ref:refs/heads/main"
  [entorno-dev]="environment:dev"
  [entorno-prod]="environment:prod"
)
for p in "${!PREFIX[@]}"; do
  for c in "${!CONTEXT[@]}"; do
    az identity federated-credential create --resource-group "$RG_STATE" \
      --identity-name "$IDN" --name "gh-${p}-${c}" \
      --issuer "https://token.actions.githubusercontent.com" \
      --subject "${PREFIX[$p]}:${CONTEXT[$c]}" \
      --audiences "api://AzureADTokenExchange" --output none
  done
done

echo "5/5 Permisos mínimos"
for rg in "$RG_DEV" "$RG_PROD"; do
  az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal --role "Contributor" \
    --scope "$(az group show --name "$rg" --query id -o tsv)" --output none
done
SA_ID=$(az storage account show -g "$RG_STATE" -n "$SA" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$SA_ID/blobServices/default/containers/tfstate" --output none

echo
echo "Cree estas cinco variables en GitHub (Settings > Secrets and variables"
echo "> Actions > Variables):"
echo "  AZURE_CLIENT_ID       = $CLIENT_ID"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID = $SUB_ID"
echo "  AZURE_LOCATION        = $LOC"
echo "  TFSTATE_SA            = $SA"
