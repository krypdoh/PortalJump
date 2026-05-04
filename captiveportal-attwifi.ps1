[CmdletBinding()]
param(
	[switch]$Install,
	[switch]$Uninstall,
	[string]$TargetSsid = "att-wifi",
	[string]$PortalBaseUrl = "http://192.0.2.123",
	[int]$InitialDelaySeconds = 6,
	[int]$MaxAttempts = 3,
	[int]$RequestTimeoutSeconds = 12,
	[string]$TaskName = "AttWifi-CaptivePortal-Auto",
	[string]$LogPath = "$env:ProgramData\AttWifiPortal\attwifi-captiveportal.log",
	[switch]$ShowConsoleOutput,
	[switch]$ElevateIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:EmitConsoleLogs = $true
if ($PSBoundParameters.ContainsKey("ShowConsoleOutput")) {
	$script:EmitConsoleLogs = [bool]$ShowConsoleOutput
}

$script:AutoElevateIfNeeded = $true
if ($PSBoundParameters.ContainsKey("ElevateIfNeeded")) {
	$script:AutoElevateIfNeeded = [bool]$ElevateIfNeeded
}

function Write-Log {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Message,
		[ValidateSet("INFO", "WARN", "ERROR")]
		[string]$Level = "INFO"
	)

	$line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
	try {
		$logDir = Split-Path -Path $LogPath -Parent
		if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
			New-Item -Path $logDir -ItemType Directory -Force | Out-Null
		}

		Add-Content -Path $LogPath -Value $line
	}
	catch {
		# Keep script behavior predictable even if file logging is unavailable.
	}

	if ($script:EmitConsoleLogs) {
		switch ($Level) {
			"INFO" { Write-Host $line -ForegroundColor Gray }
			"WARN" { Write-Host $line -ForegroundColor Yellow }
			"ERROR" { Write-Host $line -ForegroundColor Red }
		}
	}
}

function Test-IsAdministrator {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = [Security.Principal.WindowsPrincipal]::new($identity)
	return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevation {
	param(
		[hashtable]$BoundParameters
	)

	$currentShellPath = (Get-Process -Id $PID).Path
	if (-not $currentShellPath) {
		$currentShellPath = "powershell.exe"
	}

	$relaunchArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
	foreach ($entry in $BoundParameters.GetEnumerator()) {
		if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
			if ([bool]$entry.Value) {
				$relaunchArgs += "-$($entry.Key)"
			}
		}
		else {
			$relaunchArgs += "-$($entry.Key)"
			$relaunchArgs += [string]$entry.Value
		}
	}

	if ($script:AutoElevateIfNeeded -and -not $BoundParameters.ContainsKey("ElevateIfNeeded")) {
		$relaunchArgs += "-ElevateIfNeeded"
	}

	$proc = Start-Process -FilePath $currentShellPath -Verb RunAs -ArgumentList $relaunchArgs -Wait -PassThru
	return $proc.ExitCode
}

function Install-CaptivePortalTask {
	if (-not (Test-IsAdministrator)) {
		$canPromptForUac = [Environment]::UserInteractive -and [bool]$PSCommandPath
		if ($script:AutoElevateIfNeeded -and $canPromptForUac) {
			Write-Log -Level "WARN" -Message "Administrator rights are required. Attempting UAC elevation."
			try {
				$exitCode = Invoke-SelfElevation -BoundParameters $PSBoundParameters
				exit $exitCode
			}
			catch {
				Write-Log -Level "ERROR" -Message "Elevation was canceled or failed: $($_.Exception.Message)"
				throw "Elevation was canceled or failed. Re-run this script from an elevated PowerShell session."
			}
		}

		Write-Log -Level "ERROR" -Message "Administrator rights are required to install the scheduled task. Re-run this script from an elevated PowerShell session or use -ElevateIfNeeded."
		throw "Administrator rights are required. Open PowerShell as Administrator and run captiveportal-attwifi.ps1 -Install again, or run with -ElevateIfNeeded."
	}

	$wevtOutput = & wevtutil set-log "Microsoft-Windows-WLAN-AutoConfig/Operational" /enabled:true 2>&1
	if ($LASTEXITCODE -ne 0) {
		$details = ($wevtOutput | Out-String).Trim()
		Write-Log -Level "ERROR" -Message "Failed to enable WLAN operational log. $details"
		throw "Failed to enable WLAN operational log. $details"
	}

	$escapedScript = '"' + $PSCommandPath.Replace('"', '""') + '"'
	$taskRun = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $escapedScript"
	$eventQuery = "*[System[Provider[@Name='Microsoft-Windows-WLAN-AutoConfig'] and EventID=8001]]"

	$arguments = @(
		"/Create",
		"/TN", $TaskName,
		"/TR", $taskRun,
		"/SC", "ONEVENT",
		"/EC", "Microsoft-Windows-WLAN-AutoConfig/Operational",
		"/MO", $eventQuery,
		"/RU", "SYSTEM",
		"/F"
	)

	$taskOutput = & schtasks.exe @arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		$details = ($taskOutput | Out-String).Trim()
		Write-Log -Level "ERROR" -Message "Failed to create scheduled task '$TaskName' (exit code: $LASTEXITCODE). $details"
		throw "Failed to create scheduled task '$TaskName' (exit code: $LASTEXITCODE). $details"
	}

	Write-Log -Level "INFO" -Message "Installed scheduled task '$TaskName'."
	Write-Log -Level "INFO" -Message "The worker script runs on WLAN connect events and self-filters for SSID $TargetSsid."
	exit 0
}

