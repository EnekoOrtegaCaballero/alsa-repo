# Acme Hybrid Cloud — Proof of Concept

Arquitectura Híbrida en Google Cloud Platform (GCP): Windows Active Directory en Alta Disponibilidad (2 zonas), APIs Flask+Nginx dockerizadas, autoescalado horizontal (MIG), trazabilidad distribuida (OpenTelemetry → Tempo), logs centralizados (Promtail → Loki → Grafana) y monitorización completa (Zabbix Agent 2 Auto-Registro).

---

## Arquitectura

```
┌─────────────────── GCP VPC (acme-hibrida-vpc) ───────────────────┐
│                                                                   │
│  subnet-ad (10.0.1.0/24)       subnet-apps (10.0.2.0/24)        │
│  ┌──────────────────┐          ┌──────────────────────┐          │
│  │ ad1 (PDC Zone A) │          │ mantenimiento.       │          │
│  │ ad2 (Rep Zone B) │◄─LDAP───│ enekoortega.com      │          │
│  │ Windows 2022     │          │ Flask API + Docker   │          │
│  │ Zabbix Agent 2   │          │ OTLP + Zabbix Agent  │          │
│  └──────────────────┘          └──────────────────────┘          │
│                                                                   │
│                                ┌──────────────────────┐          │
│                                │ horarios.enekoortega  │          │
│                                │ .com (Load Balancer) │          │
│                                │    ▼  ▼  ▼           │          │
│                                │ MIG (1→5 VMs)       │          │
│                                │ Nginx + Docker       │          │
│                                │ Zabbix Agent 2       │          │
│                                └──────────────────────┘          │
└───────────────────────────────────────────────────────────────────┘
         │                               │
         ▼                               ▼
  zabbix.enekoortega.com       grafana.enekoortega.com
  (Zabbix Server / VPS)        (Loki + Grafana + Tempo / VPS)
```

---

## 🚀 Guía Paso a Paso

### Fase 0 — Requisitos Previos

| Requisito | Comando de verificación |
|---|---|
| Cuenta GCP con proyecto activo | `gcloud projects list` |
| APIs habilitadas (Compute, Cloud DNS) | `gcloud services list --enabled` |
| CLI `gcloud` autenticada | `gcloud auth application-default login` |
| Terraform instalado | `terraform version` |
| Cliente RDP (Remmina, xfreerdp, etc.) | `which xfreerdp` |

---

### Fase 1 — DNS Base (independiente de Terraform)

Si aún no has migrado tu dominio a Google Cloud DNS, ejecuta el script de importación:

```bash
cd ~/projects/acme
chmod +x import_dns_csv.sh
./import_dns_csv.sh
```

Este script crea la zona `enekoortega-com-zone` y carga todos tus registros existentes (A, CNAME, MX, SPF) del CSV. Apunta los **Nameservers** que te devuelve en tu registrador (DonDominio, GoDaddy, etc.).

---

### Fase 2 — Desplegar la Infraestructura con Terraform

```bash
cd ~/projects/acme/terraform

# 1. Revisa y edita tus variables
nano terraform.tfvars
```

**Variables que debes rellenar** en `terraform.tfvars`:

| Variable | Descripción | Ejemplo |
|---|---|---|
| `project_id` | ID de tu proyecto GCP | `acme-interview` |
| `ad_password` | Contraseña del Admin de AD | `SuperPassword.2026!` |
| `vps_ip` | IP pública de tu VPS | `51.91.156.141` |
| `zabbix_server` | Dominio/IP de tu Zabbix | `zabbix.enekoortega.com` |
| `loki_url` | Endpoint de Loki | `http://grafana.enekoortega.com:3100/loki/api/v1/push` |
| `git_repo_url` | Repo con el código de la API | `https://github.com/tu-usuario/acme-repo.git` |

