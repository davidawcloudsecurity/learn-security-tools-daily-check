# learn-security-tools-daily-check
Run cron job in task scheduler or eventbridge to ensure security tools are running
PS script to check Tanium Client is running
```bash
# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator."
    exit
}

# Check if Tanium client service exists
Write-Host "Checking Tanium client service status..."
$service = Get-Service -Name "Tanium Client" -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Tanium client service not found. Please install the Tanium client."
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "Tanium client service is not running. Attempting to start..."
    Start-Service -Name $service
    Start-Sleep -Seconds 5  # Wait for the service to start
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
$connectionTest = Test-NetConnection -ComputerName $serverName -Port $port
if (-not $connectionTest.TcpTestSucceeded) {
    Write-Host "Cannot connect to Tanium server $serverName on port $port. Check network settings or firewall."
    exit
} else {
    Write-Host "Network connectivity to Tanium server is successful."
}

# Check client status (assuming TaniumClient.exe status command exists)
$clientPath = "C:\Program Files\Tanium\Tanium Client\TaniumClient.exe"
Write-Host "Checking Tanium client connection status..."
$statusOutput = & $clientPath status
if ($statusOutput -notmatch "Connected") {
    Write-Host "Tanium client is not connected. Attempting to restart service..."
    Restart-Service -Name "TaniumClient"
    Start-Sleep -Seconds 10  # Wait for the service to restart
    $statusOutput = & $clientPath status
    if ($statusOutput -notmatch "Connected") {
        Write-Host "Tanium client still not connected after restart."
        # Display last 20 lines of the latest log file
        $logDir = "C:\Program Files\Tanium\Tanium Client\Logs"
        $latestLog = Get-ChildItem -Path $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestLog) {
            Write-Host "Last 20 lines of the latest log file ($($latestLog.FullName)):"
            Get-Content -Path $latestLog.FullName -Tail 20
        } else {
            Write-Host "No log files found in $logDir."
        }
    } else {
        Write-Host "Tanium client is now connected."
    }
} else {
    Write-Host "Tanium client is connected."
}
```

