# learn-security-tools-daily-check
Run cron job in task scheduler or eventbridge to ensure security tools are running
PS script to check if Splunk is running
```bash
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
```
PS script to check Tanium Client is running
```bash
# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator."
    exit
}

$serviceName = "Tanium Client"

# Check if Tanium client service exists
Write-Host "Checking Tanium client service status..."
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Tanium client service not found. Please install the Tanium client."
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "Tanium client service is not running. Attempting to start..."
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 15  # Wait for the service to start
    $service.Refresh()
    if ($service.Status -ne "Running") {
        Write-Host "Failed to start Tanium client service."
        exit
    } else {
        Write-Host "Tanium client service started successfully."
    }
} else {
    Write-Host "Tanium client service is running."
}

# Step 1: Get the Tanium Client service's Process ID (PID)
$taniumService = Get-CimInstance -ClassName Win32_Service -Filter "Name='Tanium Client'" -ErrorAction SilentlyContinue
if (-not $taniumService) {
    Write-Host "Tanium Client service not found."
    exit 1
}
$taniumPid = $taniumService.ProcessId
if (-not $taniumPid) {
    Write-Host "Tanium Client service is not running."
    exit 1
}
Write-Host "Tanium Client service is running with PID: $taniumPid"

# Step 2: Use netstat to find the port associated with the Tanium Client process
$netstatOutput = netstat -anob | Out-String
$lines = $netstatOutput -split "`n"

# Search for LISTENING connections associated with TaniumClient.exe specifically
$port = $null
for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    $currentLine = $lines[$i].Trim()
    $nextLine = $lines[$i + 1].Trim()
    
    # Check if the next line contains [TaniumClient.exe]
    if ($nextLine -match "\[TaniumClient\.exe\]") {
        # Parse the current line for TCP, LISTENING state, and port information
        if ($currentLine -match "^\s*TCP\s+([\d\.]+):(\d+)\s+[\d\.]+:\d*\s+LISTENING") {
            $port = $matches[2]
            Write-Host "Found Tanium Client listening on port $port"
            break
        }
    }
}

# Check network connectivity to the Tanium server
Write-Host "Testing network connectivity to $serverName on port $port..."
$connectionTest = Test-NetConnection localhost -Port $port
if (-not $connectionTest.TcpTestSucceeded) {
    Write-Host "Cannot connect to Tanium server $serverName on port $port. Check network settings or firewall."
    exit
} else {
    Write-Host "Network connectivity to Tanium server is successful."
}

# Check client status (assuming TaniumClient.exe status command exists)
$serviceName = "Tanium Client"
$logDir = "C:\"  # Root directory to start searching from (you can change this to a more specific path)

# Check if the service is running
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service -and $service.Status -eq "Running") {
    Write-Host "Tanium Client service is running. No need to show logs."
} else {
    Write-Host "Tanium Client service is not running. Attempting to start service..."
    Start-Service -Name $serviceName -ErrorAction Continue

    # Wait for the service to stabilize
    Start-Sleep -Seconds 10

    # Recheck the service status
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
        Write-Host "Tanium Client service is now running."
    } else {
        Write-Host "Tanium Client service failed to start."
        exit 1  # Exit the script if the service could not be started
    }

    # Search for the sensor-history0.txt log file in the specified directory and its subdirectories
    $logFilePath = Get-ChildItem -Path $logDir -Recurse -Filter "sensor-history0.txt" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($logFilePath) {
        Write-Host "Displaying the last 20 lines of the log file $($logFilePath.FullName):"
        Get-Content -Path $logFilePath.FullName -Tail 20
    } else {
        Write-Host "Log file 'sensor-history0.txt' not found in $logDir or its subdirectories."
    }
}
```

