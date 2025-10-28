@echo off
setlocal EnableExtensions EnableDelayedExpansion
color 0a

:: Fun colors https://superuser.com/questions/413073/windows-console-with-ansi-colors-handling
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

:: ANSI color codes
set "RESET=%ESC%[0m"
set "ORANGE=%ESC%[38;2;255;165;0m"
set "GREEN=%ESC%[38;2;0;255;0m"
set "DIMGREEN=%ESC%[38;2;0;130;0m"
set "RED=%ESC%[38;2;255;0;0m"
set "CYAN=%ESC%[38;2;0;255;255m"
set "WHITE=%ESC%[38;2;255;255;255m"

:: Checks if process is launched as admin, prompts UAC. Launches script inside of Windows Terminal for modern features and fixes pausing execution on mouse select
:: Also test if Windows Terminal is installed/applied to system path
:: https://stackoverflow.com/questions/54658352/passing-quoted-arguments-from-batch-file-to-powershell-start-self-elevation

net session >nul 2>&1
if %errorLevel% neq 0 (
    where wt.exe >nul 2>&1
    if %errorLevel% neq 0 (
        powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/k','\"%~f0\"' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath 'wt.exe' -ArgumentList 'cmd','/k','\"%~f0\"' -Verb RunAs"
    )
    exit
) else (
    if /i "%WT_SESSION%"=="" (
        where wt.exe >nul 2>&1
        if %errorLevel% neq 0 (
            start "" cmd.exe /k '\"%~f0\"'
        ) else (
            powershell -NoProfile -Command "Start-Process -FilePath 'wt.exe' -ArgumentList 'cmd','/k','\"%~f0\"'
        )
        exit
    )
)

:: Define file paths
set "ETL=%TEMP%\capture.etl"
set "TXT=%TEMP%\capture.txt"

:begin
	color 0a
	title Virtual Link Runner
	cls
	echo.%ORANGE% 
	echo.          #       #      #           ######   	
	echo.          #       #      #           #     #  			
	echo.          #       #      #           #     #  			
	echo.           #     #       #           ######   			
	echo.            #   #        #           #   #    			
	echo.             # #         #           #    #   			
	echo.              #          #######     #     #  			
	echo.
	echo.                  VIRTUAL LINK RUNNER										
	echo.                       v 2.2 						
	echo.						
	echo. Port information is sent within several seconds of 	
	echo. a new link-up connection or automatically every 30	
	echo. seconds. Script works with USB adapters and docks		
	echo.%RESET%
	echo. %GREEN%Initializing...%RESET%

	:: Clear previous sessions
	 del /q /f "%ETL%" "%TXT%" "%TXT%.temp" >nul 2>&1

:startSession
	echo. %GREEN%Creating packet capture session...%RESET%
	pktmon reset >nul 2>&1
	pktmon stop  >nul 2>&1
	pktmon filter remove >nul 2>&1
	pktmon filter add LLDP -m 01-80-C2-00-00-0E >nul 2>&1

	:: Start capture on all NICs, all successful packets, any size packets
	pktmon start --capture --type flow --pkt-size 0 --file-name "%ETL%" --comp nics >nul 2>&1

	echo. %GREEN%Waiting for LLDP frame...%RESET% %DIMGREEN%(insert cable now)%RESET%

:checkCounters
	:: Convenient function lets us see if a frame matching the filter has been captured
	for /f "usebackq delims=" %%A in (`pktmon counters 2^>nul ^| findstr /i /c:"All counters are zero."`) do set "counterZero=%%A"
	if defined counterZero (
		set "counterZero="
		timeout /t 1 /nobreak >nul
		goto :checkCounters
	)

	:: During initial exchange, client will send LLDP announcement, then
	echo. %GREEN%Buffering frames for 5 seconds...%RESET%
	timeout /t 5 /nobreak >nul

