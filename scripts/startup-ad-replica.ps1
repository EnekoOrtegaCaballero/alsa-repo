$ErrorActionPreference = "Stop"

$DomainName = "${ad_domain}"
$SafeModePassword = "${ad_password}" | ConvertTo-SecureString -AsPlainText -Force
$ZabbixServer = "${zabbix_server}"
$PdcIp = "${pdc_ip}"

Write-Host ">>> [INIT] Iniciando configuración de Secondary Domain Controller (Replica)..."

# 0. Asegurar Contraseña de Administrador Local (Solo si no es Domain Controller)
Write-Host ">>> [ADMIN] Seteando contraseña de Administrator..."
try {
    net user Administrator "${ad_password}" 2>$null
    net user Administrator /active:yes 2>$null
} catch {
    Write-Host ">>> [ADMIN] Ignorando error de 'net user' (La réplica ya podría ser Controlador de Dominio)."
}

# 1. Configurar red para apuntar al PDC como servidor DNS primario
$NetAdapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
Set-DnsClientServerAddress -InterfaceAlias $NetAdapter.Name -ServerAddresses $PdcIp

# 2. Configurar y Promover Active Directory (Secondary DC)
$adInstalled = Get-WindowsFeature AD-Domain-Services
if ($adInstalled.InstallState -ne "Installed") {
    Write-Host ">>> [AD] Instalando rol AD-Domain-Services..."
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

    # Esperar a que el PDC haya instalado AD, reiniciado, y esté levantado (Puerto 389 - LDAP)
    Write-Host ">>> [AD] PDC tarda ~5 min en reiniciar. Esperando 4 minutos iniciales..."
    Start-Sleep -Seconds 240
    
    Write-Host ">>> [AD] Esperando a que el PDC ($PdcIp) esté disponible en LDAP..."
    $retryCount = 0
    while (-not (Test-NetConnection -ComputerName $PdcIp -Port 389 -InformationLevel Quiet)) {
        if ($retryCount -ge 30) {
            Write-Host ">>> [ERROR] El PDC no responde en LDAP después de 15 minutos."
            exit 1
        }
        Start-Sleep -Seconds 30
        $retryCount++
    }
    
    # Pausa extra de seguridad para que LDAP termine de cargar la partición
    Write-Host ">>> [AD] PDC está respondiendo LDAP. Esperando 30s más para estabilización..."
    Start-Sleep -Seconds 30

    Write-Host ">>> [AD] Promoviendo a Controlador de Dominio Secundario ($DomainName)..."
    # Necesitamos crear un objeto de credencial para unirnos al dominio (usando Administrator local del PDC)
    $cred = New-Object System.Management.Automation.PSCredential ("$DomainName\Administrator", $SafeModePassword)

    Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$false `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName $DomainName `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SiteName "Default-First-Site-Name" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -Credential $cred `
        -SafeModeAdministratorPassword $SafeModePassword
} else {
    Write-Host ">>> [AD] El servidor ya es un controlador de dominio secundario."
}

# 3. Descargar e Instalar Zabbix Agent 2 MSI
$ZabbixUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2-7.0-latest-windows-amd64-openssl.msi"
$MsiPath = "C:\zabbix_agent2.msi"

if (-not (Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue)) {
    Write-Host ">>> [ZABBIX] Descargando Zabbix Agent 2..."
    try {
        Invoke-WebRequest -Uri $ZabbixUrl -OutFile $MsiPath -ErrorAction Stop

    Write-Host ">>> [ZABBIX] Instalando Zabbix Agent 2 silenciosamente..."
    $InstallArgs = "/i $MsiPath /qn SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer LISTENPORT=10050"
    Start-Process msiexec.exe -Wait -ArgumentList $InstallArgs

    Start-Sleep -Seconds 5
    } catch {
        Write-Host ">>> [ZABBIX-ERROR] No se pudo descargar Zabbix Agent desde: $_"
    }
}

# 4. Configurar HostMetadata para Auto-Registro en Zabbix Agent 2
$ZabbixConfPath = (Get-ChildItem "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf" -ErrorAction SilentlyContinue).FullName
if (-not $ZabbixConfPath) {
    $ZabbixConfPath = (Get-ChildItem "C:\Program Files\Zabbix Agent*\zabbix_agent2.conf" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

if ($ZabbixConfPath -and (Test-Path $ZabbixConfPath)) {
    Write-Host ">>> [ZABBIX] Configurando $ZabbixConfPath..."
    
    (Get-Content $ZabbixConfPath) -replace '^Server=127.0.0.1', "Server=$ZabbixServer" | Set-Content $ZabbixConfPath
    (Get-Content $ZabbixConfPath) -replace '^ServerActive=127.0.0.1', "ServerActive=$ZabbixServer" | Set-Content $ZabbixConfPath
    (Get-Content $ZabbixConfPath) -replace '^HostnameItem=', '# HostnameItem=' | Set-Content $ZabbixConfPath
    
    if (-not ((Get-Content $ZabbixConfPath) -match "^HostMetadata=")) {
        Add-Content -Path $ZabbixConfPath -Value "HostMetadata=Windows-AD-Acme"
    }

    Write-Host ">>> [ZABBIX] Reiniciando servicio..."
    Restart-Service -Name "Zabbix Agent 2"
} else {
    Write-Host ">>> [ZABBIX] ADVERTENCIA: No se encontró zabbix_agent2.conf o Zabbix no se instaló correctamente."
}

Write-Host ">>> [DONE] Configuración inicial finalizada. El servidor se reiniciará automáticamente si se unió a AD."
