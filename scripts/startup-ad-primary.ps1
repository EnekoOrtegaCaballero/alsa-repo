$ErrorActionPreference = "Stop"

$DomainName = "${ad_domain}"
$SafeModePassword = "${ad_password}" | ConvertTo-SecureString -AsPlainText -Force
$ZabbixServer = "${zabbix_server}"

Write-Host ">>> [INIT] Iniciando configuración de Primary Domain Controller (PDC)..."

# 0. Asegurar Contraseña de Administrador Local (Solo si no es Domain Controller)
Write-Host ">>> [ADMIN] Seteando contraseña de Administrator..."
try {
    net user Administrator "${ad_password}" 2>$null
    net user Administrator /active:yes 2>$null
} catch {
    Write-Host ">>> [ADMIN] Ignorando error de 'net user' (el servidor ya podría ser Controlador de Dominio)."
}

# 1. Configurar y Promover Active Directory
$adInstalled = Get-WindowsFeature AD-Domain-Services
if ($adInstalled.InstallState -ne "Installed") {
    Write-Host ">>> [AD] Instalando rol AD-Domain-Services..."
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

    Write-Host ">>> [AD] Promoviendo a Controlador de Dominio ($DomainName)..."
    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainMode "WinThreshold" `
        -DomainName $DomainName `
        -DomainNetbiosName "ACME" `
        -ForestMode "WinThreshold" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $SafeModePassword
} else {
    Write-Host ">>> [AD] El servidor ya es un controlador de dominio."
}

# 2. Descargar e Instalar Zabbix Agent 2 MSI
$ZabbixUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2-7.0-latest-windows-amd64-openssl.msi"
$MsiPath = "C:\zabbix_agent2.msi"

if (-not (Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue)) {
    Write-Host ">>> [ZABBIX] Descargando Zabbix Agent 2..."
    try {
        Invoke-WebRequest -Uri $ZabbixUrl -OutFile $MsiPath -ErrorAction Stop


    Write-Host ">>> [ZABBIX] Instalando Zabbix Agent 2 silenciosamente..."
    # Pasamos las IPs del servidor al instalador
    $InstallArgs = "/i $MsiPath /qn SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer LISTENPORT=10050"
    Start-Process msiexec.exe -Wait -ArgumentList $InstallArgs

    # Esperamos a que el servicio se registre
    Start-Sleep -Seconds 5
    } catch {
        Write-Host ">>> [ZABBIX-ERROR] No se pudo descargar Zabbix Agent desde: $_"
    }
}

# 3. Configurar HostMetadata para Auto-Registro en Zabbix Agent 2
# Buscar el fichero de configuración (la ruta puede variar según versión del MSI)
$ZabbixConfPath = (Get-ChildItem "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf" -ErrorAction SilentlyContinue).FullName
if (-not $ZabbixConfPath) {
    $ZabbixConfPath = (Get-ChildItem "C:\Program Files\Zabbix Agent*\zabbix_agent2.conf" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

if ($ZabbixConfPath -and (Test-Path $ZabbixConfPath)) {
    Write-Host ">>> [ZABBIX] Configurando $ZabbixConfPath..."
    
    # Reemplazar Server y ServerActive por defecto (127.0.0.1)
    (Get-Content $ZabbixConfPath) -replace '^Server=127.0.0.1', "Server=$ZabbixServer" | Set-Content $ZabbixConfPath
    (Get-Content $ZabbixConfPath) -replace '^ServerActive=127.0.0.1', "ServerActive=$ZabbixServer" | Set-Content $ZabbixConfPath
    
    # Comentar HostnameItem predeterminado para evitar conflictos
    (Get-Content $ZabbixConfPath) -replace '^HostnameItem=', '# HostnameItem=' | Set-Content $ZabbixConfPath
    
    # Inyectar HostMetadata CRÍTICO si no existe
    if (-not ((Get-Content $ZabbixConfPath) -match "^HostMetadata=")) {
        Add-Content -Path $ZabbixConfPath -Value "HostMetadata=Windows-AD-Acme"
    }

    Write-Host ">>> [ZABBIX] Reiniciando servicio..."
    Restart-Service -Name "Zabbix Agent 2"
} else {
    Write-Host ">>> [ZABBIX] ADVERTENCIA: No se encontró zabbix_agent2.conf o Zabbix no se instaló correctamente."
}

Write-Host ">>> [DONE] Configuración inicial finalizada. El servidor se reiniciará automáticamente si se promovió AD."
