# PowerShell HTTP Server for Jarvis Dashboard
# Serves the frontend and provides APIs for system management and command execution.

$port = 9000
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")

# Retrieve active IPv4 addresses to enable local network connections (e.g. iOS 18)
$ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
$boundIps = @()

foreach ($ip in $ips) {
    $ipStr = $ip.IPAddressToString
    $listener.Prefixes.Add("http://${ipStr}:$port/")
}

try {
    $listener.Start()
    $boundIps = $ips | ForEach-Object { $_.IPAddressToString }
    Write-Host "============================================="
    Write-Host "  JARVIS SYSTEM SERVER ONLINE"
    Write-Host "  Listening locally: http://localhost:$port/"
    foreach ($bIp in $boundIps) {
        Write-Host "  Local Network Access: http://${bIp}:$port/" -ForegroundColor Green
    }
    Write-Host "  Press Ctrl+C to terminate the server."
    Write-Host "============================================="
} catch {
    # If starting fails (likely due to access denied for external IPs when not admin),
    # remove all non-localhost prefixes and try starting again with only localhost.
    Write-Warning "Failed to start with external IP bindings. Retrying with local loopback only..."
    
    $listener.Close()
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    
    try {
        $listener.Start()
        Write-Host "============================================="
        Write-Host "  JARVIS SYSTEM SERVER ONLINE (Local Loopback Only)"
        Write-Host "  Listening locally: http://localhost:$port/" -ForegroundColor Green
        Write-Host "  Press Ctrl+C to terminate the server."
        Write-Host "============================================="
    } catch {
        Write-Error "Failed to start HTTP listener: $_"
        Exit
    }
}

# Helper to send JSON response
function Send-Json {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$JsonString,
        [int]$StatusCode = 200
    )
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($JsonString)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json"
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

# Helper to serve static HTML file
function Serve-Html {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$FilePath
    )
    if (Test-Path $FilePath) {
        $buffer = [System.IO.File]::ReadAllBytes($FilePath)
        $Response.StatusCode = 200
        $Response.ContentType = "text/html"
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    } else {
        $errorMsg = "File not found: index.html"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorMsg)
        $Response.StatusCode = 404
        $Response.ContentType = "text/plain"
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    }
    $Response.OutputStream.Close()
}

# Helper to get system statistics
function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRam = [Math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 2)
    $freeRam = [Math]::Round($os.FreePhysicalMemory / 1024 / 1024, 2)
    $usedRam = [Math]::Round($totalRam - $freeRam, 2)
    $ramUsagePercent = [Math]::Round(($usedRam / $totalRam) * 100, 2)

    # CPU Usage
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $cpuLoad) {
        $cpuLoad = 0
    } else {
        $cpuLoad = [Math]::Round($cpuLoad, 2)
    }

    # Disk Info
    $disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
        $size = $_.Size
        $free = $_.FreeSpace
        if ($size -gt 0) {
            $used = $size - $free
            $pct = [Math]::Round(($used / $size) * 100, 2)
            [PSCustomObject]@{
                Drive = $_.DeviceID
                TotalGB = [Math]::Round($size / 1GB, 2)
                FreeGB = [Math]::Round($free / 1GB, 2)
                UsedGB = [Math]::Round($used / 1GB, 2)
                UsedPct = $pct
            }
        }
    }

    # Computer Info
    $comp = Get-CimInstance Win32_ComputerSystem
    
    $sysInfo = [PSCustomObject]@{
        OS = $os.Caption
        OSVersion = $os.Version
        ComputerName = $comp.Name
        Manufacturer = $comp.Manufacturer
        Model = $comp.Model
        CpuLoad = $cpuLoad
        TotalRamGB = $totalRam
        UsedRamGB = $usedRam
        FreeRamGB = $freeRam
        RamUsagePct = $ramUsagePercent
        Disks = $disks
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    return $sysInfo | ConvertTo-Json -Depth 3
}