```bash
# 2. Inicializar y desplegar
terraform init
terraform plan    # Revisa que todo sea correcto
terraform apply   # Escribe "yes" cuando te lo pida
```

**¿Qué ocurre al ejecutar `terraform apply`?**:
1. Se crea la VPC con dos subredes (AD y Apps).
2. Se crean 4 reglas de firewall:
   - **RDP (3389)**: Abierto **solamente** hacia tu IP actual y tu VPS.
   - **HTTP (80, 443, 8080)**: Igual, solo tu IP y tu VPS.
   - **Zabbix (10050)**: Solo desde tu VPS.
   - **Interno**: Todo el tráfico entre las subredes.
3. Se levantan `ad1` (PDC, Zona A) y `ad2` (Réplica, Zona B) con Windows Server 2022.
4. Se levanta la VM de Mantenimiento (Ubuntu + Docker + Flask API + OTLP).
5. Se crea la plantilla, el MIG y el Load Balancer para la API de Horarios.
6. Se crean los registros DNS dinámicos (`ad`, `mantenimiento`, `horarios`) en Cloud DNS.

Al finalizar, Terraform mostrará los **outputs**:

```
ad_primary_public_ip    = "34.175.x.x"     ← Para RDP al controlador principal
ad_replica_public_ip    = "34.175.y.y"     ← Para RDP al controlador secundario
mantenimiento_public_ip = "34.175.z.z"     ← IP de la API de Mantenimiento
horarios_load_balancer_ip = "34.175.w.w"   ← IP del Load Balancer de Horarios
dns_nameservers         = [...]            ← Nameservers de Google Cloud DNS
```

> **⚠️ IMPORTANTE**: Espera ~10 minutos tras el `apply`. Los servidores Windows necesitan tiempo para ejecutar sus `sysprep-specialize-scripts` (instalar AD, promover el dominio, descargar Zabbix, etc.).

---

### Fase 3 — Configurar el Active Directory

#### 3.1 Conectar por RDP al servidor primario

```bash
# Usa los IPs de los outputs:
xfreerdp /v:34.175.x.x /u:Administrator /p:'SuperPassword.2026!' /d:acme.local
```

> **✅ El firewall ya tiene tu IP permitida en la regla `acme-allow-rdp-restricted` (puerto 3389)**. Si cambias de red/IP, haz `terraform apply` de nuevo y Terraform actualizará la regla automáticamente con tu nueva IP.

#### 3.2 Poblar el Active Directory (solo en el PDC)

Dentro del escritorio remoto de `ad1`:

1. Abre **PowerShell como Administrador**.
2. Copia o transfiere el contenido del fichero `scripts/Setup-AcmeAD.ps1`.
3. Ejecútalo:

```powershell
# Dentro del servidor ad1 (RDP)
. C:\Setup-AcmeAD.ps1
```

**Este script crea**:
- 1 OU principal (`Acme_Operaciones`) con sub-OUs `Usuarios` y `Grupos`.
- 4 Grupos de Seguridad: `Mecanicos_Grupo`, `Conductores_Grupo`, `RRHH_Grupo`, `Partners_Externos`.
- 3 Usuarios de prueba:

| Usuario | Login | Grupo | ¿Acceso a Mantenimiento? |
|---|---|---|---|
| Juan Pérez | `jperez` | `Mecanicos_Grupo` | ✅ Sí (es mecánico) |
| Ana García | `agarcia` | `Conductores_Grupo` | ❌ No |
| Luis Gómez | `lgomez` | `RRHH_Grupo` | ❌ No |

#### 3.3 ¿Es necesario replicar manualmente en ad2?

**No.** El servidor `ad2` se configuró automáticamente como controlador de dominio secundario de `acme.local` mediante el script `startup-ad-replica.ps1`. **Active Directory replica la base de datos automáticamente** (OUs, grupos y usuarios) entre PDC y Réplica. No necesitas hacer nada más.

