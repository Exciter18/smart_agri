@echo off
setlocal enabledelayedexpansion

set "projectRoot=%~dp0"
set "python=%projectRoot%.venv\Scripts\python.exe"
set "modelName=qwen2.5:3b"
set "publicApiRoot=https://jamison-noncollusive-tomasa.ngrok-free.dev"

:: --- Prerequisites Check ---
if not exist "%python%" (
    echo [ERROR] Project Python environment not found: "%python%". 
    echo Please create .venv and install requirements.txt first.
    pause
    exit /b 1
)

where ngrok >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] ngrok was not found on PATH. Install ngrok and configure its authtoken first.
    pause
    exit /b 1
)

where ollama >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Ollama was not found on PATH. Install Ollama, then run this launcher again.
    pause
    exit /b 1
)

:: --- Start Local Ollama Server ---
echo Checking if Ollama is running...
curl -s -f --max-time 2 http://127.0.0.1:11434/api/tags >nul 2>nul
if %errorlevel% neq 0 (
    echo Starting local Ollama server...
    start "Ollama Server" /min ollama serve
    
    :: Wait for Ollama to start (simple loop)
    set "ollamaReady=0"
    for /l %%i in (1, 1, 30) do (
        timeout /t 1 /nobreak >nul
        curl -s -f --max-time 2 http://127.0.0.1:11434/api/tags >nul 2>nul
        if !errorlevel! equ 0 (
            set "ollamaReady=1"
            goto ollama_started
        )
    )
    if !ollamaReady! equ 0 (
        echo [ERROR] Ollama did not start at http://127.0.0.1:11434. Start Ollama manually and try again.
        pause
        exit /b 1
    )
)
:ollama_started

:: Check if the specific model is installed
echo Checking for Ollama model '%modelName%'...
curl -s http://127.0.0.1:11434/api/tags | findstr /i "%modelName%" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Ollama model '%modelName%' is missing. Please run: ollama pull %modelName%
    pause
    exit /b 1
)

:: --- Set Environment Variables for API ---
set "LLM_PROVIDER=ollama"
set "OLLAMA_MODEL=%modelName%"
set "OLLAMA_HOST=http://127.0.0.1:11434"

:: --- Start API Server ---
set "apiUrl=http://127.0.0.1:8000"
echo Checking if API server is already running...
curl -s -f --max-time 3 "%apiUrl%/health" >nul 2>nul
if %errorlevel% equ 0 (
    echo Using the existing local API server.
) else (
    echo Starting the Smart Agri API on this PC...
    
    cd /d "%projectRoot%"
    start "Smart Agri API Server" "%python%" -m uvicorn app.api.api_server:app --host 127.0.0.1 --port 8000
    
    :: Wait for API to become ready
    set "apiReady=0"
    for /l %%i in (1, 1, 60) do (
        timeout /t 1 /nobreak >nul
        curl -s -f --max-time 2 "%apiUrl%/health" >nul 2>nul
        if !errorlevel! equ 0 (
            set "apiReady=1"
            goto api_started
        )
    )
    if !apiReady! equ 0 (
         echo [ERROR] Smart Agri API did not become ready within 60 seconds. Check the API console window.
         pause
         exit /b 1
    )
)
:api_started

:: --- Start ngrok Tunnel ---
set "ngrokApiUrl=http://127.0.0.1:4040/api/tunnels"
echo Checking if ngrok API is available...
curl -s -f --max-time 2 "%ngrokApiUrl%" >nul 2>nul
if %errorlevel% equ 0 (
    echo Checking the existing ngrok tunnel for this API...
) else (
    echo Starting one ngrok tunnel to this shared API ^(port 8000^)...
    start "ngrok Tunnel" ngrok http http://127.0.0.1:8000 --url="%publicApiRoot%"
)

:: Wait for ngrok tunnel to be established
set "tunnelReady=0"
for /l %%i in (1, 1, 30) do (
    timeout /t 1 /nobreak >nul
    curl -s --max-time 2 "%ngrokApiUrl%" | findstr /i "%publicApiRoot%" >nul
    if !errorlevel! equ 0 (
        set "tunnelReady=1"
        goto tunnel_ready
    )
)

if !tunnelReady! equ 0 (
    echo [ERROR] The fixed ngrok endpoint %publicApiRoot% did not start for port 8000. 
    echo Verify this endpoint is assigned to your ngrok account, that ngrok is logged in, and port 4040 is available.
    pause
    exit /b 1
)
:tunnel_ready

:: --- Summary ---
echo.
echo Remote demo is ready. Image analysis and Rice Care use this shared API:
echo   Health check: %publicApiRoot%/health
echo   App endpoint: %publicApiRoot%/predict
echo   Agent chat:   %publicApiRoot%/agent/chat
echo.
echo Keep this PC, Ollama, the API, and ngrok running during the demo.
echo This makes the demo API reachable from the Internet. Share the URL only with demo participants.
echo.
pause