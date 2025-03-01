# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator."
    exit
}

# Check if Splunk Universal Forwarder service exists
Write-Host "Checking Splunk service status..."
$serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='SplunkForwarder'"
if (-not $serviceInfo) {
    Write-Host "Splunk service not found. Please ensure the Splunk Universal Forwarder is installed."
    exit
}

# Extract the installation directory dynamically from the service executable path
$exePath = ($serviceInfo.PathName -split ' ', 2)[0].Trim('"')
$installDir = Split-Path -Parent $exePath
Write-Host "Splunk installation directory: $installDir"

# Verify the executable exists
$splunkExe = Join-Path $installDir "bin\splunk.exe"
if (-not (Test-Path $splunkExe)) {
    Write-Host "splunk.exe not found at $splunkExe. Cannot proceed."
    exit
}

# Check if the service is running and start it if necessary
if ($serviceInfo.State -ne "Running") {
    Write-Host "Splunk service is not running. Attempting to start..."
    Start-Service -Name "SplunkForwarder"
    Start-Sleep -Seconds 5
    $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='SplunkForwarder'"
    if ($serviceInfo.State -ne "Running") {
        Write-Host "Failed to start Splunk service."
        exit
    } else {
        Write-Host "Splunk service started successfully."
    }
} else {
    Write-Host "Splunk service is running."
}

# Check Splunk client connection status
Write-Host "Checking Splunk client connection status..."
$statusOutput = & $splunkExe list forward-server

# Check if "Active forwards: None" is in the output
if ($statusOutput -match "Active forwards:\s*None") {
    Write-Host "Splunk client is not connected."

    # Extract configured forward servers
    $configuredServers = @()
    foreach ($line in $statusOutput -split "`r`n") {
        if ($line -match "^\s+\w+:\d+$") {
            $server, $port = $line.Trim() -split ":"
            $configuredServers += [PSCustomObject]@{Server=$server; Port=$port}
        }
    }

    # Test network connectivity to each configured server
    foreach ($server in $configuredServers) {
        Write-Host "Testing connectivity to $($server.Server):$($server.Port)..."
        $connectionTest = Test-NetConnection -ComputerName $server.Server -Port $server.Port
        if (-not $connectionTest.TcpTestSucceeded) {
            Write-Host "Cannot connect to $($server.Server):$($server.Port). Check network settings or firewall."
        } else {
            Write-Host "Connectivity to $($server.Server):$($server.Port) is successful."
        }
    }

    # Attempt to restart the service
    Write-Host "Attempting to restart Splunk service..."
    Restart-Service -Name "SplunkForwarder"
    Start-Sleep -Seconds 10

    # Check connection status again
    $statusOutput = & $splunkExe list forward-server
    if ($statusOutput -match "Active forwards:\s*None") {
        Write-Host "Splunk client still not connected after restart."
        # Display the last 20 lines of the latest log file for troubleshooting
        $logDir = Join-Path $installDir "var\log\splunk"
        if (Test-Path $logDir) {
            $latestLog = Get-ChildItem -Path $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestLog) {
                Write-Host "Last 20 lines of the latest log file ($($latestLog.FullName)):"
                Get-Content -Path $latestLog.FullName -Tail 20
            } else {
                Write-Host "No log files found in $logDir."
            }
        } else {
            Write-Host "Log directory $logDir does not exist."
        }
    } else {
        Write-Host "Splunk client is now connected."
    }
} else {
    Write-Host "Splunk client is connected."
}