Para verificar que la réplica está sincronizada, conéctate por RDP a `ad2` y ejecuta:

```powershell
# Dentro del servidor ad2 (RDP)
repadmin /replsummary
```

Debería mostrar el estado `succeeded` para la replicación con `ad1`.

---

### Fase 4 — Probar la API de Mantenimiento

La API escucha en el puerto `8080` de la VM de Mantenimiento. Puedes probar desde tu VPS (que tiene el puerto abierto) o desde tu PC local.

#### 4.1 Autenticación exitosa (usuario mecánico)

```bash
# Desde tu VPS (enekoortega.com) o tu PC local:
curl -s -X POST http://mantenimiento.enekoortega.com:8080/api/v1/mantenimiento/legacy \
  -H "Content-Type: application/json" \
  -d '{"usuario": "jperez", "password": "PasswordTemporal.2026!"}' | jq

# Respuesta esperada (200 OK):
# {
#   "auth": "LDAP_Windows",
#   "status": "Acceso concedido al taller."
# }
```

#### 4.2 Autenticación rechazada (usuario sin permisos de mecánico)

```bash
curl -s -X POST http://mantenimiento.enekoortega.com:8080/api/v1/mantenimiento/legacy \
  -H "Content-Type: application/json" \
  -d '{"usuario": "agarcia", "password": "PasswordTemporal.2026!"}' | jq

# Respuesta esperada (403 Forbidden):
# {
#   "error": "No eres mecánico en el AD tradicional"
# }
```

#### 4.3 Credenciales incorrectas

```bash
curl -s -X POST http://mantenimiento.enekoortega.com:8080/api/v1/mantenimiento/legacy \
  -H "Content-Type: application/json" \
  -d '{"usuario": "jperez", "password": "contraseñaincorrecta"}' | jq

# Respuesta esperada (401 Unauthorized):
# {
#   "error": "Fallo de LDAP",
#   "details": "..."
# }
```

#### 4.4 Health Check

```bash
curl -s http://mantenimiento.enekoortega.com:8080/health | jq
# {"status": "ok"}
```

---

### Fase 5 — Probar la Alta Disponibilidad del AD

El objetivo es demostrar que si el controlador principal se cae, la API sigue funcionando gracias a la réplica.

#### Paso 1: Verificar que la API funciona con el PDC activo

```bash
curl -s -X POST http://mantenimiento.enekoortega.com:8080/api/v1/mantenimiento/legacy \
  -H "Content-Type: application/json" \
  -d '{"usuario": "jperez", "password": "PasswordTemporal.2026!"}' | jq
# → 200 OK, "Acceso concedido al taller."
```

#### Paso 2: Apagar el servidor primario (ad1)

```bash
# Desde tu PC con gcloud:
gcloud compute instances stop ad1 --zone=europe-southwest1-a --project=acme-interview
```

#### Paso 3: Probar la API de nuevo

> **Nota**: Actualmente la API apunta a la IP privada del PDC (`ad_server_ip`). Para que el failover sea transparente, la API debería apuntar al dominio `acme.local`, que AD DNS resolverá automáticamente al controlador vivo. Si ves que falla tras apagar ad1, necesitarás modificar el `startup-mantenimiento.sh` para usar el nombre del dominio en lugar de la IP directa.

```bash
curl -s -X POST http://mantenimiento.enekoortega.com:8080/api/v1/mantenimiento/legacy \
  -H "Content-Type: application/json" \
  -d '{"usuario": "jperez", "password": "PasswordTemporal.2026!"}' | jq
# → Debería seguir devolviendo 200 OK si se usa resolución DNS del dominio
```

#### Paso 4: Volver a encender el PDC

```bash
gcloud compute instances start ad1 --zone=europe-southwest1-a --project=acme-interview
```

---

### Fase 6 — Probar el Autoescalado Horizontal (MIG Horarios)