function Uninstall-CaptivePortalTask {
	if (-not (Test-IsAdministrator)) {
		$canPromptForUac = [Environment]::UserInteractive -and [bool]$PSCommandPath
		if ($script:AutoElevateIfNeeded -and $canPromptForUac) {
			Write-Log -Level "WARN" -Message "Administrator rights are required. Attempting UAC elevation."
			try {
				$exitCode = Invoke-SelfElevation -BoundParameters $PSBoundParameters
				exit $exitCode
			}
			catch {
				Write-Log -Level "ERROR" -Message "Elevation was canceled or failed: $($_.Exception.Message)"
				throw "Elevation was canceled or failed. Re-run this script from an elevated PowerShell session."
			}
		}

		Write-Log -Level "ERROR" -Message "Administrator rights are required to remove the scheduled task. Re-run this script from an elevated PowerShell session or use -ElevateIfNeeded."
		throw "Administrator rights are required. Open PowerShell as Administrator and run captiveportal-attwifi.ps1 -Uninstall again, or run with -ElevateIfNeeded."
	}

	$arguments = @(
		"/Delete",
		"/TN", $TaskName,
		"/F"
	)

	$taskOutput = & schtasks.exe @arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		$details = ($taskOutput | Out-String).Trim()
		Write-Log -Level "WARN" -Message "Task '$TaskName' may not exist or could not be removed (exit code: $LASTEXITCODE). $details"
		exit 1
	}

	Write-Log -Level "INFO" -Message "Removed scheduled task '$TaskName'."
	exit 0
}

function Get-CurrentSsid {
	$raw = netsh wlan show interfaces 2>$null
	if (-not $raw) {
		return $null
	}

	foreach ($line in $raw) {
		$match = [regex]::Match($line, '^\s*SSID\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
		if ($match.Success) {
			return $match.Groups[1].Value.Trim()
		}
	}

	return $null
}

function Test-InternetAccess {
	param(
		[int]$TimeoutSeconds = 8
	)

	$probes = @(
		@{ Uri = "http://clients3.google.com/generate_204"; ExpectCode = 204 },
		@{ Uri = "https://www.msftconnecttest.com/connecttest.txt"; ExpectText = "Microsoft Connect Test" }
	)

	foreach ($probe in $probes) {
		try {
			$result = Invoke-WebRequest -Uri $probe.Uri -Method Get -UseBasicParsing -TimeoutSec $TimeoutSeconds
			if ($probe.ContainsKey("ExpectCode") -and [int]$result.StatusCode -eq [int]$probe.ExpectCode) {
				return $true
			}
			if ($probe.ContainsKey("ExpectText") -and $result.Content -like "*$($probe.ExpectText)*") {
				return $true
			}
		}
		catch {
			continue
		}
	}

	return $false
}

function Get-HiddenInputFields {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Html
	)

	$fields = @{}
	$hiddenTagRegex = New-Object System.Text.RegularExpressions.Regex '<input[^>]*type=["'']hidden["''][^>]*>', ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$nameRegex = New-Object System.Text.RegularExpressions.Regex 'name=["'']([^"'']+)["'']', ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$valueRegex = New-Object System.Text.RegularExpressions.Regex 'value=["'']([^"'']*)["'']', ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

	$hiddenTagRegex.Matches($Html) | ForEach-Object {
		$nameMatch = $nameRegex.Match($_.Value)
		if ($nameMatch.Success) {
			$name = $nameMatch.Groups[1].Value
			$valueMatch = $valueRegex.Match($_.Value)
			$value = ""
			if ($valueMatch.Success) {
				$value = $valueMatch.Groups[1].Value
			}

			$fields[$name] = $value
		}
	}

	return $fields
}

