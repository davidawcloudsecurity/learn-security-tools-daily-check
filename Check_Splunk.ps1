# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator."
    exit
}

Write-Host "Searching for a Splunk-related service..."
$serviceName = Get-Service | Where-Object { $_.Name -match "splunk" -or $_.DisplayName -match "splunk" } | Select-Object -First 1

if (-not $serviceName) {
    Write-Host "No Splunk-related service found. Please ensure the Splunk Universal Forwarder is installed."
    exit
}

$serviceName = $serviceName.Name
$logFile = "splunkd.log"  # Common Splunk log file name
$serverName = "localhost"  # Define serverName (adjust as needed)

# Check if Splunk service exists
Write-Host "Checking Splunk service status..."
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Splunk service not found. Please install the Splunk Universal Forwarder."
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "Splunk service is not running. Attempting to start..."
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 15  # Wait for the service to start
    $service.Refresh()
    if ($service.Status -ne "Running") {
        Write-Host "Failed to start Splunk service."
        exit
    } else {
        Write-Host "Splunk service started successfully."
    }
} else {
    Write-Host "Splunk service is running."
}

# Step 1: Get the Splunk service's Process ID (PID)
$splunkService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if (-not $splunkService) {
    Write-Host "Splunk service not found."
    exit 1
}
$splunkPid = $splunkService.ProcessId
if (-not $splunkPid) {
    Write-Host "Splunk service is not running."
    exit 1
}
Write-Host "Splunk service is running with PID: $splunkPid"

# Step 2: Use netstat to find connections and check for SYN_SENT on port 9997
$netstatOutput = netstat -anob | Out-String
$lines = $netstatOutput -split "`n"

# Search for SYN_SENT connections on port 9997 associated with Splunk processes
$synSentFound = $false
for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    $currentLine = $lines[$i].Trim()
    $nextLine = $lines[$i + 1].Trim()
    
    # Check if the next line contains a Splunk-related process
    if ($nextLine -match "\[splunkd\.exe\]") {
        # Parse the current line for TCP, SYN_SENT state, and port 9997
        if ($currentLine -match "^\s*TCP\s+([\d\.]+):(\d+)\s+([\d\.]+):9997\s+SYN_SENT") {
            $localPort = $matches[2]
            $remoteIp = $matches[3]
            $synSentFound = $true
            Write-Host "Found SYN_SENT connection from local port $localPort to $remoteIp:9997 for Splunk process."
            break
        }
    }
}

# Evaluate SYN_SENT status
if ($synSentFound) {
    Write-Host "SYN_SENT detected on port 9997. This may indicate a connectivity issue to the Splunk server. Check network or server status."
    # Optionally exit or take further action here
} else {
    Write-Host "No SYN_SENT detected on port 9997. Splunk appears to be functioning normally for outbound connections."
}

# Check Splunk status
$logDir = Get-ChildItem -Path $logDir -Recurse -Filter $logFile -ErrorAction SilentlyContinue | Select-Object -First 1

# Check if the service is running
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service -and $service.Status -eq "Running") {
    Write-Host "Splunk service is running. No need to show logs."
} else {
    Write-Host "Splunk service is not running. Attempting to start service..."
    Start-Service -Name $serviceName -ErrorAction Continue

    # Wait for the service to stabilize
    Start-Sleep -Seconds 10

    # Recheck the service status
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
        Write-Host "Splunk service is now running."
    } else {
        Write-Host "Splunk service failed to start."
        exit 1  # Exit the script if the service could not be started
    }

    # Search for the splunkd.log file in the specified directory
    $logFilePath = Get-ChildItem -Path $logDir -Recurse -Filter $logFile -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($logFilePath) {
        Write-Host "Displaying the last 20 lines of the log file $($logFilePath.FullName):"
        Get-Content -Path $logFilePath.FullName -Tail 20
    } else {
        Write-Host "Log file $logFile not found in $logDir or its subdirectories."
    }
}