El Managed Instance Group de Horarios está configurado para escalar de **1 a 5 VMs** cuando la CPU supera el **60%**. Hay **dos formas** de forzar esto:

#### Opción A — Forzar CPU artificialmente vía SSH (Más rápido)

```bash
# 1. Identifica la VM activa del MIG
gcloud compute instances list --filter="name~horarios" --project=acme-interview

# 2. Conéctate por SSH
gcloud compute ssh horarios-XXXX --zone=europe-southwest1-a --project=acme-interview

# 3. Dentro de la VM: ejecuta el CPU burner (ya preinstalado por el startup script)
bash /opt/acme/horarios/cpu_burner.sh &
bash /opt/acme/horarios/cpu_burner.sh &
bash /opt/acme/horarios/cpu_burner.sh &
bash /opt/acme/horarios/cpu_burner.sh &
# Lanza varios en paralelo. Esto saturará la CPU al 100%
```

#### Opción B — Bombardear con peticiones HTTP (Más realista)

```bash
# Desde tu VPS o tu PC:
# Instala 'hey' (benchmark HTTP)
sudo apt install hey -y   # O: go install github.com/rakyll/hey@latest

# Lanza 500 peticiones concurrentes durante 120 segundos
hey -z 120s -c 50 http://horarios.enekoortega.com/
```

#### Verificar el escalado

```bash
# Monitoriza el número de instancias del MIG (ejecuta cada 30 segundos):
watch -n 30 "gcloud compute instance-groups managed list-instances \
  api-horarios-mig --zone=europe-southwest1-a --project=acme-interview"
```