function Get-AupPostUri {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Html,
		[Parameter(Mandatory = $true)]
		[uri]$BaseUri
	)

	$formRegex = New-Object System.Text.RegularExpressions.Regex '<form[^>]*name=["'']aupForm["''][^>]*action=["'']([^"'']+)["'']', ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$match = $formRegex.Match($Html)
	if (-not $match.Success) {
		return $null
	}

	return [uri]::new($BaseUri, $match.Groups[1].Value)
}

function Invoke-CaptivePortalAcceptance {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$BaseUrl,
		[Parameter(Mandatory = $true)]
		[int]$TimeoutSeconds,
		[Parameter(Mandatory = $true)]
		[int]$Attempt
	)

	$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
	$landing = Invoke-WebRequest -Uri $BaseUrl -Method Get -WebSession $session -UseBasicParsing -TimeoutSec $TimeoutSeconds

	$html = [string]$landing.Content
	$postUri = Get-AupPostUri -Html $html -BaseUri ([uri]$landing.BaseResponse.ResponseUri)
	if (-not $postUri) {
		Write-Log -Level "INFO" -Message "Attempt ${Attempt}: AUP form not found. Device may already be authorized."
		return $false
	}

	$fields = Get-HiddenInputFields -Html $html
	if ($fields.Count -eq 0) {
		throw "Attempt ${Attempt}: Could not parse hidden form fields from portal page."
	}

	if (-not $fields.ContainsKey("token") -and -not ($fields.Keys | Where-Object { $_ -match "token|csrf|nonce" })) {
		throw "Attempt ${Attempt}: No token-like hidden field was found; refusing to submit."
	}

	$fields["aupAccepted"] = "true"

	$originUri = [uri]$landing.BaseResponse.ResponseUri
	$headers = @{
		Referer = $originUri.AbsoluteUri
		Origin  = ("{0}://{1}" -f $originUri.Scheme, $originUri.Authority)
	}

	$postResult = Invoke-WebRequest -Uri $postUri.AbsoluteUri -Method Post -Body $fields -ContentType "application/x-www-form-urlencoded" -WebSession $session -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSeconds
	Write-Log -Level "INFO" -Message "Attempt ${Attempt}: POST sent to $($postUri.AbsoluteUri), status $([int]$postResult.StatusCode)."

	if (Test-InternetAccess -TimeoutSeconds 8) {
		Write-Log -Level "INFO" -Message "Attempt ${Attempt}: Internet access probe passed after AUP submission."
		return $true
	}

	return $false
}

if ($Install -and $Uninstall) {
	Write-Log -Level "ERROR" -Message "Specify only one mode switch: -Install or -Uninstall."
	throw "Specify only one mode switch: -Install or -Uninstall."
}

if ($Install) {
	Install-CaptivePortalTask
}

if ($Uninstall) {
	Uninstall-CaptivePortalTask
}

$mutexName = "Global\AttWifiCaptivePortalMutex"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$hasLock = $false

try {
	$hasLock = $mutex.WaitOne(0)
	if (-not $hasLock) {
		Write-Log -Level "INFO" -Message "Another instance is already running. Exiting."
		exit 0
	}

	$ssid = Get-CurrentSsid
	if (-not $ssid) {
		Write-Log -Level "WARN" -Message "Unable to determine current SSID. Exiting."
		exit 0
	}

	if ($ssid -ine $TargetSsid) {
		Write-Log -Level "INFO" -Message "Current SSID '$ssid' does not match target '$TargetSsid'. Exiting."
		exit 0
	}

	Write-Log -Level "INFO" -Message "SSID '$ssid' matched target. Waiting $InitialDelaySeconds seconds before portal checks."
	Start-Sleep -Seconds $InitialDelaySeconds

	if (Test-InternetAccess -TimeoutSeconds 6) {
		Write-Log -Level "INFO" -Message "Internet already available. No captive portal action needed."
		exit 0
	}

	$succeeded = $false
	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		try {
			$succeeded = Invoke-CaptivePortalAcceptance -BaseUrl $PortalBaseUrl -TimeoutSeconds $RequestTimeoutSeconds -Attempt $attempt
			if ($succeeded) {
				break
			}
		}
		catch {
			Write-Log -Level "WARN" -Message "Attempt ${attempt} failed: $($_.Exception.Message)"
		}

		if ($attempt -lt $MaxAttempts) {
			$delay = [Math]::Min(2 * $attempt, 8)
			Write-Log -Level "INFO" -Message "Attempt $attempt did not complete. Retrying in $delay seconds."
			Start-Sleep -Seconds $delay
		}
	}

	if ($succeeded) {
		Write-Log -Level "INFO" -Message "Captive portal automation completed successfully."
		exit 0
	}

	Write-Log -Level "ERROR" -Message "Captive portal automation exhausted retries without confirmed success."
	exit 1
}
finally {
	if ($hasLock) {
		$mutex.ReleaseMutex() | Out-Null
	}
	$mutex.Dispose()
}
