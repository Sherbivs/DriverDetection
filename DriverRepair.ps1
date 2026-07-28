<# Simple Driver Check / Repair (minimal) #>
<#
Minimal PowerShell 5.1 WPF utility:
  - List installed drivers (Get-WindowsDriver -Online -All)
  - Scan a folder recursively for *.inf
  - Install selected INF(s) with pnputil
Intentionally no logging / caching / filtering / categories.
If you see any text beyond the line '# EOF', the file has unwanted leftovers.
#>
if(-not ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show('Run PowerShell as Administrator.','Driver Check','OK','Warning')|Out-Null
  return
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

function GetInstalledDrivers {
  $items = @()
  try {
    foreach($d in (Get-WindowsDriver -Online -All)){
      $inf = $d.OriginalFileName
      if(-not $inf -and $d.PublishedName -match '\.inf$'){ $inf = $d.PublishedName }
      $pub = $d.PublishedName
      $path = if($pub){ Join-Path $env:WINDIR (Join-Path 'INF' $pub) } elseif($inf){ Join-Path $env:WINDIR (Join-Path 'INF' $inf) }
      $items += [pscustomobject]@{
        FileName  = $inf
        Provider  = $d.ProviderName
        Class     = $d.ClassName
        DriverVer = $d.Version
        Path      = $path
      }
    }
  } catch {}
  $items
}

function GetInfMeta { param([Parameter(Mandatory)][string]$Path)
  $prov=$null;$cls=$null;$ver=$null
  try {
    foreach($ln in (Get-Content -LiteralPath $Path -Encoding ASCII -TotalCount 160)){
      if(-not $prov -and $ln -match '^\s*Provider\s*=\s*(?<v>.+)$'){ $prov=$Matches.v.Trim() }
      if(-not $cls  -and $ln -match '^\s*Class\s*=\s*(?<v>.+)$'){ $cls=$Matches.v.Trim() }
      if(-not $ver  -and $ln -match '^\s*DriverVer\s*=\s*(?<v>.+)$'){ $ver=$Matches.v.Trim() }
      if($prov -and $cls -and $ver){ break }
    }
  } catch {}
  [pscustomobject]@{ FileName=[IO.Path]::GetFileName($Path); Provider=$prov; Class=$cls; DriverVer=$ver; Path=$Path }
}

function ScanFolder { param([Parameter(Mandatory)][string]$Folder)
  $LblStatus.Text='Scanning...'
  $out=@()
  try {
    Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.inf -File -ErrorAction Stop | ForEach-Object { $out += GetInfMeta -Path $_.FullName }
    $LblStatus.Text = "Found $($out.Count) INF files"
  } catch { $LblStatus.Text = "Scan failed: $_" }
  $out
}

function InstallSelected {
  $sel=@($LvAvailable.SelectedItems)
  if($sel.Count -eq 0){ $LblStatus.Text='No selection.'; return }
  $LblStatus.Text='Installing...'
  $ok=0;$fail=0
  foreach($d in $sel){
    try {
      $p = Start-Process pnputil.exe -ArgumentList "/add-driver `"$($d.Path)`" /install" -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
      if($p.ExitCode -eq 0){ $ok++ } else { $fail++ }
    } catch { $fail++ }
  }
  $LblStatus.Text = "Install done. Success:$ok Fail:$fail"
  $LvInstalled.ItemsSource = GetInstalledDrivers
}

$x = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Driver Check / Repair' Width='1150' Height='630' Background='#1f2531' FontFamily='Segoe UI' WindowStartupLocation='CenterScreen'>
  <Window.Resources>
    <SolidColorBrush x:Key='Fg' Color='#e5e7eb'/>
    <Style TargetType='TextBlock'><Setter Property='Foreground' Value='{StaticResource Fg}'/></Style>
    <Style TargetType='ListViewItem'><Setter Property='Foreground' Value='{StaticResource Fg}'/><Setter Property='Background' Value='Transparent'/></Style>
    <Style TargetType='GridViewColumnHeader'><Setter Property='Foreground' Value='{StaticResource Fg}'/><Setter Property='Background' Value='#2d3644'/></Style>
  </Window.Resources>
  <Grid Margin='10'>
    <Grid.RowDefinitions>
      <RowDefinition Height='Auto'/>
      <RowDefinition Height='*'/>
      <RowDefinition Height='Auto'/>
    </Grid.RowDefinitions>
    <DockPanel Grid.Row='0' Margin='0,0,0,8'>
      <TextBlock Text='Folder:' Margin='0,0,6,0'/>
      <TextBox x:Name='TxtFolder' Width='360' Height='26' Margin='0,0,6,0'/>
      <Button x:Name='BtnBrowse' Content='Browse…' Width='90' Height='26' Margin='0,0,6,0'/>
      <Button x:Name='BtnScan' Content='Scan' Width='80' Height='26' Margin='0,0,6,0'/>
      <Button x:Name='BtnInstall' Content='Install Selected' Width='140' Height='26'/>
    </DockPanel>
    <Grid Grid.Row='1'>
      <Grid.ColumnDefinitions>
        <ColumnDefinition/>
        <ColumnDefinition Width='6'/>
        <ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <GroupBox Header='Available (Folder)' Grid.Column='0' Foreground='{StaticResource Fg}'>
        <ListView x:Name='LvAvailable' SelectionMode='Extended' VirtualizingPanel.IsVirtualizing='True' ScrollViewer.CanContentScroll='True'>
          <ListView.View>
            <GridView>
              <GridViewColumn Header='INF' DisplayMemberBinding='{Binding FileName}' Width='180'/>
              <GridViewColumn Header='Provider' DisplayMemberBinding='{Binding Provider}' Width='160'/>
              <GridViewColumn Header='Class' DisplayMemberBinding='{Binding Class}' Width='120'/>
              <GridViewColumn Header='Version' DisplayMemberBinding='{Binding DriverVer}' Width='160'/>
              <GridViewColumn Header='Path' DisplayMemberBinding='{Binding Path}' Width='300'/>
            </GridView>
          </ListView.View>
        </ListView>
      </GroupBox>
      <GridSplitter Grid.Column='1' HorizontalAlignment='Stretch'/>
      <GroupBox Header='Installed (System)' Grid.Column='2' Foreground='{StaticResource Fg}'>
        <ListView x:Name='LvInstalled' VirtualizingPanel.IsVirtualizing='True' ScrollViewer.CanContentScroll='True'>
          <ListView.View>
            <GridView>
              <GridViewColumn Header='INF' DisplayMemberBinding='{Binding FileName}' Width='180'/>
              <GridViewColumn Header='Provider' DisplayMemberBinding='{Binding Provider}' Width='160'/>
              <GridViewColumn Header='Class' DisplayMemberBinding='{Binding Class}' Width='120'/>
              <GridViewColumn Header='Version' DisplayMemberBinding='{Binding DriverVer}' Width='160'/>
              <GridViewColumn Header='Path' DisplayMemberBinding='{Binding Path}' Width='300'/>
            </GridView>
          </ListView.View>
        </ListView>
      </GroupBox>
    </Grid>
    <DockPanel Grid.Row='2'>
      <TextBlock x:Name='LblStatus' Text='Ready.'/>
      <TextBlock Text='  |  Simple Driver Check / Repair' Opacity='0.5'/>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$x)
$win    = [Windows.Markup.XamlReader]::Load($reader)
foreach($n in 'TxtFolder','BtnBrowse','BtnScan','BtnInstall','LvAvailable','LvInstalled','LblStatus'){
  Set-Variable -Name $n -Value ($win.FindName($n)) -Scope Script
}

$BtnBrowse.Add_Click({ $dlg = New-Object System.Windows.Forms.FolderBrowserDialog; if($dlg.ShowDialog() -eq 'OK'){ $TxtFolder.Text = $dlg.SelectedPath } })
$BtnScan.Add_Click({ if(Test-Path -LiteralPath $TxtFolder.Text){ $LvAvailable.ItemsSource = ScanFolder -Folder $TxtFolder.Text } else { $LblStatus.Text='Folder missing.' } })
$BtnInstall.Add_Click({ InstallSelected })

$LvInstalled.ItemsSource = GetInstalledDrivers
[void]$win.ShowDialog()

# EOF
function Ensure-RootCached {
  param([Parameter(Mandatory)] [string]$SourceRoot)
  if (-not (Test-IsNetworkPath $SourceRoot)) { return $SourceRoot }
  try {
    $rootFull = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction SilentlyContinue)
    if (-not $rootFull) { return $SourceRoot }
    $rootFull = $rootFull.Path
    if ($script:CachedRootsMap.ContainsKey($rootFull)) { return $script:CachedRootsMap[$rootFull] }
    $key = Get-CacheKeyFromSourceRoot -SourceRoot $rootFull
    $destRoot = Join-Path $script:CacheRoot $key
    if (Test-Path -LiteralPath $destRoot) {
      # Reuse existing cache
      $script:CachedRootsMap[$rootFull] = $destRoot
      return $destRoot
    }
    Write-Log ("Caching entire driver tree from network: {0} -> {1}" -f $rootFull, $destRoot)
    $ok = $false
    if ($script:UseRobocopy -and (Test-RobocopyAvailable)) {
      $ok = Invoke-RobocopyCache -SourceRoot $rootFull -DestRoot $destRoot -Threads $script:RobocopyThreads
    }
    if (-not $ok) {
      # Fallback to internal copy with UI progress
      $ok = Copy-DirectoryWithProgress -SourceRoot $rootFull -DestRoot $destRoot
    }
    if ($ok) {
      Write-Log ("Cache complete: {0}" -f $destRoot) 'SUCCESS'
      $script:CachedRootsMap[$rootFull] = $destRoot
      return $destRoot
    } else {
      Write-Log 'Cache failed; using network path directly.' 'WARN'
      return $SourceRoot
    }
  } catch { Write-Log ("Ensure-RootCached failed: {0}" -f $_) 'WARN'; return $SourceRoot }
}
#endregion

#region --- Category Filters ---
$script:CategoryFilters = @{
  'Webcams'   = @{ Classes = @('Camera','Image'); Keywords = @('webcam','camera','uvc','imaging','chicony','liteon','sonix','sunplus','quanta','realtek','dell') }
  'Audio'     = @{ Classes = @('Media','Audio');  Keywords = @('audio','sound','nahimic','waves','realtek') }
  'Bluetooth' = @{ Classes = @('Bluetooth');      Keywords = @('bluetooth','bt') }
  'Network'   = @{ Classes = @('Net');            Keywords = @('ethernet','lan','wifi','wireless','intel','killer','ax','iwlwifi') }
  'Storage'   = @{ Classes = @('SCSIAdapter','HDC','USB','DiskDrive'); Keywords = @('nvme','sata','ahci','raid','rst') }
  'Chipset'   = @{ Classes = @('System');         Keywords = @('chipset','management engine','intel chipset','me') }
}
$script:CurrentCategory = $null  # default to Show All so initial installed list isn't empty
#endregion

#region --- WPF UI ---
Add-Type -AssemblyName PresentationCore, WindowsBase, System.Windows.Forms, Microsoft.VisualBasic

    $avail = @(
      $folderInventory | Where-Object {
        $row = $_
        $cls = $row.Class
        $prov = $row.Provider
        $name = $row.FileName
        if (-not (Test-MatchByCategory -Class $cls -Provider $prov -NameOrPath $name -Category $cat)) { return $false }
        if (-not $search) { return $true }
        $s = $search
        return (
          ($name -and $name.ToLower().Contains($s)) -or
          ($prov -and $prov.ToLower().Contains($s)) -or
          ($cls -and $cls.ToLower().Contains($s)) -or
          ($row.DriverVer -and $row.DriverVer.ToLower().Contains($s)) -or
          ($row.Version -and $row.Version.ToLower().Contains($s))
        )
      }
    )
@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Driver Sweep Installer" Width="1700" Height="960" Background="#1a1f29" FontFamily="Segoe UI" WindowStartupLocation="CenterScreen">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <DockPanel Grid.Row="0" LastChildFill="True" Margin="0,0,0,10">
      <TextBlock Text="Driver folder:" Foreground="#e5e7eb" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="TxtFolder" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnBrowse" Content="Browse…" Width="90" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnScan" Content="Scan" Width="80" Height="28"/>
    </DockPanel>

    <!-- Category Bar -->
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock Text="Only:" Foreground="#e5e7eb" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyWebcams" Content="Webcams" Width="100" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyAudio" Content="Audio" Width="90" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyBluetooth" Content="Bluetooth" Width="110" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyNetwork" Content="Network" Width="100" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyStorage" Content="Storage" Width="100" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnOnlyChipset" Content="Chipset" Width="100" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnShowAll" Content="Show All" Width="110" Height="28"/>
    </StackPanel>

    <!-- Search Filter -->
    <DockPanel Grid.Row="2" LastChildFill="True" Margin="0,0,0,10">
      <TextBlock Text="Search:" Foreground="#e5e7eb" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="TxtSearch" Height="26"/>
      <Button x:Name="BtnApplyFilter" Content="Apply" Width="80" Height="26" Margin="8,0,0,0"/>
      <Button x:Name="BtnClearFilter" Content="Clear" Width="80" Height="26" Margin="8,0,0,0"/>
  <CheckBox x:Name="ChkShowTwins" Content="Show twin pairs" Foreground="#e5e7eb" Margin="12,0,0,0" VerticalAlignment="Center"/>
    </DockPanel>

    <!-- Split Lists -->
    <Grid Grid.Row="3">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <GroupBox Header="Available to Install (filtered)" Grid.Column="0" Foreground="#e5e7eb">
        <ListView x:Name="LvAvailable" SelectionMode="Extended" VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" ScrollViewer.CanContentScroll="True">
          <ListView.ItemContainerStyle>
            <Style TargetType="ListViewItem">
              <Setter Property="Background" Value="Transparent"/>
              <Setter Property="Foreground" Value="#e5e7eb"/>
              <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                <Style.Triggers>
                <DataTrigger Binding="{Binding ColorTag}" Value="Newer">
                  <Setter Property="Background" Value="#153e2a"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding ColorTag}" Value="Older">
                  <Setter Property="Background" Value="#3e1a1a"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding ColorTag}" Value="Same">
                  <Setter Property="Background" Value="#2b2b2b"/>
                </DataTrigger>
              </Style.Triggers>
            </Style>
          </ListView.ItemContainerStyle>
          <ListView.View>
            <GridView>
              <GridViewColumn Header="INF" DisplayMemberBinding="{Binding FileName}" Width="220"/>
              <GridViewColumn Header="Version" DisplayMemberBinding="{Binding DriverVer}" Width="160"/>
              <GridViewColumn Header="Provider" DisplayMemberBinding="{Binding Provider}" Width="200"/>
              <GridViewColumn Header="Class" DisplayMemberBinding="{Binding Class}" Width="140"/>
              <GridViewColumn Header="Published" DisplayMemberBinding="{Binding PublishedName}" Width="120"/>
              <GridViewColumn Header="Path" DisplayMemberBinding="{Binding Path}" Width="300"/>
            </GridView>
          </ListView.View>
          <ListView.ContextMenu>
            <ContextMenu x:Name="CtxAvailable">
              <MenuItem Header="Copy row (tab-separated)" x:Name="CopyRowAvailable"/>
              <MenuItem Header="Copy selected rows (CSV)" x:Name="CopySelectedAvailableCsv"/>
              <Separator/>
              <MenuItem Header="Copy field">
                <MenuItem Header="INF" x:Name="CopyAvail_FileName"/>
                <MenuItem Header="Version" x:Name="CopyAvail_DriverVer"/>
                <MenuItem Header="Provider" x:Name="CopyAvail_Provider"/>
                <MenuItem Header="Class" x:Name="CopyAvail_Class"/>
                <MenuItem Header="Path" x:Name="CopyAvail_Path"/>
              </MenuItem>
            </ContextMenu>
          </ListView.ContextMenu>
        </ListView>
      </GroupBox>

      <GridSplitter Grid.Column="1" HorizontalAlignment="Stretch"/>

      <GroupBox Header="Already Installed (filtered)" Grid.Column="2" Foreground="#e5e7eb">
        <ListView x:Name="LvInstalled" VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" ScrollViewer.CanContentScroll="True">
          <ListView.ItemContainerStyle>
            <Style TargetType="ListViewItem">
              <Setter Property="Background" Value="Transparent"/>
              <Setter Property="Foreground" Value="#e5e7eb"/>
              <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
              <Style.Triggers>
                <DataTrigger Binding="{Binding ColorTag}" Value="Newer">
                  <Setter Property="Background" Value="#153e2a"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding ColorTag}" Value="Older">
                  <Setter Property="Background" Value="#3e1a1a"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding ColorTag}" Value="Same">
                  <Setter Property="Background" Value="#2b2b2b"/>
                </DataTrigger>
              </Style.Triggers>
            </Style>
          </ListView.ItemContainerStyle>
          <ListView.View>
            <GridView>
              <GridViewColumn Header="INF" DisplayMemberBinding="{Binding FileName}" Width="180"/>
              <GridViewColumn Header="Version" DisplayMemberBinding="{Binding DriverVer}" Width="140"/>
              <GridViewColumn Header="Provider" DisplayMemberBinding="{Binding Provider}" Width="180"/>
              <GridViewColumn Header="Class" DisplayMemberBinding="{Binding Class}" Width="120"/>
              <GridViewColumn Header="Published" DisplayMemberBinding="{Binding PublishedName}" Width="120"/>
              <GridViewColumn Header="Path" DisplayMemberBinding="{Binding Path}" Width="200"/>
            </GridView>
          </ListView.View>
          <ListView.ContextMenu>
            <ContextMenu x:Name="CtxInstalled">
              <MenuItem Header="Copy row (tab-separated)" x:Name="CopyRowInstalled"/>
              <MenuItem Header="Copy selected rows (CSV)" x:Name="CopySelectedInstalledCsv"/>
              <Separator/>
              <MenuItem Header="Copy field">
                <MenuItem Header="INF" x:Name="CopyInst_OriginalFileName"/>
                <MenuItem Header="Version" x:Name="CopyInst_Version"/>
                <MenuItem Header="Provider" x:Name="CopyInst_ProviderName"/>
                <MenuItem Header="Class" x:Name="CopyInst_ClassName"/>
                <MenuItem Header="Published" x:Name="CopyInst_PublishedName"/>
              </MenuItem>
              <Separator/>
              <MenuItem Header="Open file location (INF)" x:Name="OpenInstalledInf"/>
            </ContextMenu>
          </ListView.ContextMenu>
        </ListView>
      </GroupBox>
    </Grid>

  <!-- Footer -->
    <DockPanel Grid.Row="4" LastChildFill="True" Margin="0,12,0,0">
      <ProgressBar x:Name="Prg" Width="260" Height="20" Minimum="0" Maximum="100" Margin="0,0,8,0"/>
  <TextBlock x:Name="LblStatus" Foreground="#e5e7eb" Margin="0,0,12,0" VerticalAlignment="Center"/>
    <Button x:Name="BtnInstallSelected" Content="Install Selected" Width="130" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnInstallAll" Content="Install All (Filtered)" Width="150" Height="28" Margin="0,0,8,0"/>
  <Button x:Name="BtnRemoveSelected" Content="Remove Selected (Installed)" Width="200" Height="28" Margin="0,0,8,0"/>
  <Button x:Name="BtnRollback" Content="Rollback Last Install Batch" Width="200" Height="28" Margin="0,0,8,0"/>
  <Button x:Name="BtnRestoreRemoval" Content="Restore Last Removal" Width="170" Height="28" Margin="0,0,8,0"/>
  <Button x:Name="BtnExportInstalled" Content="Export Installed…" Width="150" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="BtnRefresh" Content="Refresh" Width="90" Height="28" Margin="0,0,8,0"/>
  <Button x:Name="BtnCleanup" Content="Cleanup…" Width="100" Height="28" Margin="0,0,8,0"/>
      <TextBox x:Name="TxtLog" Height="90" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" TextWrapping="Wrap"/>
    </DockPanel>

    <!-- Startup overlay -->
    <Grid x:Name="StartupOverlay" Background="#BF0f1115" Visibility="Collapsed" Grid.RowSpan="5">
      <Border Width="480" Padding="20" Background="#1f2430" CornerRadius="8" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock x:Name="TxtStartupStatus" Text="Loading installed drivers…" Foreground="#e5e7eb" FontSize="16" Margin="0,0,0,10"/>
          <ProgressBar x:Name="PrgStartup" IsIndeterminate="True" Height="18" Minimum="0" Maximum="100"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnStartupCancel" Content="Cancel" Width="90" Height="28"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$Xaml))
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Controls
$TxtFolder     = $Window.FindName('TxtFolder')
$BtnBrowse     = $Window.FindName('BtnBrowse')
$BtnScan       = $Window.FindName('BtnScan')
$TxtSearch     = $Window.FindName('TxtSearch')
$BtnApplyFilter= $Window.FindName('BtnApplyFilter')
$BtnClearFilter= $Window.FindName('BtnClearFilter')
$ChkShowTwins  = $Window.FindName('ChkShowTwins')
$BtnOnlyWebcams= $Window.FindName('BtnOnlyWebcams')
$BtnOnlyAudio  = $Window.FindName('BtnOnlyAudio')
$BtnOnlyBluetooth = $Window.FindName('BtnOnlyBluetooth')
$BtnOnlyNetwork= $Window.FindName('BtnOnlyNetwork')
$BtnOnlyStorage= $Window.FindName('BtnOnlyStorage')
$BtnOnlyChipset= $Window.FindName('BtnOnlyChipset')
$BtnShowAll    = $Window.FindName('BtnShowAll')
$LvAvailable   = $Window.FindName('LvAvailable')
$LvInstalled   = $Window.FindName('LvInstalled')
$BtnInstallSelected = $Window.FindName('BtnInstallSelected')
$BtnInstallAll = $Window.FindName('BtnInstallAll')
$BtnRemoveSelected = $Window.FindName('BtnRemoveSelected')
$BtnRollback = $Window.FindName('BtnRollback')
$BtnRestoreRemoval = $Window.FindName('BtnRestoreRemoval')
$BtnExportInstalled = $Window.FindName('BtnExportInstalled')
$BtnRefresh    = $Window.FindName('BtnRefresh')
$Prg           = $Window.FindName('Prg')
$LblStatus     = $Window.FindName('LblStatus')
$script:UiLogBox = $Window.FindName('TxtLog')
$StartupOverlay = $Window.FindName('StartupOverlay')
$PrgStartup     = $Window.FindName('PrgStartup')
$TxtStartupStatus = $Window.FindName('TxtStartupStatus')
$BtnStartupCancel = $Window.FindName('BtnStartupCancel')

#endregion

#region --- State & Filtering ---
$script:ApplyFilterRunning = $false
$script:InstalledCacheAll = @()
$script:InstalledFiltered = @()
$script:FolderInventoryAll = @()
$script:AvailableFiltered  = @()
$script:LastInstallPublishedNames = @()
$script:GuardScanFromSearch = $false
$script:ColorTagImmediateThreshold = 15000  # skip color tagging when total rows exceed this
$script:InitialLoadComplete = $false
$script:ScanInProgress = $false
$script:ScanCancel = $false

function Get-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
}

function Get-DriverVersionInfo {
  param([string]$Text)
  $result = [ordered]@{ Date=$null; Version=$null; Raw=$Text }
  if ([string]::IsNullOrWhiteSpace($Text)) { return [pscustomobject]$result }
  $t = $Text.Trim()
  # Accepted forms: 'MM/DD/YYYY,version'  'MM/DD/YYYY version'  or just 'version'
  $date = $null; $ver = $null
  if ($t -match '^(?<d>\d{1,2}/\d{1,2}/\d{2,4})\s*[ ,]\s*(?<v>[^\s,]+)') {
    [void][DateTime]::TryParse($Matches.d, [ref]$date)
    $verStr = $Matches.v
    try { $ver = [version]$verStr } catch { $ver = $null }
  } else {
    # Try version only
    $parts = $t.Split(' ,') | Where-Object { $_ }
    foreach ($p in $parts) {
      try { $ver = [version]$p; break } catch {}
    }
  }
  $result.Date = $date
  $result.Version = $ver
  return [pscustomobject]$result
}

function Compare-DriverVersions {
  param([string]$Left, [string]$Right)
  $l = Get-DriverVersionInfo $Left
  $r = Get-DriverVersionInfo $Right
  # Prefer Version compare when both available
  if ($l.Version -and $r.Version) {
    if ($l.Version -gt $r.Version) { return 1 }
    if ($l.Version -lt $r.Version) { return -1 }
    # equal version, use date as tiebreaker
    if ($l.Date -and $r.Date) {
      if ($l.Date -gt $r.Date) { return 1 }
      if ($l.Date -lt $r.Date) { return -1 }
    }
    return 0
  }
  # Fallback to date if both dates exist
  if ($l.Date -and $r.Date) {
    if ($l.Date -gt $r.Date) { return 1 }
    if ($l.Date -lt $r.Date) { return -1 }
    return 0
  }
  # Last resort: string compare
  if ($Left -and $Right) { return [string]::Compare($Left,$Right,$true) }
  return 0
}

function Import-InstalledCache {
  Write-Log "Loading installed drivers…"
  $script:InstalledCacheAll = Get-InstalledDrivers
  Invoke-Filter
}

function Scan-Folder {
  param([string]$Folder)
  if ($script:ScanInProgress) {
    # If already scanning, treat invocation as cancel request (safety guard if handler missed)
    if (-not $script:ScanCancel) { $script:ScanCancel = $true; Write-Log 'Cancellation requested (re-entrant call).' 'WARN'; if ($LblStatus) { $LblStatus.Text = 'Canceling scan…' } }
    return
  }
  $script:ScanInProgress = $true
  $script:ScanCancel = $false
  $origBtnText = $null
  try { if ($BtnScan) { $origBtnText = $BtnScan.Content; $BtnScan.Content = 'Cancel'; } } catch {}
  try {
    if (-not (Test-Path -LiteralPath $Folder)) { throw "Folder not found: $Folder" }
    Write-Log ("Scanning folder for drivers: {0}" -f $Folder)
    if ($LblStatus) { $LblStatus.Text = 'Starting scan…' }
    if ($Prg) { $Prg.IsIndeterminate = $true; $Prg.Value = 0 }
  
    # If network source, cache entire tree locally once for fast, reliable operations
    $scanRoot = $Folder
    if (Test-IsNetworkPath $Folder) {
      $scanRoot = Ensure-RootCached -SourceRoot $Folder
      if ($scanRoot -ne $Folder) { Write-Log ("Scanning from local cache: {0}" -f $scanRoot) }
    }
  # Phase 1: enumerate directories and files with determinate progress
  Write-Log "Enumerating .inf files…"
  if ($LblStatus) { $LblStatus.Text = 'Enumerating folders…' }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $infs = @()
  Write-Log 'SCAN TRACE: Phase1 begin' 'DEBUG'
  try {
    # First attempt: simple recursive enumeration (fast path)
    $fastEnum = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue | Select-Object -Expand FullName)
    if ($fastEnum.Count -gt 0) {
      Write-Log ("Fast enumeration found {0} INF file(s)." -f $fastEnum.Count) 'INFO'
      $infs = $fastEnum
    }
    if (-not $infs -or $infs.Count -eq 0) {
    $dirs = @(Enumerate-DirectoriesRobust -Root $scanRoot)
    if ($dirs.Count -eq 0) { $dirs = @($scanRoot) }
    if ($Prg) { $Prg.IsIndeterminate = $false; $Prg.Minimum = 0; $Prg.Maximum = [math]::Max(1,$dirs.Count); $Prg.Value = 0 }
    $di = 0
    foreach ($d in $dirs) {
      if ($script:ScanCancel) { Write-Log 'Scan canceled during directory enumeration.' 'WARN'; break }
      $di++
      try {
        $ext = Resolve-ExtendedPath -Path $d
        foreach ($f in [System.IO.Directory]::EnumerateFiles($ext, '*.inf')) { $infs += (Normalize-FromExtendedPath $f) }
      } catch { }
      if ($Prg) { $Prg.Value = $di }
      if ($LblStatus) { $LblStatus.Text = "Scanning dir $di/$($dirs.Count): $([IO.Path]::GetFileName($d))" }
  $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)
      [System.Windows.Forms.Application]::DoEvents()
    }
    if (-not $infs -or $infs.Count -eq 0) {
      # Fallback to PowerShell enumeration in case of permission peculiarities
      if ($Prg) { $Prg.IsIndeterminate = $true; $Prg.Value = 0 }
      $infs = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -Filter *.inf -ErrorAction SilentlyContinue | Select-Object -Expand FullName)
    }
      }
    } catch {
      Write-Log ("Primary enumeration failed for {0}: {1}" -f $Folder, $_) 'WARN'
      if ($Prg) { $Prg.IsIndeterminate = $true; $Prg.Value = 0 }
      $infs = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -Filter *.inf -ErrorAction SilentlyContinue | Select-Object -Expand FullName)
    }
    $sw.Stop()
    Write-Log ("Found {0} .inf file(s) in {1:n1}s" -f $infs.Count, ($sw.Elapsed.TotalSeconds))
    Write-Log 'SCAN TRACE: Phase1 end' 'DEBUG'
    if ($LblStatus) { $LblStatus.Text = "Found $($infs.Count) INF(s); parsing…" }
  if ($infs.Count -eq 0) { Write-Log "No INF files discovered. Ensure folder contains extracted driver packages (.inf)." 'WARN' }

  # Phase 2: parse metadata with determinate progress
  Write-Log 'SCAN TRACE: Phase2 setup progress' 'DEBUG'
  if ($Prg) { $Prg.IsIndeterminate = $false; $Prg.Minimum = 0; $Prg.Maximum = [math]::Max(1,$infs.Count); $Prg.Value = 0 }
  try { $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render) } catch { Write-Log ("SCAN TRACE: Dispatcher.Invoke (pre-loop) failed: " + $_) 'WARN' }
    Write-Log 'SCAN TRACE: Phase2 loop begin' 'DEBUG'
    $parsed = New-Object System.Collections.Generic.List[object]
    $i = 0
    $lastUi = [datetime]::UtcNow
    foreach ($p in $infs) {
      if ($script:ScanCancel) { Write-Log 'Scan canceled during metadata parsing.' 'WARN'; break }
      $i++
      try { $meta = Get-InfMetadata -InfPath $p } catch { $meta = $null; Write-Log ("Metadata parse failed: {0} — {1}" -f $p, $_) 'WARN' }
      if ($meta) { [void]$parsed.Add($meta) }
      if ($Prg) {
        $Prg.Value = $i
        $needPump = ($i -le 2) -or ($i -eq $infs.Count) -or (([datetime]::UtcNow - $lastUi).TotalMilliseconds -ge 33)
        if ($needPump) {
          if ($LblStatus) { $LblStatus.Text = "Parsing $i/$($infs.Count): $([IO.Path]::GetFileName($p))" }
          try { $null = $Prg.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Render) } catch { Write-Log ("SCAN TRACE: Dispatcher.Invoke (loop) failed: " + $_) 'WARN' }
          [System.Windows.Forms.Application]::DoEvents()
          $lastUi = [datetime]::UtcNow
        }
      }
    }
    Write-Log 'SCAN TRACE: Phase2 loop end' 'DEBUG'
    $parsedArray = @()
    try {
      # Convert generic List[object] to plain object[] so downstream filters see each item, not the list itself
      $parsedArray = @($parsed.ToArray())
    } catch {
      Write-Log ("SCAN TRACE: ToArray failed, fallback enumerate list: " + $_) 'WARN'
      $parsedArray = @($parsed | ForEach-Object { $_ })
    }
    $script:FolderInventoryAll = $parsedArray
    Write-Log ("Parsed metadata for {0} file(s) (parsedListType={1} assignedType={2})" -f $parsedArray.Count, $parsed.GetType().FullName, ($script:FolderInventoryAll.GetType().FullName))
    if ($parsedArray.Count -gt 0) { Write-Log ("First parsed element type: " + $parsedArray[0].GetType().FullName) 'DEBUG' }
    try {
      if ($parsed.Count -gt 0) {
  $sample = $parsed | Select-Object -First 3 | ForEach-Object { "[FileName=$($_.FileName);Class=$($_.Class);Provider=$($_.Provider);Ver=$($_.DriverVer)]" }
  Write-Log ("Sample parsed entries: " + ($sample -join ' ')) 'DEBUG'
      }
    } catch { Write-Log ("SCAN TRACE: sample build failed: " + $_) 'WARN' }
    if ($script:ScanCancel) {
      Write-Log 'Scan canceled by user before filtering.' 'WARN'
      if ($Prg) { $Prg.Value = 0; $Prg.IsIndeterminate = $false }
      if ($LblStatus) { $LblStatus.Text = 'Scan canceled.' }
    } else {
      Write-Log 'SCAN TRACE: Before Invoke-Filter' 'DEBUG'
      Invoke-Filter
      Write-Log 'SCAN TRACE: After Invoke-Filter' 'DEBUG'
      if ($Prg) { $Prg.Value = 0; $Prg.IsIndeterminate = $false }
      if ($LblStatus) { $LblStatus.Text = "Scan complete. Available: $($script:AvailableFiltered.Count)" }
    }
  } catch {
    $etype = $_.Exception.GetType().FullName
    Write-Log ("Scan-Folder fatal: $etype :: $_ :: Stack=`n$($_.ScriptStackTrace)") 'ERROR'
    throw
  } finally {
    $script:ScanInProgress = $false
    $script:ScanCancel = $false
    try { if ($BtnScan -and $origBtnText) { $BtnScan.Content = $origBtnText } } catch {}
  }
}

function Test-MatchByCategory {
  param(
    [string]$Class,
    [string]$Provider,
    [string]$NameOrPath,
    [string]$Category
  )
  if (-not $Category) { return $true }
  if (-not ($script:CategoryFilters) -or -not ($script:CategoryFilters.ContainsKey($Category))) { return $true }
  $rule = $script:CategoryFilters[$Category]
  if (-not $rule) { return $true }

  $classes  = @($rule.Classes)
  $keywords = @($rule.Keywords)

  if ($classes.Count -gt 0) {
    $clsLower = ([string]$Class).ToLower()
    $matched = $false
    foreach ($c in $classes) { if ($clsLower -like ("*" + [string]$c + "*")) { $matched = $true; break } }
    if (-not $matched) { return $false }
  }
  if ($keywords.Count -gt 0) {
    $hay = ("{0} {1} {2}" -f ([string]$NameOrPath), ([string]$Provider), ([string]$Class)).ToLower()
    foreach ($kw in $keywords) { if ($hay -like ("*" + ([string]$kw).ToLower() + "*")) { return $true } }
    return $false
  }
  return $true
}

# --- Simplified filtering path (SimpleMode) ---
function Invoke-FilterSimple {
  try {
  Write-Log 'Invoke-FilterSimple invoked.' 'DEBUG'
    $search = ([string]$TxtSearch.Text).Trim().ToLower()
    $cat    = $script:CurrentCategory
  $catLabel = 'ALL'
  if ($cat) { $catLabel = $cat }
    # Diagnostics of collection shapes
    try {
      $instType = if ($script:InstalledCacheAll -and $script:InstalledCacheAll.Count -gt 0) { $script:InstalledCacheAll[0].GetType().FullName } else { 'EMPTY' }
      $folderCount = if ($script:FolderInventoryAll) { ($script:FolderInventoryAll | Measure-Object).Count } else { 0 }
      $folderFirstType = if ($folderCount -gt 0) { ($script:FolderInventoryAll | Select-Object -First 1).GetType().FullName } else { 'EMPTY' }
      Write-Log ("FilterSimple pre: InstalledCount={0} InstalledFirstType={1} FolderCount={2} FolderFirstType={3}" -f ($script:InstalledCacheAll.Count), $instType, $folderCount, $folderFirstType) 'DEBUG'
    } catch { Write-Log ("FilterSimple pre diagnostics failed: " + $_) 'WARN' }
    # Installed side
  $installedAll = @($script:InstalledCacheAll) | Where-Object { $_ }
    $script:InstalledFiltered = @(
      $installedAll | Where-Object {
        $row = $_
        # Category test uses unified Class/Provider/FileName; fall back to legacy if missing
        $cls = if ($row.PSObject.Properties['Class']) { $row.Class } else { $row.ClassName }
        $prov= if ($row.PSObject.Properties['Provider']) { $row.Provider } else { $row.ProviderName }
        $name= if ($row.PSObject.Properties['FileName']) { $row.FileName } else { $row.OriginalFileName }
        if (-not (Test-MatchByCategory -Class $cls -Provider $prov -NameOrPath $name -Category $cat)) { return $false }
        if (-not $search) { return $true }
        $s = $search
        return (
          ($name -and $name.ToLower().Contains($s)) -or
          ($prov -and $prov.ToLower().Contains($s)) -or
          ($cls -and $cls.ToLower().Contains($s)) -or
          ($row.DriverVer -and $row.DriverVer.ToLower().Contains($s)) -or
          ($row.Version -and $row.Version.ToLower().Contains($s))
        )
      }
    )
    if ($LvInstalled) { $LvInstalled.ItemsSource = $null; $LvInstalled.ItemsSource = $script:InstalledFiltered }

    # Debug: detect any rows lacking FileName which would render blank under new bindings
    try {
      $missingInstalled = @($script:InstalledFiltered | Where-Object { -not $_.FileName })
      if ($missingInstalled.Count -gt 0) { Write-Log ("WARN: Installed rows missing FileName: {0}" -f $missingInstalled.Count) 'WARN' }
      $missingAvail = @($avail | Where-Object { -not $_.FileName })
      if ($missingAvail.Count -gt 0) { Write-Log ("WARN: Available rows missing FileName: {0}" -f $missingAvail.Count) 'WARN' }
    } catch { Write-Log ("FileName missing diagnostics failed: " + $_) 'WARN' }

    # Available side (only if a scan has run)
  $folderInventory = @($script:FolderInventoryAll) | Where-Object { $_ }
    $avail = @(
      $folderInventory | Where-Object {
        $row = $_
        if (-not (Test-MatchByCategory -Class $row.Class -Provider $row.Provider -NameOrPath ($row.FileName + ' ' + $row.Path) -Category $cat)) { return $false }
        if (-not $search) { return $true }
        $s = $search
        return (
          ($row.FileName -and $row.FileName.ToLower().Contains($s)) -or
          ($row.Path -and $row.Path.ToLower().Contains($s)) -or
          ($row.Provider -and $row.Provider.ToLower().Contains($s)) -or
          ($row.Class -and $row.Class.ToLower().Contains($s)) -or
          ($row.DriverVer -and $row.DriverVer.ToLower().Contains($s))
        )
      }
    )
    # Hide twins unless checkbox set (PS 5.1 safe HashSet)
    if ($script:SimpleModeShowTwinsByDefault -and $ChkShowTwins -and $ChkShowTwins.IsChecked -eq $false) { $ChkShowTwins.IsChecked = $true }
    $showTwins = ($ChkShowTwins -and $ChkShowTwins.IsChecked)
    if (-not $showTwins) {
      try {
        $installedNameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($d in $installedAll) { if ($d.OriginalFileName) { [void]$installedNameSet.Add([string]$d.OriginalFileName) } }
        $avail = @($avail | Where-Object { $_.FileName -and -not $installedNameSet.Contains([string]$_.FileName) })
      } catch { Write-Log ("Twin filtering failed: " + $_) 'WARN' }
    }
    $script:AvailableFiltered = $avail
    if ($LvAvailable) {
      try {
        $LvAvailable.ItemsSource = $null
        $LvAvailable.ItemsSource = @($script:AvailableFiltered)
      } catch {
        Write-Log ("LvAvailable ItemsSource assignment error: " + $_) 'ERROR'
      }
    }
  Write-Log ("Simple filter applied (Installed={0} Available={1} Cat='{2}' Search='{3}')" -f $script:InstalledFiltered.Count,$script:AvailableFiltered.Count,$catLabel,$search) 'DEBUG'
  if ($LblStatus) { $LblStatus.Text = "Installed: $($script:InstalledFiltered.Count) | Available: $($script:AvailableFiltered.Count)" }
  } catch {
    Write-Log ("Invoke-FilterSimple error: " + $_) 'ERROR'
  }
}

function Invoke-Filter {
  if ($script:SimpleMode) { Invoke-FilterSimple; return }
  if ($script:ApplyFilterRunning) { return }
  $script:ApplyFilterRunning = $true
  try {
  $swFilter = [System.Diagnostics.Stopwatch]::StartNew()
  Write-Log ("Invoke-Filter START (InitialLoadComplete={0})" -f $script:InitialLoadComplete) 'DEBUG'
  $search = ([string]$TxtSearch.Text).Trim()
  $cat    = $script:CurrentCategory

  # If search looks like a folder path (UNC or drive) and exists, scan that folder.
  try {
    if (-not $script:GuardScanFromSearch) {
      $looksLikePath = $false
      if ($search) {
        # UNC \\server\share or X:\path
        if ($search -match '^(\\\\|[A-Za-z]:\\)') { $looksLikePath = $true }
      }
      if ($looksLikePath -and (Test-Path -LiteralPath $search -PathType Container)) {
        $script:GuardScanFromSearch = $true
        if ($TxtFolder.Text -ne $search) { $TxtFolder.Text = $search }
        Scan-Folder -Folder $search
      }
    }
  } catch { Write-Log ("Scan from search failed: {0}" -f $_) 'WARN' }
  finally { $script:GuardScanFromSearch = $false }

  # Coerce inventories to arrays to guarantee .Count exists under StrictMode
  $folderInventory = @($script:FolderInventoryAll)
  $installedAll = @($script:InstalledCacheAll)

  # Available (from folder)
  $avail = $folderInventory | Where-Object {
    $row = $_
    $catOk = Test-MatchByCategory -Class $row.Class -Provider $row.Provider -NameOrPath ($row.FileName + ' ' + $row.Path) -Category $cat
    if (-not $catOk) { return $false }
    if ([string]::IsNullOrWhiteSpace($search)) { return $true }
    $s = $search.ToLower()
    return ($row.FileName.ToLower().Contains($s) -or $row.Path.ToLower().Contains($s) -or ($row.Provider -and $row.Provider.ToLower().Contains($s)) -or ($row.Class -and $row.Class.ToLower().Contains($s)) -or ($row.DriverVer -and $row.DriverVer.ToLower().Contains($s)))
  }
  $availArray = if ($null -eq $avail) { @() } else { @($avail) }
  if ($folderInventory.Count -eq 0) { Write-Log 'Invoke-Filter: FolderInventoryAll empty (scan produced 0 parsed INFs).' 'WARN' }
  Write-Log ("Invoke-Filter: raw inventory={0} after category/search filter={1} (category='{2}', search='{3}')" -f ($folderInventory.Count), ($availArray.Count), $cat, $search) 'DEBUG'

  # Exclude by INF name if already installed (same OriginalFileName)
  $installedMap = @{}
  foreach ($d in $installedAll) { if ($d.OriginalFileName) { $installedMap[$d.OriginalFileName.ToLower()] = $true } }
  $showTwins = ($ChkShowTwins -and $ChkShowTwins.IsChecked)
  if ($showTwins) {
    $script:AvailableFiltered = Get-Array $availArray
  } else {
    $script:AvailableFiltered = Get-Array ($availArray | Where-Object { $_.FileName -and -not $installedMap.ContainsKey( (($_.FileName) -as [string]).ToLower() ) })
  }
  if ($availArray.Count -gt 0 -and $script:AvailableFiltered.Count -eq 0 -and -not $showTwins) {
    Write-Log 'All available drivers filtered out because matching INF names already installed and Show Twins disabled.' 'INFO'
  }
  if ($script:AvailableFiltered.Count -eq 0) {
    Write-Log 'AvailableFiltered empty. Possible causes: (1) Wrong category selected; (2) Search too restrictive; (3) Only twins hidden; (4) INF parse failed (see earlier logs).' 'WARN'
  }
  if ($LvAvailable) { $LvAvailable.ItemsSource = $null; $LvAvailable.ItemsSource = @($script:AvailableFiltered) }

  # Installed (on this PC) — filter to category and search
  $inst = $installedAll | Where-Object {
    $row = $_
    $catOk = Test-MatchByCategory -Class $row.ClassName -Provider $row.ProviderName -NameOrPath $row.OriginalFileName -Category $cat
    if (-not $catOk) { return $false }
    if ([string]::IsNullOrWhiteSpace($search)) { return $true }
    $s = $search.ToLower()
    return ($row.OriginalFileName.ToLower().Contains($s) -or ($row.ProviderName -and $row.ProviderName.ToLower().Contains($s)) -or ($row.ClassName -and $row.ClassName.ToLower().Contains($s)) -or ($row.Version -and $row.Version.ToLower().Contains($s)))
  }
  $script:InstalledFiltered = if ($null -eq $inst) { @() } else { @($inst) }
  
  $totalForTag = $script:InstalledFiltered.Count + $script:AvailableFiltered.Count
  $doTag = $true
  if (-not $script:InitialLoadComplete) { $doTag = $false; Write-Log 'Skipping color tagging during initial load (defer until UI stable).' 'DEBUG' }
  elseif ($totalForTag -gt $script:ColorTagImmediateThreshold) { $doTag = $false }
  # If we have installed drivers overall but none matched the chosen category (and user hasn't picked a folder yet), auto-fallback once.
  if ($script:InitialLoadComplete -and $script:InstalledFiltered.Count -eq 0 -and $installedAll.Count -gt 0 -and $cat) {
    Write-Log ("No installed drivers matched category '{0}'. Auto-switching to Show All." -f $cat) 'INFO'
    $script:CurrentCategory = $null
    $cat = $null
    # Re-run filter quickly (prevent reentrancy by temporarily clearing flag)
    $script:ApplyFilterRunning = $false
    return Invoke-Filter
  }
  if ($doTag) {
    $mapInstalledByKey = @{ }
  foreach ($d in $installedAll) {
      $key = (([string]$d.ProviderName).Trim().ToLower() + '|' + ([string]$d.ClassName).Trim().ToLower() + '|' + ([string]$d.OriginalFileName).Trim().ToLower())
      if (-not $mapInstalledByKey.ContainsKey($key)) { $mapInstalledByKey[$key] = @() }
      $mapInstalledByKey[$key] += $d
    }
    $mapAvailableByKey = @{ }
  foreach ($a in $folderInventory) {
      $key = (([string]$a.Provider).Trim().ToLower() + '|' + ([string]$a.Class).Trim().ToLower() + '|' + ([string]$a.FileName).Trim().ToLower())
      if (-not $mapAvailableByKey.ContainsKey($key)) { $mapAvailableByKey[$key] = @() }
      $mapAvailableByKey[$key] += $a
    }
    foreach ($row in $script:AvailableFiltered) {
      $key = (([string]$row.Provider).Trim().ToLower() + '|' + ([string]$row.Class).Trim().ToLower() + '|' + ([string]$row.FileName).Trim().ToLower())
      if (-not ($row.PSObject.Properties['ColorTag'])) { $row | Add-Member -NotePropertyName ColorTag -NotePropertyValue $null -Force }
      if ($mapInstalledByKey.ContainsKey($key)) {
        $best = $mapInstalledByKey[$key] | Sort-Object -Property @{Expression={ (Get-DriverVersionInfo $_.Version).Version }}, @{Expression={ (Get-DriverVersionInfo $_.Date).Date }} -Descending | Select-Object -First 1
        $cmp = Compare-DriverVersions -Left $row.DriverVer -Right $best.Version
        if ($cmp -gt 0) { $row.ColorTag = 'Newer' }
        elseif ($cmp -lt 0) { $row.ColorTag = 'Older' }
        else { $row.ColorTag = 'Same' }
      }
    }
    foreach ($row in $script:InstalledFiltered) {
      $key = (([string]$row.ProviderName).Trim().ToLower() + '|' + ([string]$row.ClassName).Trim().ToLower() + '|' + ([string]$row.OriginalFileName).Trim().ToLower())
      if (-not ($row.PSObject.Properties['ColorTag'])) { $row | Add-Member -NotePropertyName ColorTag -NotePropertyValue $null -Force }
      if ($mapAvailableByKey.ContainsKey($key)) {
        $best = $mapAvailableByKey[$key] | Sort-Object -Property @{Expression={ (Get-DriverVersionInfo $_.DriverVer).Version }}, @{Expression={ (Get-DriverVersionInfo $_.DriverVer).Date }} -Descending | Select-Object -First 1
        $cmp = Compare-DriverVersions -Left $best.DriverVer -Right $row.Version
        if ($cmp -gt 0) { $row.ColorTag = 'Older' }
        elseif ($cmp -lt 0) { $row.ColorTag = 'Newer' }
        else { $row.ColorTag = 'Same' }
      }
    }
  } else {
    Write-Log ("Skipping color tagging (rows={0} threshold={1}) to avoid UI freeze" -f $totalForTag,$script:ColorTagImmediateThreshold) 'WARN'
  }
  try {
    $LvInstalled.ItemsSource = $null
    $LvInstalled.ItemsSource = @($script:InstalledFiltered)
  } catch { Write-Log ("LvInstalled ItemsSource assignment error: " + $_) 'ERROR' }
    $swFilter.Stop(); Write-Log ("Invoke-Filter END {0} ms (Avail={1} Inst={2} Tagged={3})" -f $swFilter.ElapsedMilliseconds,$script:AvailableFiltered.Count,$script:InstalledFiltered.Count, (if ($doTag) { 'Yes' } else { 'No' })) 'DEBUG'
  } catch {
    Write-Log ("Invoke-Filter hard failure: " + $_) 'ERROR'
  } finally { $script:ApplyFilterRunning = $false }
}
#endregion

#region --- Installation ---
function Invoke-InstallDrivers {
  param([System.Collections.IEnumerable]$Items)
  $list = @($Items)
  if ($list.Count -eq 0) { Write-Log "No drivers selected." 'WARN'; return }
  $total = $list.Count
  $i = 0
  $script:LastInstallPublishedNames = @()
  foreach ($item in $list) {
    $i++
    $pct = [math]::Round((($i)/$total)*100,2)
    Write-Log "Installing: $($item.FileName)"
    try {
      $pathToUse = $item.Path
      if (Test-IsNetworkPath $TxtFolder.Text) {
        $pathToUse = Get-CachedInfPath -InfPath $item.Path -SourceRoot $TxtFolder.Text
      }
  $pnputilCmd = "/add-driver `"$pathToUse`" /install"
      # Show movement while installing this driver
      $Prg.IsIndeterminate = $true
  $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)

      # Start process without waiting so UI remains responsive
  $proc = Start-Process -FilePath pnputil.exe -ArgumentList $pnputilCmd -WindowStyle Hidden -PassThru

      # Pump UI while waiting
      while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.Application]::DoEvents()
      }

      # Commit step progress
      $Prg.IsIndeterminate = $false
      $Prg.Value = $pct
  $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)

      if ($proc.ExitCode -eq 0) { Write-Log "Installed: $($item.FileName)" 'SUCCESS' }
      else { Write-Log "pnputil exit code $($proc.ExitCode) for $($item.FileName)" 'ERROR' }
    } catch {
      $Prg.IsIndeterminate = $false
      Write-Log "Install failed for $($item.FileName): $_" 'ERROR'
    }
  }
  Import-InstalledCache
  Invoke-Filter
  $Prg.Value = 0

  # Attempt to map the installed INFs to published names (oemXX.inf)
  try {
    $installedMap = @{}
    foreach ($d in $script:InstalledCacheAll) {
      if ($d.OriginalFileName -and $d.PublishedName) { $installedMap[$d.OriginalFileName.ToLower()] = $d.PublishedName }
    }
    foreach ($it in $list) {
      $pub = $installedMap[$it.FileName.ToLower()]
      if ($pub) { $script:LastInstallPublishedNames += $pub }
    }
    if ($script:LastInstallPublishedNames.Count -gt 0) {
      Write-Log "Rollback tracking captured: $($script:LastInstallPublishedNames -join ', ')" 'INFO'
    }
  } catch { Write-Log "Failed to capture rollback mapping: $_" 'WARN' }
}
#endregion

#region --- Removal / Rollback ---
function Confirm-DestructiveAction {
  param(
    [Parameter(Mandatory)] [string]$Prompt,
    [string]$Required = 'REMOVE'
  )
  $msg = $Prompt + "`n`nType '" + $Required + "' to confirm."
  $resp = [Microsoft.VisualBasic.Interaction]::InputBox($msg, 'Confirm removal', '')
  return ($resp -ceq $Required)
}

function Invoke-RemoveDriversByPublishedName {
  param([Parameter(Mandatory)] [string[]]$PublishedNames)
  if (-not $PublishedNames -or $PublishedNames.Count -eq 0) { Write-Log 'No drivers specified for removal.' 'WARN'; return }
  $total = [double]$PublishedNames.Count
  $i = 0
  $script:LastRemovalBackups = @()
  foreach ($pn in $PublishedNames) {
    $i++
    $pct = [math]::Round(($i/$total)*100,2)
    Write-Log "Preparing backup for: $pn"
    try {
      # Backup package first
      $backupDir = Backup-DriverPackage -PublishedName $pn
      if ($backupDir) { $script:LastRemovalBackups += $backupDir; Write-Log ("Backup complete: {0}" -f $backupDir) 'INFO' }

      # If manifest captured details, perform post-uninstall registry cleanup
      $manifest = $null
      try { if ($backupDir) { $manifest = Get-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Raw | ConvertFrom-Json } } catch {}

      Write-Log "Removing driver package: $pn"
      $Prg.IsIndeterminate = $true
  $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)
  $pnputilCmd = "/delete-driver $pn /uninstall /force"
  $proc = Start-Process -FilePath pnputil.exe -ArgumentList $pnputilCmd -WindowStyle Hidden -PassThru
      while (-not $proc.HasExited) { Start-Sleep -Milliseconds 150; [System.Windows.Forms.Application]::DoEvents() }
      $Prg.IsIndeterminate = $false
      $Prg.Value = $pct
  $null = $Prg.Dispatcher.Invoke([action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)
      if ($proc.ExitCode -eq 0) {
        Write-Log "Removed: $pn" 'SUCCESS'
        if ($manifest) { Cleanup-DriverRegistry -PublishedName $pn -ClassGuid $manifest.ClassGuid -ServiceNames $manifest.ServiceNames }
      } else {
        Write-Log "pnputil exit code $($proc.ExitCode) for delete $pn" 'ERROR'
      }
  } catch { $Prg.IsIndeterminate = $false; Write-Log ("Removal failed for {0}: {1}" -f $pn, $_) 'ERROR' }
  }
  Import-InstalledCache
  Invoke-Filter
  $Prg.Value = 0
}

function Invoke-RemoveSelectedInstalled {
  # From LvInstalled selection (objects with PublishedName)
  $sel = @($LvInstalled.SelectedItems)
  if ($sel.Count -eq 0) { Write-Log 'No installed drivers selected for removal.' 'WARN'; return }
  $pns = $sel | Where-Object { $_.PublishedName } | Select-Object -ExpandProperty PublishedName -Unique
  if ($pns.Count -eq 0) { Write-Log 'Selected items lack PublishedName; cannot remove.' 'ERROR'; return }
  if (-not (Confirm-DestructiveAction -Prompt ("You are about to remove {0} driver package(s):`n`n{1}" -f $pns.Count, ($pns -join "`n")) -Required 'REMOVE')) { Write-Log 'Removal canceled.' 'WARN'; return }
  Invoke-RemoveDriversByPublishedName -PublishedNames $pns
}

function Invoke-RollbackLastInstall {
  if (-not $script:LastInstallPublishedNames -or $script:LastInstallPublishedNames.Count -eq 0) { Write-Log 'No rollback info available for this session.' 'WARN'; return }
  $list = $script:LastInstallPublishedNames | Select-Object -Unique
  if (-not (Confirm-DestructiveAction -Prompt ("Rollback will remove the last installed package(s):`n`n{0}" -f ($list -join "`n")) -Required 'REMOVE')) { Write-Log 'Rollback canceled.' 'WARN'; return }
  Invoke-RemoveDriversByPublishedName -PublishedNames $list
}

function Invoke-RestoreLastRemoval {
  if (-not $script:LastRemovalBackups -or $script:LastRemovalBackups.Count -eq 0) { Write-Log 'No removal backups available to restore.' 'WARN'; return }
  $toRestore = $script:LastRemovalBackups | Where-Object { Test-Path -LiteralPath $_ }
  if ($toRestore.Count -eq 0) { Write-Log 'Backup directories are missing; cannot restore.' 'ERROR'; return }
  foreach ($dir in $toRestore) { Restore-DriverBackup -BackupDir $dir }
  Import-InstalledCache; Invoke-Filter
}
#endregion

#region --- Export Installed ---
function Invoke-ExportInstalledDrivers {
  try {
    $list = @($script:InstalledFiltered)
    if ($list.Count -eq 0) { $list = @($script:InstalledCacheAll) }
    if ($list.Count -eq 0) { Write-Log 'No installed drivers to export.' 'WARN'; return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = 'Export Installed Drivers'
    $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    $dlg.FileName = 'installed-drivers.csv'
    if (-not $dlg.ShowDialog()) { Write-Log 'Export canceled.' 'WARN'; return }

    $path = $dlg.FileName
    $export = $list | Select-Object OriginalFileName, PublishedName, ProviderName, ClassName, Version, Date
    $export | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Log "Exported installed drivers to: $path" 'SUCCESS'
  } catch { Write-Log ("Export failed: {0}" -f $_) 'ERROR' }
}
#endregion

#region --- Events ---
function Copy-ItemsAsCsv {
  param($items, [string[]]$columns)
  $lines = @()
  $lines += ($columns -join ',')
  foreach ($it in @($items)) {
    $cells = foreach ($c in $columns) {
      $v = '' + ($it.$c)
      '"' + ($v -replace '"','""') + '"'
    }
    $lines += ($cells -join ',')
  }
  [System.Windows.Clipboard]::SetText(($lines -join [Environment]::NewLine))
}

function Copy-RowTab {
  param($item, [string[]]$columns)
  if (-not $item) { return }
  $vals = $columns | ForEach-Object { '' + ($item.$_) }
  [System.Windows.Clipboard]::SetText(($vals -join "`t"))
}

function Copy-Field {
  param($item, [string]$field)
  if (-not $item) { return }
  [System.Windows.Clipboard]::SetText(('' + ($item.$field)))
}

function Open-InstalledInfLocation {
  param($item)
  try {
    $inf = if ($item.PublishedName) { '' + $item.PublishedName } elseif ($item.OriginalFileName) { '' + $item.OriginalFileName } else { '' }
    if (-not $inf) { Write-Log 'No INF name on selected item.' 'WARN'; return }
    $path = Join-Path $env:WINDIR (Join-Path 'INF' $inf)
    if (Test-Path -LiteralPath $path) {
      Start-Process explorer.exe "/select,`"$path`""
    } else {
      # Fall back to opening INF folder
      Start-Process explorer.exe (Join-Path $env:WINDIR 'INF')
    }
  } catch { Write-Log ("Open file location failed: {0}" -f $_) 'WARN' }
}

# Ensure right-click targets the row under the mouse for both lists
function Select-RowUnderMouse {
  param([System.Windows.Controls.ListView]$listView, [System.Object]$source, [System.Windows.Input.MouseButtonEventArgs]$e)
  try {
    $dep = [System.Windows.DependencyObject]$e.OriginalSource
    while ($dep -and -not ($dep -is [System.Windows.Controls.ListViewItem])) {
      $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($dep -is [System.Windows.Controls.ListViewItem]) {
      $dep.IsSelected = $true
      $dep.Focus() | Out-Null
    }
  } catch { }
}

# Recursively find a MenuItem by x:Name inside a ContextMenu or nested MenuItem
function Find-MenuItemByName {
  param([System.Windows.Controls.ItemsControl]$root, [string]$name)
  if (-not $root -or [string]::IsNullOrWhiteSpace($name)) { return $null }
  foreach ($it in $root.Items) {
    if ($it -is [System.Windows.Controls.MenuItem]) {
      if ($it.Name -eq $name) { return $it }
      $child = Find-MenuItemByName -root $it -name $name
      if ($child) { return $child }
    }
  }
  return $null
}
$BtnBrowse.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Select the root folder containing driver .INF files'
  if ($dlg.ShowDialog() -eq 'OK') { $TxtFolder.Text = $dlg.SelectedPath }
})

$BtnScan.Add_Click({
  try {
    if ($script:ScanInProgress -and -not $script:ScanCancel) {
      $script:ScanCancel = $true
      Write-Log 'User requested scan cancellation.' 'INFO'
      if ($LblStatus) { $LblStatus.Text = 'Canceling scan…' }
      return
    }
    if (-not $script:ScanInProgress) { Scan-Folder $TxtFolder.Text }
  } catch { Write-Log $_ 'ERROR' }
})
$BtnRefresh.Add_Click({ Import-InstalledCache; Invoke-Filter })
$BtnApplyFilter.Add_Click({ Invoke-Filter })
$BtnClearFilter.Add_Click({ $TxtSearch.Text=''; Invoke-Filter })
$TxtSearch.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Return') { Invoke-Filter } })
$ChkShowTwins.Add_Checked({ Invoke-Filter })
$ChkShowTwins.Add_Unchecked({ Invoke-Filter })

# Only buttons
$BtnOnlyWebcams.Add_Click(  { $script:CurrentCategory = 'Webcams';   Invoke-Filter })
$BtnOnlyAudio.Add_Click(    { $script:CurrentCategory = 'Audio';     Invoke-Filter })
$BtnOnlyBluetooth.Add_Click({ $script:CurrentCategory = 'Bluetooth'; Invoke-Filter })
$BtnOnlyNetwork.Add_Click(  { $script:CurrentCategory = 'Network';   Invoke-Filter })
$BtnOnlyStorage.Add_Click(  { $script:CurrentCategory = 'Storage';   Invoke-Filter })
$BtnOnlyChipset.Add_Click(  { $script:CurrentCategory = 'Chipset';   Invoke-Filter })
$BtnShowAll.Add_Click(      { $script:CurrentCategory = $null;       Invoke-Filter })

$BtnInstallSelected.Add_Click({ Invoke-InstallDrivers $LvAvailable.SelectedItems })
$BtnInstallAll.Add_Click({ Invoke-InstallDrivers $LvAvailable.Items })
$BtnRemoveSelected.Add_Click({ Invoke-RemoveSelectedInstalled })
$BtnRollback.Add_Click({ Invoke-RollbackLastInstall })
$BtnRestoreRemoval.Add_Click({ Invoke-RestoreLastRemoval })
$BtnExportInstalled.Add_Click({ Invoke-ExportInstalledDrivers })

# Cleanup button wiring
try {
  $BtnCleanup = $Window.FindName('BtnCleanup')
  if ($BtnCleanup) {
    $BtnCleanup.Add_Click({
      Clear-DriverSweepData
      # Reset in-memory state and UI
      $script:InstalledCacheAll = @()
      $script:InstalledFiltered = @()
      $script:FolderInventoryAll = @()
      $script:AvailableFiltered  = @()
      $LvAvailable.ItemsSource = @()
      $LvInstalled.ItemsSource = @()
      if ($LblStatus) { $LblStatus.Text = 'Cleaned local data. Ready.' }
    })
  }
} catch {}

# Context menu wiring for Available
$ctxAvail = ($LvAvailable.ContextMenu)
if ($ctxAvail) {
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyRowAvailable';                if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-RowTab $LvAvailable.SelectedItem @('FileName','DriverVer','Provider','Class','Path') } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopySelectedAvailableCsv';        if ($mi) { $mi.Add_Click({ $sel=@($LvAvailable.SelectedItems); if ($sel.Count -gt 0) { Copy-ItemsAsCsv $sel @('FileName','DriverVer','Provider','Class','Path') } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyAvail_FileName';              if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-Field $LvAvailable.SelectedItem 'FileName' } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyAvail_DriverVer';             if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-Field $LvAvailable.SelectedItem 'DriverVer' } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyAvail_Provider';              if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-Field $LvAvailable.SelectedItem 'Provider' } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyAvail_Class';                 if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-Field $LvAvailable.SelectedItem 'Class' } }) }
  $mi = Find-MenuItemByName -root $ctxAvail -name 'CopyAvail_Path';                  if ($mi) { $mi.Add_Click({ if ($LvAvailable.SelectedItem) { Copy-Field $LvAvailable.SelectedItem 'Path' } }) }
  $LvAvailable.Add_PreviewMouseRightButtonDown({ param($s,$e) Select-RowUnderMouse -listView $LvAvailable -source $s -e $e })
}

# Context menu wiring for Installed
$ctxInst = ($LvInstalled.ContextMenu)
if ($ctxInst) {
  # Use unified property set for parity with Available (FileName, DriverVer, Provider, Class, Path); legacy menu item names map to new fields.
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyRowInstalled';                 if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-RowTab $LvInstalled.SelectedItem @('FileName','DriverVer','Provider','Class','Path') } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopySelectedInstalledCsv';         if ($mi) { $mi.Add_Click({ $sel=@($LvInstalled.SelectedItems); if ($sel.Count -gt 0) { Copy-ItemsAsCsv $sel @('FileName','DriverVer','Provider','Class','Path') } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyInst_OriginalFileName';        if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-Field $LvInstalled.SelectedItem 'FileName' } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyInst_Version';                 if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-Field $LvInstalled.SelectedItem 'DriverVer' } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyInst_ProviderName';            if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-Field $LvInstalled.SelectedItem 'Provider' } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyInst_ClassName';               if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-Field $LvInstalled.SelectedItem 'Class' } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'CopyInst_PublishedName';           if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Copy-Field $LvInstalled.SelectedItem 'PublishedName' } }) }
  $mi = Find-MenuItemByName -root $ctxInst -name 'OpenInstalledInf';                 if ($mi) { $mi.Add_Click({ if ($LvInstalled.SelectedItem) { Open-InstalledInfLocation $LvInstalled.SelectedItem } }) }
  $LvInstalled.Add_PreviewMouseRightButtonDown({ param($s,$e) Select-RowUnderMouse -listView $LvInstalled -source $s -e $e })
}
#endregion

#region --- Cleanup Utilities ---
function Clear-DriverSweepData {
  param([switch]$Silent)
  try {
    if (-not $Silent) {
      $msg = "This will delete:\n- Cache: $script:CacheRoot\n- Backups: $script:BackupRoot\n- Log: $global:LogPath\n\nProceed?"
      $res = [System.Windows.MessageBox]::Show($msg, 'Cleanup confirmation', 'YesNo', 'Warning')
      if ($res -ne 'Yes') { return }
    }

    $targets = @()
    if (Test-Path -LiteralPath $script:CacheRoot) { $targets += $script:CacheRoot }
    if (Test-Path -LiteralPath $script:BackupRoot) { $targets += $script:BackupRoot }
    if (Test-Path -LiteralPath $global:LogPath) { $targets += $global:LogPath }

    $count = $targets.Count
    if ($count -eq 0) { if ($LblStatus) { $LblStatus.Text = 'Nothing to clean.' }; return }

    if ($Prg) { $Prg.IsIndeterminate = $false; $Prg.Minimum = 0; $Prg.Maximum = $count; $Prg.Value = 0 }
    if ($LblStatus) { $LblStatus.Text = 'Cleaning up…' }
    $i = 0
    foreach ($t in $targets) {
      $i++
      try {
        if ($LblStatus) { $LblStatus.Text = "Deleting ($i/$count): $t" }
        $null = $Prg.Dispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()

        if (Test-Path -LiteralPath $t) {
          $attr = (Get-Item -LiteralPath $t -Force).Attributes
          if ($attr -band [IO.FileAttributes]::ReadOnly) {
            try { (Get-Item -LiteralPath $t -Force).Attributes = 'Normal' } catch {}
          }
          if (Test-Path -LiteralPath $t -PathType Container) {
            Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop
          } else {
            Remove-Item -LiteralPath $t -Force -ErrorAction Stop
          }
          Write-Log ("Deleted: {0}" -f $t) 'INFO'
        }
      } catch {
        Write-Log ("Failed to delete {0}: {1}" -f $t, $_) 'WARN'
      } finally {
        if ($Prg) { $Prg.Value = [math]::Min($i, $Prg.Maximum) }
      }
    }

    # Recreate roots
    try { New-Item -ItemType Directory -Path $script:CacheRoot -Force | Out-Null } catch {}
    try { New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null } catch {}

    if ($LblStatus) { $LblStatus.Text = 'Cleanup complete.' }
  } catch {
    Write-Log ("Cleanup error: {0}" -f $_) 'ERROR'
    if ($LblStatus) { $LblStatus.Text = 'Cleanup failed. See log.' }
  }
}
#endregion --- Cleanup Utilities ---

#region --- Bootstrap ---
Write-Log 'Driver Sweep Installer started.'
$defaultPath = 'C:\'
if (Test-Path $defaultPath) { $TxtFolder.Text = $defaultPath }
function Start-LoadInstalledAsync {
  if ($script:SimpleMode) {
    try {
      if ($StartupOverlay) { $StartupOverlay.Visibility = 'Visible' }
      if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Scanning installed drivers…' }
      if ($PrgStartup) { $PrgStartup.IsIndeterminate = $true; $PrgStartup.Value = 0 }
      if ($Prg) { $Prg.IsIndeterminate = $true; $Prg.Value = 0 }
      $script:StartupCancel = $false
  function _SafeProp([object]$o,[string]$n){ if(-not $o){return $null}; try { if($o -is [hashtable]){ if($o.ContainsKey($n)){ return $o[$n] } else { return $null } }; $p=$o.PSObject.Properties[$n]; if($p){ return $p.Value }; return $null } catch { return $null } }
      if ($BtnStartupCancel) {
        $BtnStartupCancel.IsEnabled = $true
        $BtnStartupCancel.Add_Click({ $script:StartupCancel = $true; if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Canceling…' } }) | Out-Null
      }

      # Background job to gather raw data (DISM if available else pnputil output lines)
      $job = Start-Job -ScriptBlock {
        $out = [ordered]@{ Mode=''; Data=$null }
        $dism = Get-Command -Name Get-WindowsDriver -ErrorAction SilentlyContinue
        if ($dism) {
          try {
            $drivers = Get-WindowsDriver -Online -All
            if ($drivers) {
              $out.Mode = 'DISM'
              $out.Data = @($drivers)
              return [pscustomobject]$out
            }
          } catch {}
        }
        $out.Mode = 'PNPUTIL'
        $out.Data = & pnputil /enum-drivers 2>&1
        return [pscustomobject]$out
      }

      # Simple spinner + pulse while job runs
  $spin = @('|','/','-','\\')
      $si = 0; $pulse = 0
      while ($job.State -eq 'Running' -and -not $script:StartupCancel) {
        Start-Sleep -Milliseconds 180
        $si = ($si + 1) % $spin.Count
        $pulse = ($pulse + 7) % 100
        if ($Prg) { $Prg.IsIndeterminate = $false; $Prg.Minimum=0; $Prg.Maximum=100; $Prg.Value = $pulse }
        if ($TxtStartupStatus) { $TxtStartupStatus.Text = "Gathering raw driver list $($spin[$si])" }
        [System.Windows.Forms.Application]::DoEvents()
      }
      if ($script:StartupCancel) { try { Stop-Job $job -Force -ErrorAction SilentlyContinue } catch {}; try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}; $script:InstalledCacheAll=@(); Invoke-Filter; return }
      $raw = Receive-Job -Job $job -ErrorAction SilentlyContinue
      try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}

      $results = @()
      if ($raw) {
        if ($raw.Mode -eq 'DISM') {
          $drivers = @($raw.Data)
          $total = $drivers.Count
          if ($PrgStartup -and $total -gt 0) { $PrgStartup.IsIndeterminate=$false; $PrgStartup.Minimum=0; $PrgStartup.Maximum=$total; $PrgStartup.Value=0 }
          if ($Prg -and $total -gt 0) { $Prg.IsIndeterminate=$false; $Prg.Minimum=0; $Prg.Maximum=$total; $Prg.Value=0 }
          $i=0
          foreach ($d in $drivers) {
            if ($script:StartupCancel) { break }
            $i++
            try {
              $orig = _SafeProp $d 'OriginalFileName'; if (-not $orig) { $orig = _SafeProp $d 'OriginalName' }
              $pub  = _SafeProp $d 'PublishedName'; if (-not $pub) { $pub = _SafeProp $d 'Driver' }
              if (-not $orig -and $pub -and ($pub -match '\.inf$')) { $orig = $pub }
              $prov = _SafeProp $d 'ProviderName'
              $cls  = _SafeProp $d 'ClassName'
              $date = _SafeProp $d 'Date'
              $ver  = _SafeProp $d 'Version'
              $pathInf = $null
              try {
                if ($pub) { $pathInf = Join-Path $env:WINDIR (Join-Path 'INF' $pub) }
                elseif ($orig) { $pathInf = Join-Path $env:WINDIR (Join-Path 'INF' $orig) }
              } catch {}
              $results += [pscustomobject]@{
                OriginalFileName = $orig
                ProviderName     = $prov
                ClassName        = $cls
                Date             = $date
                Version          = $ver
                PublishedName    = $pub
                Path             = $pathInf
                FileName         = $orig
                Provider         = $prov
                Class            = $cls
                DriverVer        = $ver
              }
            } catch { Write-Log ("DISM enumeration row skipped: " + $_) 'WARN' }
            if ($PrgStartup) { $PrgStartup.Value = $i }
            if ($Prg) { $Prg.Value = $i }
            if ($TxtStartupStatus) { $TxtStartupStatus.Text = "Loaded $i/$total drivers…" }
            if (($i % 25) -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
          }
        } else {
          $lines = @($raw.Data)
          # pre-count blocks for determinate progress
          $totalBlocks=0; $blockHas=$false
          foreach ($ln in $lines) { if ($ln -match '^(Published Name|Original Name|Provider Name|Class Name|Driver Version)\s*:') { $blockHas=$true; continue } if ($ln -match '^\s*$') { if ($blockHas){$totalBlocks++;$blockHas=$false} } }
          if ($blockHas) { $totalBlocks++ }
          if ($PrgStartup -and $totalBlocks -gt 0) { $PrgStartup.IsIndeterminate=$false; $PrgStartup.Minimum=0; $PrgStartup.Maximum=$totalBlocks; $PrgStartup.Value=0 }
          if ($Prg -and $totalBlocks -gt 0) { $Prg.IsIndeterminate=$false; $Prg.Minimum=0; $Prg.Maximum=$totalBlocks; $Prg.Value=0 }
          $block=@{}; $i=0
          foreach ($ln in $lines) {
            if ($script:StartupCancel) { break }
            if ($ln -match 'Published Name\s*:\s*(?<p>oem\d+\.inf)') { $block.PublishedName=$Matches.p; continue }
            if ($ln -match 'Original Name\s*:\s*(?<o>.+\.inf)') { $block.OriginalFileName=$Matches.o; continue }
            if ($ln -match 'Provider Name\s*:\s*(?<pr>.+)') { $block.ProviderName=$Matches.pr; continue }
            if ($ln -match 'Class Name\s*:\s*(?<c>.+)') { $block.ClassName=$Matches.c; continue }
            if ($ln -match 'Driver Version\s*:\s*(?<v>\S+\s+\S+)') { $block.Version=$Matches.v; continue }
            if ($ln -match '^\s*$') {
              $orig=$block['OriginalFileName']; $pub=$block['PublishedName']; $prov=$block['ProviderName']; $cls=$block['ClassName']; $ver=$block['Version']
              if ($orig -or $pub -or $prov -or $cls -or $ver) {
                $pathInf = $null
                try {
                  if ($pub) { $pathInf = Join-Path $env:WINDIR (Join-Path 'INF' $pub) }
                  elseif ($orig) { $pathInf = Join-Path $env:WINDIR (Join-Path 'INF' $orig) }
                } catch {}
                $results += [pscustomobject]@{
                  OriginalFileName = $orig
                  ProviderName     = $prov
                  ClassName        = $cls
                  Date             = $null
                  Version          = $ver
                  PublishedName    = $pub
                  Path             = $pathInf
                  FileName         = $orig
                  Provider         = $prov
                  Class            = $cls
                  DriverVer        = $ver
                }
                $i++
                if ($PrgStartup) { $PrgStartup.Value=[math]::Min($i,$PrgStartup.Maximum) }
                if ($Prg) { $Prg.Value=[math]::Min($i,$Prg.Maximum) }
                if ($TxtStartupStatus -and $totalBlocks -gt 0) { $TxtStartupStatus.Text = "Parsed $i/$totalBlocks blocks…" }
              }
              $block=@{}
              if (($i % 25) -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
            }
          }
        }
      }

      $script:InstalledCacheAll = @($results | Where-Object { $_ })
      Write-Log ("Startup (SimpleMode) enumeration complete. InstalledCacheAll count={0}" -f ($script:InstalledCacheAll.Count)) 'INFO'
      Invoke-Filter
      $script:InitialLoadComplete = $true
      if ($LblStatus) { $LblStatus.Text = "Installed loaded: $($script:InstalledCacheAll.Count) drivers" }
    } catch {
      Write-Log ("SimpleMode startup enumeration error: " + $_) 'ERROR'
    } finally {
      try {
        if ($StartupOverlay) { $StartupOverlay.Visibility = 'Collapsed' }
        if ($PrgStartup) { $PrgStartup.IsIndeterminate = $false; $PrgStartup.Value = 0 }
        if ($Prg) { $Prg.IsIndeterminate = $false; $Prg.Value = 0 }
      } catch {}
    }
    return
  }
  try {
    if ($StartupOverlay) { $StartupOverlay.Visibility = 'Visible' }
    if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Loading installed drivers…' }
    if ($PrgStartup) { $PrgStartup.IsIndeterminate = $true; $PrgStartup.Value = 0 }
  $script:StartupCancel = $false
  if ($BtnStartupCancel) { $BtnStartupCancel.IsEnabled = $true; $BtnStartupCancel.Add_Click({ $script:StartupCancel = $true; if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Canceling…' } }) }

    # Ensure overlay paints before heavy work
    try { $null = $Window.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Render) } catch {}

    # Phase 1: gather raw data in background (keeps UI responsive)
    if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Scanning installed drivers…' }
    $job = Start-Job -ScriptBlock {
      $result = [ordered]@{ Mode=''; Data=$null }
      $dism = Get-Command -Name Get-WindowsDriver -ErrorAction SilentlyContinue
      if ($dism) {
        try {
          $drivers = Get-WindowsDriver -Online -All
          $result.Mode = 'DISM'
          $lite = @()
          foreach ($d in $drivers) {
            $lite += [pscustomobject]@{
              OriginalFileName = if ($d.OriginalFileName) { $d.OriginalFileName } elseif ($d.OriginalName) { $d.OriginalName } else { $null }
              ProviderName     = $d.ProviderName
              ClassName        = $d.ClassName
              Date             = $d.Date
              Version          = $d.Version
              PublishedName    = if ($d.PublishedName) { $d.PublishedName } elseif ($d.Driver) { $d.Driver } else { $null }
            }
          }
          $result.Data = $lite
          return [pscustomobject]$result
        } catch {}
      }
      # Fallback: return pnputil output lines to parse on UI thread
      $result.Mode = 'PNPUTIL'
      $result.Data = & pnputil /enum-drivers 2>&1
      return [pscustomobject]$result
    }

    while ($job.State -eq 'Running' -and -not $script:StartupCancel) {
      Start-Sleep -Milliseconds 120
      [System.Windows.Forms.Application]::DoEvents()
    }
    if ($script:StartupCancel) { try { Stop-Job $job -Force -ErrorAction SilentlyContinue } catch {}; try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}; $script:InstalledCacheAll = @(); Invoke-Filter; return }
    $raw = Receive-Job -Job $job -ErrorAction SilentlyContinue
    try { Remove-Job $job -Force -ErrorAction SilentlyContinue } catch {}

    $results = @()
    if ($raw -and -not $script:StartupCancel) {
      if ($raw.Mode -eq 'DISM') {
        $drivers = @($raw.Data)
        $total = $drivers.Count
        if ($total -gt 0 -and $PrgStartup) { $PrgStartup.IsIndeterminate = $false; $PrgStartup.Minimum=0; $PrgStartup.Maximum=$total; $PrgStartup.Value=0 }
        $i=0
        foreach ($d in $drivers) {
          if ($script:StartupCancel) { break }
          $i++
          $orig = $d.OriginalFileName; $prov=$d.ProviderName; $cls=$d.ClassName; $date=$d.Date; $ver=$d.Version; $pub=$d.PublishedName
          if (-not $orig -and $pub -and ($pub -match '\.inf$')) { $orig = $pub }
          $results += [pscustomobject]@{ OriginalFileName=$orig; ProviderName=$prov; ClassName=$cls; Date=$date; Version=$ver; PublishedName=$pub }
          if ($PrgStartup) { $PrgStartup.Value = $i }
          if ($TxtStartupStatus -and $total -gt 0) { $TxtStartupStatus.Text = "Loading installed drivers… ($i/$total)" }
          [System.Windows.Forms.Application]::DoEvents()
        }
      } else {
        $lines = @($raw.Data)
        if ($TxtStartupStatus) { $TxtStartupStatus.Text = 'Enumerating installed drivers (pnputil)…' }
        [System.Windows.Forms.Application]::DoEvents()
        $totalBlocks = 0; $blockHasData = $false
        foreach ($line in $lines) {
          if ($line -match '^(Published Name|Original Name|Provider Name|Class Name|Driver Version)\s*:') { $blockHasData = $true; continue }
          if ($line -match '^\s*$') { if ($blockHasData) { $totalBlocks++; $blockHasData = $false } }
        }
        if ($blockHasData) { $totalBlocks++ }
        if ($PrgStartup) { $PrgStartup.IsIndeterminate = $false; $PrgStartup.Minimum=0; $PrgStartup.Maximum=[math]::Max(1,$totalBlocks); $PrgStartup.Value=0 }
        $i=0; $block=@{}
        foreach ($line in $lines) {
          if ($script:StartupCancel) { break }
          if ($line -match 'Published Name\s*:\s*(?<p>oem\d+\.inf)') { $block.PublishedName = $Matches.p; continue }
          if ($line -match 'Original Name\s*:\s*(?<o>.+\.inf)')      { $block.OriginalFileName = $Matches.o; continue }
          if ($line -match 'Provider Name\s*:\s*(?<pr>.+)')            { $block.ProviderName = $Matches.pr; continue }
          if ($line -match 'Class Name\s*:\s*(?<c>.+)')                { $block.ClassName = $Matches.c; continue }
          if ($line -match 'Driver Version\s*:\s*(?<v>\S+\s+\S+)')   { $block.Version = $Matches.v; continue }
          if ($line -match '^\s*$') {
            $orig = $block['OriginalFileName']; $pub=$block['PublishedName']; $prov=$block['ProviderName']; $cls=$block['ClassName']; $ver=$block['Version']
            if ($orig -or $pub -or $prov -or $cls -or $ver) {
              $results += [pscustomobject]@{ OriginalFileName=$orig; ProviderName=$prov; ClassName=$cls; Date=$null; Version=$ver; PublishedName=$pub }
              $i++
              if ($PrgStartup) { $PrgStartup.Value = [math]::Min($i, $PrgStartup.Maximum) }
              if ($TxtStartupStatus -and $totalBlocks -gt 0) { $TxtStartupStatus.Text = "Loading installed drivers… ($i/$totalBlocks)" }
              [System.Windows.Forms.Application]::DoEvents()
            }
            $block=@{}
          }
        }
        if ($block.Count -gt 0 -and -not $script:StartupCancel) {
          $orig = $block['OriginalFileName']; $pub=$block['PublishedName']; $prov=$block['ProviderName']; $cls=$block['ClassName']; $ver=$block['Version']
          if ($orig -or $pub -or $prov -or $cls -or $ver) {
            $results += [pscustomobject]@{ OriginalFileName=$orig; ProviderName=$prov; ClassName=$cls; Date=$null; Version=$ver; PublishedName=$pub }
            $i++
            if ($PrgStartup) { $PrgStartup.Value = [math]::Min($i, $PrgStartup.Maximum) }
            if ($TxtStartupStatus -and $totalBlocks -gt 0) { $TxtStartupStatus.Text = "Loading installed drivers… ($i/$totalBlocks)" }
          }
        }
      }
    }

    if ($script:StartupCancel) { Write-Log 'Startup load canceled by user.' 'WARN' }
  $script:InstalledCacheAll = if ($script:StartupCancel) { @() } else { $results }
  Write-Log ("Startup enumeration complete. InstalledCacheAll count={0}" -f $script:InstalledCacheAll.Count) 'INFO'
  Invoke-Filter
  $script:InitialLoadComplete = $true
  Write-Log 'Initial load marked complete.' 'DEBUG'
  } finally {
    if ($StartupOverlay) { $StartupOverlay.Visibility = 'Collapsed' }
  }
}

$Window.Add_Loaded({
  try {
    $null = $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [System.Action]{ Start-LoadInstalledAsync })
  } catch {
    # Fallback to direct call if BeginInvoke fails
    Start-LoadInstalledAsync
  }
})

$null = $Window.ShowDialog()
Write-Log 'Driver Sweep Installer closed.'
#endregion