Tras ~60 segundos el Autoscaler debería crear nuevas VMs. Puedes observarlo también en la [Consola de GCP → Compute Engine → Instance Groups](https://console.cloud.google.com/compute/instanceGroups).

Para detener la carga y esperar a que baje:

```bash
# Si usaste el burner, mata los procesos:
gcloud compute ssh horarios-XXXX --zone=europe-southwest1-a -- "killall cpu_burner.sh; killall bash"
```

---

### Fase 7 — Monitorización y Observabilidad

La observabilidad de este entorno se compone de tres pilares. Toda la configuración visual se detalla en el documento dedicado:

📖 **[Guía completa de Grafana, Zabbix y Tempo](docs/guia_grafanazabbix.md)**

Resumen ejecutivo de los pilares:

| Pilar | Herramienta | Función |
|---|---|---|
| **Métricas** | Zabbix Agent 2 (Auto-Registro) | CPU, RAM, Disco, Red de cada VM |
| **Logs** | Promtail → Loki → Grafana | Logs JSON estructurados (method, path, status, traceID) |
| **Trazas** | OpenTelemetry SDK → Tempo → Grafana | Spans de latencia LDAP y JWT (diagrama de Gantt) |

---

### Fase 8 — Mostrar el Código de la API (Tips para Vídeo)

Si vas a grabar un vídeo demostrativo, puedes enseñar el código fuente y su ejecución de las siguientes formas:

1. **El código fuente (Tu Editor Local)**: 
   Abre el archivo `api/app.py` en tu entorno local (VSCode, Notepad++, etc.). Explica que este es el código base y que **Terraform se encarga de inyectarlo mágicamente dentro de la máquina** sin necesidad de repositorios de Github, leyendo el archivo local a través de la función `templatefile` en `vm-mantenimiento.tf`.

2. **El despliegue en la máquina (Terminal/SSH)**:
   Si quieres mostrar dónde "vive" este código dentro de GCP:
   ```bash
   # Entra por SSH a la VM:
   gcloud compute ssh mantenimiento-enekoortega-com --zone=europe-southwest1-a --project=acme-interview
   
   # Aquí Terraform depositó los archivos e hizo el docker build:
   cd /opt/acme/api
   ls -la
   # Verás app.py, Dockerfile y requirements.txt
   ```

3. **Ver los logs de la API en vivo**:
   Para demostrar cómo la API reacciona a los comandos `curl` que hagas desde tu VPS y cómo manda las trazas OTLP, puedes mostrar los logs del contenedor Docker en tiempo real:
   ```bash
   # Dentro del SSH de la VM:
   sudo docker logs -f api-mantenimiento
   ```
   Si lanzas peticiones `curl`, verás aquí cómo el servidor procesa el login LDAP y despacha los JSON.

4. **El Porqué Arquitectónico (Legacy vs Moderno)**:
   Puedes comentar por qué la API conecta por puerto puro LDAP a un Windows Server en vez de usar OAuth2 o EntraID (Azure AD):
   - **El caso de uso Híbrido Real**: En muchas empresas (como Acme hace años), la identidad vive en servidores on-premise (*legacy*). Esta PoC demuestra cómo modernizar la capa de aplicaciones (Linux, Docker, Autoescalado) pero manteniendo la integración directa con la fuente de verdad heredada (AD tradicional por LDAP).
   - **Si fuera 100% Cloud (EntraID / Google Identity)**: La API no recibiría la contraseña del usuario ni hablaría por LDAP. El usuario se loguearía en una web (SSO), obtendría un token JWT, y se lo enviaría a la API por cabecera (`Authorization: Bearer <token>`). La API solo tendría que comprobar criptográficamente que el token es válido y mirar "dentro" del token los grupos a los que pertenece, ahorrando latencia y la necesidad de tener servidores de Directorio levantados permanentemente. De hecho, el código tiene una función `validar_token_auth0()` preparada simulando este entorno moderno.

---

## Destruir el entorno

```bash
cd ~/projects/acme/terraform
terraform destroy
# Escribe "yes"
```

> **⚠️ Nota**: `terraform destroy` **NO borra** la zona de Cloud DNS que creaste con `import_dns_csv.sh`. Esas entradas son independientes. Para borrarla, ejecuta:
> ```bash
> gcloud dns managed-zones delete enekoortega-com-zone --project=acme-interview
> ```

---

## Estructura del Proyecto

```
acme/
├── terraform/
│   ├── main.tf                    # Provider, VPC, Subredes, Firewall
│   ├── vm-ad.tf                   # Windows PDC (Zona A) + Réplica (Zona B)
│   ├── vm-mantenimiento.tf        # API Mantenimiento (Ubuntu + Docker)
│   ├── vm-horarios.tf             # MIG + Autoscaler + Load Balancer
│   ├── vm-dns.tf                  # Registros DNS dinámicos (Cloud DNS)
│   ├── variables.tf               # Variables del proyecto
│   ├── outputs.tf                 # IPs y Nameservers resultantes
│   └── terraform.tfvars           # Tus credenciales (no subir a git)
├── scripts/
│   ├── startup-ad-primary.ps1     # Startup Windows PDC + Zabbix MSI
│   ├── startup-ad-replica.ps1     # Startup Windows Réplica + Zabbix MSI
│   ├── Setup-AcmeAD.ps1           # Poblar AD: OUs, Grupos, Usuarios
│   ├── startup-mantenimiento.sh   # Docker + Flask API + OTLP + Zabbix + Promtail
│   └── startup-horarios.sh        # Docker + Nginx + Zabbix + Promtail
├── api/
│   ├── app.py                     # Flask API (LDAP + JWT + OpenTelemetry)
│   ├── requirements.txt           # Dependencias Python + OTLP
│   └── Dockerfile                 # Imagen con opentelemetry-instrument + gunicorn
├── docs/
│   └── guia_grafanazabbix.md      # Guía detallada de observabilidad
├── blog/
│   └── acme-hybrid-cloud.md       # Blog técnico para WordPress
├── import_dns_csv.sh              # Script independiente para cargar DNS base
├── DNS_enekoortega.com.csv        # Registros DNS originales del registrador
└── README.md                      # ← Estás aquí
```
