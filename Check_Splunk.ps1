# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit
}

Write-Host "Searching for a Splunk-related service..." -ForegroundColor Cyan
$serviceName = Get-Service | Where-Object { $_.Name -match "splunk" -or $_.DisplayName -match "splunk" } | Select-Object -First 1

if (-not $serviceName) {
    Write-Host "No Splunk-related service found. Please ensure the Splunk Universal Forwarder is installed." -ForegroundColor Yellow
    exit
}

$serviceName = $serviceName.Name
$logFile = "splunkd.log"  # Common Splunk log file name
$serverName = "localhost"  # Define serverName (adjust as needed)

# Check if Splunk service exists
Write-Host "Checking Splunk service status..." -ForegroundColor Cyan
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Splunk service not found. Please install the Splunk Universal Forwarder." -ForegroundColor Red
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "Splunk service is not running. Attempting to start..." -ForegroundColor Yellow
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 15  # Wait for the service to start
    $service.Refresh()
    if ($service.Status -ne "Running") {
        Write-Host "Failed to start Splunk service." -ForegroundColor Red
        exit
    } else {
        Write-Host "Splunk service started successfully." -ForegroundColor Green
    }
} else {
    Write-Host "Splunk service is running." -ForegroundColor Green
}

# Step 1: Get the Splunk service's Process ID (PID)
$splunkService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if (-not $splunkService) {
    Write-Host "Splunk service not found." -ForegroundColor Red
    exit 1
}
$splunkPid = $splunkService.ProcessId
if (-not $splunkPid) {
    Write-Host "Splunk service is not running." -ForegroundColor Red
    exit 1
}
Write-Host "Splunk service is running with PID: $splunkPid" -ForegroundColor Green

# Step 2: Use netstat to find connections and check for SYN_SENT on port 9997
Write-Host "Checking for SYN_SENT connections..." -ForegroundColor Cyan
$netstatOutput = netstat -anob | Out-String
$lines = $netstatOutput -split "`n"

# Create a table format for display
$synSentConnections = @()

# Search for SYN_SENT connections associated with any process
for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    $currentLine = $lines[$i].Trim()
    $nextLine = $lines[$i + 1].Trim()
    
    # Check if the current line has TCP and SYN_SENT
    if ($currentLine -match "^\s*TCP\s+([\d\.]+):(\d+)\s+([\d\.]+):(\d+)\s+SYN_SENT") {
        $localIp = $matches[1]
        $localPort = $matches[2]
        $remoteIp = $matches[3]
        $remotePort = $matches[4]
        
        # Extract the process name from the next line if it exists
        $processName = "Unknown"
        if ($nextLine -match "\[(.*?)\]") {
            $processName = $matches[1]
        }
        
        # Create a custom object with the connection details
        $connectionInfo = [PSCustomObject]@{
            Protocol = "TCP"
            LocalAddress = "$localIp`:$localPort"
            RemoteAddress = "$remoteIp`:$remotePort"
            State = "SYN_SENT"
            Process = $processName
        }
        
        $synSentConnections += $connectionInfo
    }
}

# Display the results in a table format
if ($synSentConnections.Count -gt 0) {
    Write-Host "Found $($synSentConnections.Count) SYN_SENT connections:" -ForegroundColor Yellow
    $synSentConnections | Format-Table -AutoSize
    
    # Check specifically for splunkd.exe with SYN_SENT to port 9997
    $splunkSynSent = $synSentConnections | Where-Object { 
        $_.Process -eq "splunkd.exe" -and $_.RemoteAddress -match ":9997$" 
    }
    
    if ($splunkSynSent) {
        Write-Host "ALERT: Splunk is attempting to connect to remote servers but connections are in SYN_SENT state." -ForegroundColor Red
        Write-Host "This may indicate network connectivity issues or firewall blocking." -ForegroundColor Yellow
    }
} else {
    Write-Host "No SYN_SENT connections detected." -ForegroundColor Green
}

# Check Splunk status and logs if needed
$logDir = "C:\Program Files\SplunkUniversalForwarder\var\log\splunk"  # Default log directory, adjust if needed

# Check if the service is running
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service -and $service.Status -eq "Running") {
    Write-Host "Splunk service is running." -ForegroundColor Green
} else {
    Write-Host "Splunk service is not running. Attempting to start service..." -ForegroundColor Yellow
    Start-Service -Name $serviceName -ErrorAction Continue

    # Wait for the service to stabilize
    Start-Sleep -Seconds 10

    # Recheck the service status
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
        Write-Host "Splunk service is now running." -ForegroundColor Green
    } else {
        Write-Host "Splunk service failed to start." -ForegroundColor Red
        
        # Search for the splunkd.log file in the specified directory
        $logFilePath = Get-ChildItem -Path $logDir -Recurse -Filter $logFile -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($logFilePath) {
            Write-Host "Displaying the last 20 lines of the log file $($logFilePath.FullName):" -ForegroundColor Cyan
            Get-Content -Path $logFilePath.FullName -Tail 20
        } else {
            Write-Host "Log file $logFile not found in $logDir or its subdirectories." -ForegroundColor Red
        }
        
        exit 1  # Exit the script if the service could not be started
    }
}
