$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = Join-Path $projectRoot '.venv\Scripts\python.exe'
$modelName = 'qwen2.5:3b'
$publicApiRoot = 'https://jamison-noncollusive-tomasa.ngrok-free.dev'

if (-not (Test-Path $python)) {
    throw "Project Python environment not found: $python. Create .venv and install requirements.txt first."
}

$ngrokCommand = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrokCommand) {
    throw 'ngrok was not found on PATH. Install ngrok and configure its authtoken first.'
}

$ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCommand) {
    throw 'Ollama was not found on PATH. Install Ollama, then run this launcher again.'
}

function Get-OllamaStatus {
    try {
        return Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
    } catch {
        return $null
    }
}

$ollamaStatus = Get-OllamaStatus
if (-not $ollamaStatus) {
    Write-Host 'Starting local Ollama server...'
    Start-Process -FilePath $ollamaCommand.Source -ArgumentList 'serve' -WindowStyle Hidden | Out-Null

    $ollamaDeadline = (Get-Date).AddSeconds(30)
    while (-not $ollamaStatus -and (Get-Date) -lt $ollamaDeadline) {
        Start-Sleep -Seconds 1
        $ollamaStatus = Get-OllamaStatus
    }
}

if (-not $ollamaStatus) {
    throw 'Ollama did not start at http://127.0.0.1:11434. Start Ollama manually and try again.'
}

$installedModel = $ollamaStatus.models |
    Where-Object { $_.name -eq $modelName -or $_.name -eq "${modelName}:latest" } |
    Select-Object -First 1
if (-not $installedModel) {
    throw "Ollama model '$modelName' is missing. Run: ollama pull $modelName"
}

$env:LLM_PROVIDER = 'ollama'
$env:OLLAMA_MODEL = $modelName
$env:OLLAMA_HOST = 'http://127.0.0.1:11434'

$apiUrl = 'http://127.0.0.1:8000'
$apiReady = $false
try {
    $null = Invoke-RestMethod -Uri "$apiUrl/health" -TimeoutSec 3
    $apiReady = $true
    $agentInfo = Invoke-RestMethod -Uri "$apiUrl/agent/model-info" -TimeoutSec 3
    if ($agentInfo.llm.provider -ne 'ollama_local') {
        throw 'An API is already running on port 8000, but it is not configured for local Ollama. Stop that server and retry.'
    }
    Write-Host 'Using the existing local API server.'
} catch {
    if ($apiReady) {
        throw
    }
}

if (-not $apiReady) {
    Write-Host 'Starting the Smart Agri API on this PC only...'
    $server = Start-Process `
        -FilePath $python `
        -ArgumentList @(
            '-m', 'uvicorn', 'app.api.api_server:app',
            '--host', '127.0.0.1', '--port', '8000'
        ) `
        -WorkingDirectory $projectRoot `
        -PassThru

    $apiDeadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $apiDeadline) {
        if ($server.HasExited) {
            throw "Smart Agri API stopped during startup (exit code $($server.ExitCode)). Check the API console for details."
        }
        try {
            $null = Invoke-RestMethod -Uri "$apiUrl/health" -TimeoutSec 2
            $apiReady = $true
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $apiReady) {
        throw 'Smart Agri API did not become ready within 60 seconds. Check the API console.'
    }
}

$ngrokApiUrl = 'http://127.0.0.1:4040/api/tunnels'
$ngrokApiAvailable = $false
try {
    $null = Invoke-RestMethod -Uri $ngrokApiUrl -TimeoutSec 2
    $ngrokApiAvailable = $true
} catch {
    $ngrokApiAvailable = $false
}

$ngrokProcess = $null
if (-not $ngrokApiAvailable) {
    Write-Host 'Starting one ngrok tunnel to this shared API (port 8000)...'
    $ngrokProcess = Start-Process `
        -FilePath $ngrokCommand.Source `
        -ArgumentList @(
            'http',
            'http://127.0.0.1:8000',
            "--url=$publicApiRoot"
        ) `
        -PassThru
} else {
    Write-Host 'Checking the existing ngrok tunnel for this API...'
}

$ngrokDeadline = (Get-Date).AddSeconds(30)
$tunnelReady = $false
while ((Get-Date) -lt $ngrokDeadline) {
    if ($ngrokProcess -and $ngrokProcess.HasExited) {
        throw 'ngrok stopped during startup. Check ngrok authentication and its console output.'
    }
    try {
        $tunnelStatus = Invoke-RestMethod -Uri $ngrokApiUrl -TimeoutSec 2
        $apiTunnel = $tunnelStatus.tunnels |
            Where-Object {
                $_.config.addr -match '(^|:)8000$' -and
                    $_.public_url.TrimEnd('/') -eq $publicApiRoot
            } |
            Select-Object -First 1
        if ($apiTunnel) {
            $tunnelReady = $true
            break
        }
    } catch {
        # The local inspector may not be ready until the ngrok agent starts.
    }
    Start-Sleep -Seconds 1
}
if (-not $tunnelReady) {
    throw "The fixed ngrok endpoint $publicApiRoot did not start for port 8000. Verify this endpoint is assigned to your ngrok account, that ngrok is logged in, and port 4040 is available."
}

$appApiUrl = "$publicApiRoot/predict"
Write-Host ''
Write-Host 'Remote demo is ready. Image analysis and Rice Care use this shared API:'
Write-Host "  Health check: $publicApiRoot/health"
Write-Host "  App endpoint: $appApiUrl"
Write-Host "  Agent chat:   $publicApiRoot/agent/chat"
Write-Host 'Keep this PC, Ollama, the API, and ngrok running during the demo.'
Write-Host 'This makes the demo API reachable from the Internet. Share the URL only with demo participants.'
