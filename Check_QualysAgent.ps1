# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit
}

Write-Host "Searching for a Qualys-related service..." -ForegroundColor Cyan
$serviceName = Get-Service | Where-Object { $_.Name -match "Qualys" -or $_.DisplayName -match "Qualys" } | Select-Object -First 1

if (-not $serviceName) {
    Write-Host "No Qualys-related service found. Please ensure the Qualys Agent is installed." -ForegroundColor Yellow
    exit
}

$serviceName = $serviceName.Name
$logFile = "Log.txt"  # Common Qualys log file name
$serverName = "localhost"  # Define serverName (adjust as needed)

# Check if Qualys service exists
Write-Host "Checking Qualys service status..." -ForegroundColor Cyan
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Qualys service not found. Please install the Qualys Agent." -ForegroundColor Red
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "Qualys service is not running. Attempting to start..." -ForegroundColor Yellow
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 15  # Wait for the service to start
    $service.Refresh()
    if ($service.Status -ne "Running") {
        Write-Host "Failed to start Qualys service." -ForegroundColor Red
        exit
    } else {
        Write-Host "Qualys service started successfully." -ForegroundColor Green
    }
} else {
    Write-Host "Qualys service is running." -ForegroundColor Green
}

# Step 1: Get the Qualys service's Process ID (PID)
$qualysService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if (-not $qualysService) {
    Write-Host "Qualys service not found." -ForegroundColor Red
    exit 1
}
$qualysPid = $qualysService.ProcessId
if (-not $qualysPid) {
    Write-Host "Qualys service is not running." -ForegroundColor Red
    exit 1
}
Write-Host "Qualys service is running with PID: $qualysPid" -ForegroundColor Green

# Step 2: Use netstat to find connections and check for ESTABLISHED (Qualys typically uses port 443)
Write-Host "Checking for ESTABLISHED connections..." -ForegroundColor Cyan
$netstatOutput = netstat -anob | Out-String
$lines = $netstatOutput -split "`n"

# Create a table format for display
$establishedConnections = @()

# Search for ESTABLISHED connections associated with any process
for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    $currentLine = $lines[$i].Trim()
    $nextLine = $lines[$i + 1].Trim()
    
    # Check if the current line has TCP and ESTABLISHED
    if ($currentLine -match "^\s*TCP\s+([\d\.]+):(\d+)\s+([\d\.]+):(\d+)\s+ESTABLISHED") {
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
            State = "ESTABLISHED"
            Process = $processName
        }
        
        $establishedConnections += $connectionInfo
    }
}

# Display the results in a table format
if ($establishedConnections.Count -gt 0) {
    Write-Host "Found $($establishedConnections.Count) ESTABLISHED connections:" -ForegroundColor Yellow
    $establishedConnections | Format-Table -AutoSize | findstr -i qual
    
    # Check specifically for QualysAgent.exe with ESTABLISHED to port 443 (default Qualys port)
    $qualysEstablished = $establishedConnections | Where-Object { 
        $_.Process -eq "QualysAgent.exe" -and $_.RemoteAddress -match ":443$" 
    }
    
    if ($qualysEstablished) {
        Write-Host "ALERT: Qualys Agent has established a connection to remote servers on port 443." -ForegroundColor Red
        Write-Host "This means the Qualys Agent is successfully connected." -ForegroundColor Yellow
    }
} else {
    Write-Host "No ESTABLISHED connections detected." -ForegroundColor Green
}

# Check Qualys status and logs if needed
$logDir = "C:\ProgramData\Qualys\QualysAgent"  # Default Qualys log directory

# Check if the service is running
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service -and $service.Status -eq "Running") {
    Write-Host "Qualys service is running." -ForegroundColor Green
} else {
    Write-Host "Qualys service is not running. Attempting to start service..." -ForegroundColor Yellow
    Start-Service -Name $serviceName -ErrorAction Continue

    # Wait for the service to stabilize
    Start-Sleep -Seconds 10

    # Recheck the service status
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
        Write-Host "Qualys service is now running." -ForegroundColor Green
    } else {
        Write-Host "Qualys service failed to start." -ForegroundColor Red
        
        # Search for the QualysAgent.log file in the specified directory
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
