@echo off
rem ckode launcher for Windows: runs the pinned, unmodified OpenCode release
rem with the ckode plugin loaded. Installed by install.ps1; settings live
rem beside it. Mirrors launcher/ckode; keep the two in step.
rem
rem A .cmd rather than a .ps1 so it runs under the default execution policy and
rem from cmd, PowerShell and Windows Terminal alike. Paths are only expanded
rem outside parenthesised blocks, where a ")" in a user name would end the block.
setlocal

set "AC_HOME=%USERPROFILE%\.ckode"
if defined CKODE_HOME set "AC_HOME=%CKODE_HOME%"
if not exist "%AC_HOME%\settings.cmd" goto :not_installed
rem Provides CKODE_VERSION, TITLE, OPENCODE_VERSION, INSTALLER_URL and PLUGIN_PATH.
call "%AC_HOME%\settings.cmd"
if not defined TITLE set "TITLE=ckode"
rem The plugin draws this as the logo and terminal title; the menu shows it too.
set "CKODE_TITLE=%TITLE%"

set "AC_BIN=%AC_HOME%\opencode\%OPENCODE_VERSION%\opencode.exe"
if not exist "%AC_BIN%" goto :missing_opencode

rem OpenCode's own upgrade would replace the binary behind the pinned version;
rem upgrades go through the installer, which only moves to evaluated releases.
if /i "%~1"=="upgrade" goto :upgrade

rem OpenCode's --version only knows its own number; report both.
if "%~2"=="" if "%~1"=="--version" goto :version
if "%~2"=="" if "%~1"=="-v" goto :version

rem Providers. The default is OpenCode's own free models, which need nothing.
rem Anything else is a provider the user added (name, OpenAI-compatible URL and an
rem optional key), kept in %AC_HOME%\providers and managed by ckode-menu.ps1,
rem which writes the choice to %AC_OUT% as `set` lines. The menu never changes
rem the default: Enter means OpenCode. CKODE_BASE_URL (with CKODE_API_KEY and
rem CKODE_PROVIDER_NAME) in the environment picks a provider for one run and
rem skips the menu.
set "AC_PROV=%AC_HOME%\providers"
set "AC_OUT=%AC_HOME%\selection.cmd"
if /i "%~1"=="connect" goto :connect

rem Only the interactive TUI gets the menu: no arguments, or a directory.
if "%~1"=="" goto :menu
if exist "%~1\*" goto :menu
goto :provider_ready

:menu
if defined CKODE_BASE_URL goto :provider_ready
if exist "%AC_OUT%" del "%AC_OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ckode-menu.ps1" -Providers "%AC_PROV%" -Out "%AC_OUT%"
if errorlevel 1 exit /b 1
if not exist "%AC_OUT%" goto :provider_ready
call "%AC_OUT%"
del "%AC_OUT%"

:provider_ready
set "AC_OPTS={}"
if not defined CKODE_BASE_URL goto :env_ready
rem A server that needs no key still needs some key for OpenCode to treat the
rem provider as connected; the server ignores it.
if not defined CKODE_API_KEY set "CKODE_API_KEY=local"
set "AC_OPTS={"baseURL":"%CKODE_BASE_URL%","name":"%CKODE_PROVIDER_NAME%"}"

:env_ready
rem Passed by environment rather than written to OpenCode's config files, so a
rem user's own opencode.json and tui.json keep working. The plugin itself
rem enforces the provider lock from inside the config hook.
set "OPENCODE_CONFIG_CONTENT={"plugin":[["%PLUGIN_PATH%",%AC_OPTS%]]}"
set "OPENCODE_TUI_CONFIG=%AC_HOME%\tui.json"

:run
"%AC_BIN%" %*
exit /b %errorlevel%

:connect
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ckode-menu.ps1" -Providers "%AC_PROV%" -Out "%AC_OUT%" -Add
exit /b %errorlevel%

:version
set "AC_LABEL=%CKODE_VERSION%"
if not defined AC_LABEL set "AC_LABEL=(local)"
echo %TITLE% %AC_LABEL% (OpenCode %OPENCODE_VERSION%)
exit /b 0

:upgrade
if not defined INSTALLER_URL goto :no_installer
rem Keep the installed title unless the user passes another -Title.
rem TLS 1.2 is not the default for Windows PowerShell 5.1 on every machine.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((Invoke-RestMethod '%INSTALLER_URL%'))) -Title '%TITLE%'"
exit /b %errorlevel%

:not_installed
echo ckode: not installed correctly ("%AC_HOME%\settings.cmd" is missing). Re-run the installer. 1>&2
exit /b 1

:missing_opencode
echo ckode: OpenCode %OPENCODE_VERSION% is missing from "%AC_HOME%\opencode". Re-run the installer. 1>&2
exit /b 1

:no_installer
echo ckode: this install has no installer URL to upgrade from. Re-run install.ps1 from a new ckode bundle. 1>&2
exit /b 1