# Main request loop
while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $url = $request.Url.LocalPath

        # Handle preflight OPTIONS requests for CORS
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
            $response.OutputStream.Close()
            continue
        }

        Write-Host "$($request.HttpMethod) $url"

        # Routing
        switch ($url) {
            "/" {
                $htmlPath = Join-Path $PSScriptRoot "index.html"
                Serve-Html -Response $response -FilePath $htmlPath
            }
            "/index.html" {
                $htmlPath = Join-Path $PSScriptRoot "index.html"
                Serve-Html -Response $response -FilePath $htmlPath
            }
            "/api/sysinfo" {
                if ($request.HttpMethod -eq "GET") {
                    $info = Get-SystemInfo
                    Send-Json -Response $response -JsonString $info
                } else {
                    Send-Json -Response $response -JsonString '{"error": "Method Not Allowed"}' -StatusCode 455
                }
            }
            "/api/processes" {
                if ($request.HttpMethod -eq "GET") {
                    $procs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 | ForEach-Object {
                        [PSCustomObject]@{
                            Id = $_.Id
                            Name = $_.ProcessName
                            CPU = [Math]::Round(($_.CPU), 2)
                            MemoryMB = [Math]::Round(($_.WorkingSet64 / 1MB), 2)
                        }
                    }
                    $jsonProcs = $procs | ConvertTo-Json
                    Send-Json -Response $response -JsonString $jsonProcs
                } else {
                    Send-Json -Response $response -JsonString '{"error": "Method Not Allowed"}' -StatusCode 455
                }
            }
            "/api/exec" {
                if ($request.HttpMethod -eq "POST") {
                    # Read request body
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $reader.Close()

                    $cmdData = ConvertFrom-Json $body
                    $cmd = $cmdData.command

                    if ($null -ne $cmd -and $cmd -ne "") {
                        Write-Host "Executing local command: $cmd" -ForegroundColor Yellow
                        
                        $stdout = ""
                        $stderr = ""
                        try {
                            # Execute command and capture output
                            $output = Invoke-Expression $cmd -ErrorVariable errs -ErrorAction SilentlyContinue
                            $stdout = $output | Out-String
                            if ($errs) {
                                $stderr = $errs | Out-String
                            }
                            $status = "success"
                        } catch {
                            $stderr = $_.Exception.Message
                            $status = "error"
                        }

                        $resObj = [PSCustomObject]@{
                            status = $status
                            stdout = $stdout
                            stderr = $stderr
                        }
                        Send-Json -Response $response -JsonString ($resObj | ConvertTo-Json)
                    } else {
                        Send-Json -Response $response -JsonString '{"error": "Missing command parameter"}' -StatusCode 400
                    }
                } else {
                    Send-Json -Response $response -JsonString '{"error": "Method Not Allowed"}' -StatusCode 455
                }
            }
            "/api/kill" {
                if ($request.HttpMethod -eq "POST") {
                    # Read request body
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $reader.Close()

                    $killData = ConvertFrom-Json $body
                    $pid = $killData.pid

                    if ($null -ne $pid) {
                        Write-Host "Killing process ID: $pid" -ForegroundColor Red
                        try {
                            Stop-Process -Id $pid -Force
                            Send-Json -Response $response -JsonString '{"status": "success", "message": "Process terminated"}'
                        } catch {
                            Send-Json -Response $response -JsonString "{\`"status\`": \`"error\`", \`"message\`": \`"$($_.Exception.Message)\`"}" -StatusCode 500
                        }
                    } else {
                        Send-Json -Response $response -JsonString '{"error": "Missing PID"}' -StatusCode 400
                    }
                } else {
                    Send-Json -Response $response -JsonString '{"error": "Method Not Allowed"}' -StatusCode 455
                }
            }
            "/api/upload" {
                if ($request.HttpMethod -eq "POST") {
                    $filename = $request.QueryString["filename"]
                    if ($null -eq $filename -or $filename -eq "") {
                        Send-Json -Response $response -JsonString '{"error": "Missing filename parameter"}' -StatusCode 400
                        continue
                    }

                    # Define the upload directory
                    $uploadDir = Join-Path $PSScriptRoot "uploads"
                    if (-not (Test-Path $uploadDir)) {
                        New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null
                    }

                    $filePath = Join-Path $uploadDir $filename
                    Write-Host "Saving uploaded file to: $filePath" -ForegroundColor Green

                    try {
                        # Create output stream and copy input stream contents directly
                        $outStream = [System.IO.File]::Create($filePath)
                        $request.InputStream.CopyTo($outStream)
                        $outStream.Close()

                        $resObj = [PSCustomObject]@{
                            status = "success"
                            message = "File uploaded successfully"
                            path = $filePath
                        }
                        Send-Json -Response $response -JsonString ($resObj | ConvertTo-Json)
                    } catch {
                        $resObj = [PSCustomObject]@{
                            status = "error"
                            message = $_.Exception.Message
                        }
                        Send-Json -Response $response -JsonString ($resObj | ConvertTo-Json) -StatusCode 500
                    }
                } else {
                    Send-Json -Response $response -JsonString '{"error": "Method Not Allowed"}' -StatusCode 455
                }
            }
            default {
                Send-Json -Response $response -JsonString '{"error": "Not Found"}' -StatusCode 404
            }
        }
    } catch {
        Write-Host "Error handling request: $_" -ForegroundColor Red
    }
}