:exportAndParse
	echo. %GREEN%Parsing LLDP frame...%RESET%
	pktmon stop >nul 2>&1

	:: Built in tool to convert etl to txt. Verbose shows actual packet data
	pktmon etl2txt "%ETL%" --out "%TXT%" --verbose 3 >nul 2>&1

	:: Requires UTF-8 formatting. etl2txt gives incompatible encoding for CMD string matching
	powershell -noprofile -Command "Get-Content -Raw '%TXT%' | Set-Content -Encoding UTF8 '%TXT%.temp'" 2>nul
	move /y "%TXT%.temp" "%TXT%" >nul 2>&1

	set "portDesc="
	set "sysName="
	set "pvid="
	set "InRx=0"

	for /f "usebackq delims=" %%L in ("%TXT%") do (
		set "line=%%L"
		:: Checks if packet header contains Rx or Tx. We don't want self-announcements
		if not "!line!"=="!line:Direction =!" set "InRx=0"
		if not "!line!"=="!line:Direction Rx=!" (
			set "InRx=1"
		)
		:: EQU 1 = Find receiving
		if !InRx! EQU 1 (
			if not defined portDesc if not "!line!"=="!line:Port Description=!" (
				for %%t in (!line!) do set "portDesc=%%t"
			)
			
			if not defined sysName if not "!line!"=="!line:System Name=!" (
				for %%t in (!line!) do set "sysName=%%t"
			)

			if not defined pvid if not "!line!"=="!line:PVID=!" (
				for %%t in (!line!) do set "pvid=%%t"
			)

			if defined portDesc if defined sysName if defined pvid (
				goto :gotValues
			)
		)
	)


	if not defined portDesc goto :restart
	if not defined sysName  goto :restart
	if not defined pvid     goto :restart

:gotValues
	del /q /f "%ETL%" "%TXT%" "%TXT%.temp" >nul 2>&1
	echo.
	echo   %CYAN%System Name:%RESET%      %WHITE%!sysName!%RESET%
	echo   %CYAN%Port Description:%RESET% %WHITE%!portDesc!%RESET%
	call :vlanOutput "!pvid!"
	echo.
	echo. %GREEN%Press any key to capture new port information%RESET%
	pause >nul
	goto :begin

:restart
	del /q /f "%ETL%" "%TXT%" "%TXT%.temp" >nul 2>&1
	echo.
	echo.%RED% Data captured was invalid. Press any key to retry...%RESET%
	pause >nul
	timeout /t 2 /nobreak >nul
	goto :begin

:vlanOutput
	:: Define function argument. 
	set "idnum=%~1"

	:: Known VLANs
		if "!idnum!"=="101" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%101%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%DATA%RESET%
			goto :eof
		)
		if "!idnum!"=="102" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%102%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%VOICE - Voice VLAN ID should not be visible. Contact NetOps%RESET%
			goto :eof
		)
		if "!idnum!"=="103" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%103%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%TECH%RESET%
			goto :eof
		)
		if "!idnum!"=="104" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%104%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%CAMERAS%RESET%
			goto :eof
		)
		if "!idnum!"=="105" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%105%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%PRINTER%RESET%
			goto :eof
		)
		if "!idnum!"=="106" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%106%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%MAINTENANCE%RESET%
			goto :eof
		)
		if "!idnum!"=="1" (
			echo   %CYAN%VLAN ID:%RESET%          %WHITE%1%RESET%
			echo   %CYAN%VLAN Info:%RESET%        %WHITE%NATIVE - Port not configured. Contact NetOps%RESET%
			goto :eof
		)

	:: VLANs > 106 are unique cases
	if "!idnum!" GEQ "107" (
		echo   %CYAN%VLAN ID:%RESET%          %WHITE%!idnum!%RESET%
		echo   %CYAN%VLAN Info:%RESET%        %WHITE%MISC - Unique VLAN ID. Contact NetOps%RESET%
		goto :eof
	)

	:: Unknown VLANs. Probably code bug
	echo   %CYAN%VLAN ID:%RESET%          %WHITE%!idnum!%RESET%
	echo   %CYAN%VLAN Info:%RESET%        %WHITE%UNKNOWN - Refer to NetOps%RESET%
	goto :eof
