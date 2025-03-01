# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit
}

Write-Host "Searching for Microsoft Defender for Endpoint (Sense) service..." -ForegroundColor Cyan
$serviceName = "Sense"  # MDE's core service name
$logDir = "C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection\Temp"  # Common MDE log directory

# Check if MDE service exists
Write-Host "Checking MDE service status..." -ForegroundColor Cyan
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Microsoft Defender for Endpoint (Sense) service not found. Ensure MDE is installed." -ForegroundColor Red
    exit
}

# Check if the service is running
if ($service.Status -ne "Running") {
    Write-Host "MDE service is not running. Attempting to start..." -ForegroundColor Yellow
    Start-Service -Name $serviceName -ErrorAction Continue
    Start-Sleep -Seconds 15  # Wait for the service to start
    $service.Refresh()
    if ($service.Status -ne "Running") {
        Write-Host "Failed to start MDE service." -ForegroundColor Red
    } else {
        Write-Host "MDE service started successfully." -ForegroundColor Green
    }
} else {
    Write-Host "MDE service is running." -ForegroundColor Green
}

# Step 1: Get the MDE service's Process ID (PID)
$mdeService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if (-not $mdeService) {
    Write-Host "MDE service not found in CIM instance." -ForegroundColor Red
    exit 1
}
$mdePid = $mdeService.ProcessId
if (-not $mdePid) {
    Write-Host "MDE service is not running (no PID found)." -ForegroundColor Red
    exit 1
}
Write-Host "MDE service is running with PID: $mdePid" -ForegroundColor Green

# Step 2: Use netstat to check for ESTABLISHED connections (MDE typically uses port 443)
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
    $establishedConnections | Format-Table -AutoSize | findstr -i sense
    
    # Check specifically for Sense.exe (or MsSense.exe) with ESTABLISHED to port 443
    $mdeEstablished = $establishedConnections | Where-Object { 
        ($_.Process -eq "MsSense.exe" -or $_.Process -eq "Sense.exe") -and $_.RemoteAddress -match ":443$" 
    }
    
    if ($mdeEstablished) {
        Write-Host "ALERT: MDE has established a connection to remote servers on port 443." -ForegroundColor Green
        Write-Host "This indicates MDE is successfully communicating with its cloud endpoints." -ForegroundColor Yellow
    } else {
        Write-Host "No ESTABLISHED connections found for MDE on port 443." -ForegroundColor Red
    }
} else {
    Write-Host "No ESTABLISHED connections detected on the system." -ForegroundColor Red
}

# Step 3: Check MDE status and collect logs if needed
if ($service.Status -eq "Running") {
    Write-Host "MDE service is running." -ForegroundColor Green
} else {
    Write-Host "MDE service is not running after attempts to start." -ForegroundColor Red
    
    # Search for diagnostic logs in the MDE temp directory
    $logFile = "MDEClientAnalyzerResult.zip"  # Common output from MDE diagnostic tools
    $logFilePath = Get-ChildItem -Path $logDir -Recurse -Filter $logFile -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($logFilePath) {
        Write-Host "Found existing diagnostic log at $($logFilePath.FullName)." -ForegroundColor Cyan
        Write-Host "Please extract and review this file for errors (e.g., connectivity issues, service failures)." -ForegroundColor Yellow
    } else {
        Write-Host "No diagnostic log file ($logFile) found in $logDir." -ForegroundColor Red
        Write-Host "Attempting to generate logs using built-in MDE diagnostics..." -ForegroundColor Cyan
        
        # Simulate running a basic diagnostic (assuming MDEClientAnalyzer is available locally)
        $analyzerPath = "C:\Temp\MDEClientAnalyzer.ps1"  # Adjust this path if needed
        if (Test-Path $analyzerPath) {
            Write-Host "Running MDE Client Analyzer..." -ForegroundColor Cyan
            & $analyzerPath
            Write-Host "Check $logDir for new diagnostic output (e.g., MDEClientAnalyzerResult.zip)." -ForegroundColor Yellow
        } else {
            Write-Host "MDEClientAnalyzer.ps1 not found. Please download it from https://aka.ms/MDEClientAnalyzerPreview and place it in C:\Temp." -ForegroundColor Red
        }
    }
    exit 1  # Exit if the service isn’t running
}

# Step 4: Additional Connectivity Check
Write-Host "Performing a basic connectivity test to MDE cloud endpoints..." -ForegroundColor Cyan
$testUrl = "https://global.azure-devices-provisioning.net"  # Example MDE endpoint (adjust as needed)
try {
    $response = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec 10 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Host "Connectivity test to $testUrl succeeded." -ForegroundColor Green
    }
} catch {
    Write-Host "Connectivity test to $testUrl failed: $_" -ForegroundColor Red
    Write-Host "This may indicate a network issue preventing MDE from functioning." -ForegroundColor Yellow
}
