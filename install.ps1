# Installs AltC for this user on Windows 10 (1809) or later, with a Bun of its
# own, so nothing else is needed: no Node, no npm, no admin (plan
# 2026-09-25-install).
#
#   irm https://raw.githubusercontent.com/adit-firdaus/altc-public/main/install.ps1 | iex
#
# Running it again updates AltC, and restarts the server when it runs.
# Everything comes from AltC's public releases on GitHub: altc's bundle, and a
# copy of Bun's own release (scripts/release.ts). Each is checked against its
# sha256 in the release's release.txt before it is used.
#
# Settings, from the environment:
#   $env:ALTC_VERSION = '1.2.3'      a version to install (default: the latest)
#   $env:ALTC_HOME = '...'             where it goes (default: %LOCALAPPDATA%\Programs\altc)
#   $env:ALTC_NO_MODIFY_PATH = '1'   leave the user's PATH alone
#   $env:ALTC_NO_RESTART = '1'       leave a running server on the version it runs
#   $env:ALTC_BASE = 'https://...'   another copy of the releases (for testing)
#
# No `exit` anywhere: under `iex` it would close the window it runs in.

function Install-Altc {
  $ErrorActionPreference = 'Stop'
  # Invoke-WebRequest's progress bar makes a download many times slower in Windows PowerShell.
  $ProgressPreference = 'SilentlyContinue'
  # Windows PowerShell may still default to TLS 1.0; GitHub needs 1.2.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  if ([Environment]::OSVersion.Version.Build -lt 17763) { throw 'AltC needs Windows 10 version 1809 or later: its terminals need ConPTY' }
  $base = if ($env:ALTC_BASE) { $env:ALTC_BASE.TrimEnd('/') } else { 'https://github.com/adit-firdaus/altc-public/releases' }
  # Only a test's own server may be plain http.
  if ($base -notmatch '^https://' -and $base -notmatch '^http://(127\.0\.0\.1|localhost):') { throw "ALTC_BASE must be https, not $base" }
  $root = if ($env:ALTC_HOME) { $env:ALTC_HOME } else { Join-Path $env:LOCALAPPDATA 'Programs\altc' }
  if (-not [IO.Path]::IsPathRooted($root)) { throw "ALTC_HOME must be an absolute path, not $root" }
  # The tar that comes with Windows: Git's tar, if first on the PATH, takes C: for a host name.
  $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
  if (-not (Test-Path $tar)) { throw 'tar.exe is missing from System32; AltC needs Windows 10 version 1809 or later' }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("altc-install-" + [Guid]::NewGuid().ToString('n'))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    # The latest release says which version it is; GitHub sends latest/download/ to it.
    if ($env:ALTC_VERSION) {
      $version = $env:ALTC_VERSION.Trim()
      if (-not $version -or $version -match '[\\/]|^\.') { throw "No such altc version: $version" }
      $release = Get-Text "$base/download/v$version/release.txt" $tmp "There is no altc $version at $base"
    } else {
      $release = Get-Text "$base/latest/download/release.txt" $tmp "No answer from $base"
      $version = Get-Field $release 'version'
      if (-not $version -or $version -match '[\\/]|^\.') { throw "The latest release at $base names no version" }
    }
    $bunVersion = Get-Field $release 'bun'
    $bun = Install-Bun $root $tmp $base $tar $bunVersion $release
    Install-Package $root $tmp $base $tar $version (Get-Field $release 'sha256')
    Write-Shim $root $bun $version
    $current = Join-Path $root 'current'
    $old = if (Test-Path $current) { (Get-Content $current -Raw).Trim() } else { '' }
    if ($old -and $old -ne $version) { Set-Content (Join-Path $root 'previous') $old -Encoding ascii }
    Set-Content $current $version -Encoding ascii
    Remove-Old $root $version $bunVersion
    $pathNote = Add-ToPath (Join-Path $root 'bin')
    After $root $version $pathNote
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Say($text) { Write-Host $text -ForegroundColor DarkGray }

# A program's output, without its errors. Windows PowerShell turns a redirected
# error line into an exception under 'Stop', so errors stay on just in here.
function Get-Quietly($exe) {
  $ErrorActionPreference = 'Continue'
  try { & $exe @args 2>$null } catch { $null }
}

# A URL's text, through a file: a response's Content is bytes or text by its type.
function Get-Text($url, $tmp, $problem) {
  $file = Join-Path $tmp 'text'
  try { Invoke-WebRequest -UseBasicParsing $url -OutFile $file } catch { throw $problem }
  return [IO.File]::ReadAllText($file)
}

# A value from release.txt's `name value` lines.
function Get-Field($text, $name) {
  $line = ($text -split "`n") | Where-Object { $_.StartsWith("$name ") } | Select-Object -First 1
  if ($line) { return $line.Substring($name.Length + 1).Trim() }
  return ''
}

function Test-Sha256($file, $want, $what) {
  if (-not $want) { throw "The release gave no checksum for $what" }
  if ((Get-FileHash -Algorithm SHA256 $file).Hash.ToLower() -ne $want.ToLower()) { throw "$what doesn't match its checksum; nothing was changed" }
}

function Get-Target {
  # OSArchitecture, not PROCESSOR_ARCHITECTURE: an x64 PowerShell on an arm64 PC says AMD64.
  $arch = try { [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch { $env:PROCESSOR_ARCHITECTURE }
  switch -Regex ($arch) {
    '^(Arm64|ARM64)$' { return 'windows-aarch64' }
    '^(X64|AMD64)$' {
      Add-Type -Namespace AltcInstall -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int feature);' -ErrorAction SilentlyContinue
      # 40: PF_AVX2_INSTRUCTIONS_AVAILABLE.
      $avx2 = try { [AltcInstall.Cpu]::IsProcessorFeaturePresent(40) } catch { $true }
      if ($avx2) { return 'windows-x64' } else { return 'windows-x64-baseline' }
    }
    default { throw "AltC runs on x64 and arm64, not $arch" }
  }
}

function Install-Bun($root, $tmp, $base, $tar, $bunVersion, $release) {
  if (-not $bunVersion) { throw 'The release gave no Bun version for altc' }
  $dir = Join-Path $root "bun\$bunVersion"
  $exe = Join-Path $dir 'bun.exe'
  if ((Test-Path $exe) -and ((Get-Quietly $exe --version) -eq $bunVersion)) { return $exe }
  $target = Get-Target
  Say "Bun $bunVersion for $target"
  $want = Get-Field $release "bun-$target"
  if (-not $want) { throw "This altc has no Bun for $target" }
  $tgz = Join-Path $tmp 'bun.tgz'
  Invoke-WebRequest -UseBasicParsing "$base/download/bun-v$bunVersion/bun-$target.tgz" -OutFile $tgz
  Test-Sha256 $tgz $want "Bun $bunVersion"
  $unpack = Join-Path $tmp 'bun'
  New-Item -ItemType Directory -Force $unpack | Out-Null
  & $tar -xzf $tgz -C $unpack
  if ($LASTEXITCODE) { throw "Couldn't unpack Bun" }
  $from = Join-Path $unpack 'bun.exe'
  if ((Get-Quietly $from --version) -ne $bunVersion) { throw 'Bun would not start on this machine' }
  New-Item -ItemType Directory -Force $dir | Out-Null
  Move-Item -Force $from $exe
  return $exe
}

function Install-Package($root, $tmp, $base, $tar, $version, $sha256) {
  $dest = Join-Path $root "versions\$version"
  if (Test-Path (Join-Path $dest '.installed')) {
    Say "altc $version is installed already"
    return
  }
  Say "altc $version"
  $tgz = Join-Path $tmp 'altc.tgz'
  Invoke-WebRequest -UseBasicParsing "$base/download/v$version/altc-$version.tgz" -OutFile $tgz
  Test-Sha256 $tgz $sha256 "altc $version"
  $stage = Join-Path $root "versions\.$version.$PID"
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $stage | Out-Null
  & $tar -xzf $tgz -C $stage --strip-components 1
  if ($LASTEXITCODE) {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    throw "Couldn't unpack altc $version"
  }
  New-Item -ItemType File -Force (Join-Path $stage '.installed') | Out-Null
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Move-Item $stage $dest
}

function Write-Shim($root, $bun, $version) {
  $bin = Join-Path $root 'bin'
  New-Item -ItemType Directory -Force $bin | Out-Null
  $cli = Join-Path $root "versions\$version\dist\cli.js"
  # A .cmd, not a .ps1: PowerShell's default execution policy won't run a script.
  # One line, which cmd reads whole before it runs: `altc update` replaces this
  # file while it runs, and cmd reads a batch file on from where it was. A bare
  # `exit /b` loses bun's exit code under cmd /c, which is how PowerShell runs a
  # .cmd; `call` expands %errorlevel% again once bun has ended.
  $shim = "@rem Written by the AltC installer: altc $version on its own Bun. Run the installer again to update.`r`n@`"$bun`" `"$cli`" %* & call exit /b %%errorlevel%%`r`n"
  $file = Join-Path $bin 'altc.cmd'
  [IO.File]::WriteAllText("$file.tmp", $shim, [Text.Encoding]::ASCII)
  Move-Item -Force "$file.tmp" $file
}

# Keeps this version and the one before it, to go back to. Files an old
# terminal host still runs from can't be removed yet: the next install tries again.
function Remove-Old($root, $version, $bunVersion) {
  $previous = Join-Path $root 'previous'
  $keep = if (Test-Path $previous) { (Get-Content $previous -Raw).Trim() } else { '' }
  Get-ChildItem -Force -Directory (Join-Path $root 'versions') | Where-Object { $_.Name -ne $version -and $_.Name -ne $keep } | ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
  Get-ChildItem -Force -Directory (Join-Path $root 'bun') | Where-Object { $_.Name -ne $bunVersion } | ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
}

# Puts the folder on the user's own PATH, keeping %VARIABLES% in it as they are.
function Add-ToPath($bin) {
  $on = ($env:Path -split ';') -contains $bin
  if (-not $on) { $env:Path = "$bin;$env:Path" }
  if ($env:ALTC_NO_MODIFY_PATH) { if ($on) { return '' } else { return "Add $bin to your PATH" } }
  $key = Get-Item 'HKCU:\Environment'
  $path = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  if (($path -split ';') -contains $bin) { return '' }
  $next = if ($path) { "$bin;$path" } else { $bin }
  Set-ItemProperty 'HKCU:\Environment' -Name Path -Value $next -Type ExpandString
  # Setting any user variable through .NET tells Explorer, and so new terminals, that PATH changed.
  [Environment]::SetEnvironmentVariable('ALTC_INSTALL_PING', '1', 'User')
  [Environment]::SetEnvironmentVariable('ALTC_INSTALL_PING', $null, 'User')
  return "Added $bin to your PATH. Open a new terminal to use altc there"
}

function After($root, $version, $pathNote) {
  $altc = Join-Path $root 'bin\altc.cmd'
  Write-Host ''
  Write-Host "altc $version is installed " -NoNewline
  Say "in $root"
  $other = Get-Command altc -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -and $_.Source -ne $altc } | Select-Object -First 1
  if ($other) { Say "Another altc is on your PATH too ($($other.Source)). Remove it to use this one." }
  if ($pathNote) { Write-Host $pathNote }
  # A server running already: move it onto this version.
  if (-not $env:ALTC_NO_RESTART) {
    Get-Quietly $altc status | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Say 'Restarting the server on the new version...'
      & $altc restart
      if ($LASTEXITCODE) { Write-Host "The restart didn't finish. Run: altc restart" }
      return
    }
  }
  Write-Host 'Then start it: ' -NoNewline
  Write-Host 'altc start' -ForegroundColor White
}

try {
  Install-Altc
} catch {
  Write-Host "altc install: $($_.Exception.Message)" -ForegroundColor Red
  # Run as a file (CI, altc update), the exit code says it failed; under iex nothing closes.
  if ($PSCommandPath) { throw }
}
