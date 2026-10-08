variable "project_id" {
  type        = string
  description = "Proyecto de GCP del entorno (lo crea el bootstrap)."
}

variable "location" {
  type = string
}

variable "prefix" {
  type        = string
  description = "Prefijo corto para el nombre del bucket."

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.prefix))
    error_message = "El prefijo debe tener de 3 a 8 letras minusculas o digitos."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "El entorno debe ser dev o prod."
  }
}

variable "index_file" {
  type        = string
  description = "Ruta del archivo index.html que se publica."
}

variable "labels" {
  type = map(string)

  validation {
    condition = alltrue([
      for k in ["owner", "environment", "course"] : can(var.labels[k])
    ])
    error_message = "Etiquetas obligatorias: owner, environment y course."
  }
}
