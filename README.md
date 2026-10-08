# Laboratorio 6: GitOps con GitHub, Terraform y GCP

Adaptación a Google Cloud del laboratorio 6 de PEMU 2026 (Escuela Colombiana de
Ingeniería Julio Garavito), originalmente escrito para Azure.

- `modules/static_site/`   módulo: bucket de Cloud Storage con sitio web estático
- `envs/dev`, `envs/prod`  un entorno por carpeta, cada uno con su propio estado
- `site/index.html`        la página que se publica
- `.github/workflows/`     terraform-plan, terraform-apply, drift y destroy
- `bootstrap/bootstrap.sh` preparación de GCP (se ejecuta una vez, a mano)

## Equivalencias con la guía original (Azure)

| Guía (Azure) | Aquí (GCP) |
|---|---|
| `rg-gitops-state` / `-dev` / `-prod` | tres proyectos: `gitops-state-*`, `gitops-dev-*`, `gitops-prod-*` |
| Identidad administrada `id-gitops-github` | Service Account `sa-gitops-github@gitops-state-*` |
| 4 credenciales federadas | Workload Identity Pool + provider OIDC + 4 bindings `principal://.../subject/...` |
| `Contributor` sobre el RG | `roles/storage.admin` sobre cada proyecto de entorno |
| `Storage Blob Data Contributor` sobre `tfstate` | `roles/storage.objectAdmin` sobre el bucket del estado |
| backend `azurerm` (contenedor `tfstate`, lease) | backend `gcs` (bucket + `prefix`, bloqueo nativo) |
| Storage Account + contenedor `$web` | bucket con `website {}` + `allUsers:objectViewer` |
| Variables `AZURE_*`, `TFSTATE_SA` | `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `GCP_PROJECT_DEV`, `GCP_PROJECT_PROD`, `GCP_REGION`, `TFSTATE_BUCKET` |

No suba secretos. Ninguna de las seis variables lo es: sin la federación son inútiles.
