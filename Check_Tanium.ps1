# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator."
    exit
}

$serviceName = "Tanium Client"
$logfile = "sensor-history0.txt"

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
$taniumService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
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
