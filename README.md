# Laboratorio 5: GitOps con GitHub, Terraform y Azure

Repositorio plantilla del laboratorio (PEMU 2026, Escuela Colombiana de
Ingeniería Julio Garavito). Siga la guía del laboratorio; no suba secretos.

- `modules/static_site/`  módulo: cuenta de almacenamiento con sitio web estático
- `envs/dev`, `envs/prod` un entorno por carpeta, cada uno con su propio estado
- `site/index.html`       la página que se publica
- `.github/workflows/`    terraform-plan, terraform-apply, drift y destroy
- `bootstrap/bootstrap.sh` preparación de Azure (se ejecuta una vez, a mano)
