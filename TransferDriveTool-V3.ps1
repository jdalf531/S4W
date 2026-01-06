$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MPN DTA Tool"
        Height="1050"
        Width="900"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        Background="#1E1E1E"
        Foreground="#E0E0E0"
        FontSize="16"
        FontFamily="Segoe UI">

<Window.Resources>

    <!-- GLOBAL TEXTBOX STYLE -->
    <Style TargetType="TextBox">
        <Setter Property="Foreground" Value="#FFFFFF"/>
        <Setter Property="Background" Value="#000000"/> <!-- pure black -->
        <Setter Property="BorderBrush" Value="#005A9E"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="6"/>
        <Setter Property="Margin" Value="5"/>
    </Style>

    <!-- GLOBAL LABEL STYLE -->
    <Style TargetType="Label">
        <Setter Property="Foreground" Value="#FFFFFF"/>
        <Setter Property="Margin" Value="5"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

</Window.Resources>


    <Grid Margin="15">

        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- BRANDING HEADER -->
        <Border Grid.Row="0" Background="#003366" Padding="15" CornerRadius="6">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="MPN DTA TOOL"
                           FontSize="28"
                           FontWeight="Bold"
                           Foreground="#FF3A3A"
                           Margin="0,0,10,0"/>
                <TextBlock Text="(Don't Copy That Floppy)"
                           FontSize="20"
                           Foreground="#FFFFFF"
                           VerticalAlignment="Bottom"/>
            </StackPanel>
        </Border>

        <!-- TAB CONTROL -->
        <TabControl x:Name="tabMain"
                    Grid.Row="2"
                    Background="#1E1E1E"
                    BorderBrush="#005A9E"
                    BorderThickness="2"
                    Margin="0,10,0,10"
                    Foreground="#FFFFFF"
                    FontSize="16">
                <!-- ========================= -->
                <!-- TAB 1 — Commercial → Drive -->
                <!-- ========================= -->
                <TabItem Header="To Drive (Commercial → Drive)">
                    <Grid Margin="10">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="120"/>
                        </Grid.ColumnDefinitions>

                        <Grid.Resources>

                            <!-- TEXTBOX STYLE -->
                            <Style TargetType="TextBox">
                                <Setter Property="Background" Value="#2D2D30"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#005A9E"/>
                                <Setter Property="BorderThickness" Value="1"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>
                            </Style>

                            <!-- COMBOBOX STYLE (FULL DARK THEME FIX) -->
                            <Style TargetType="ComboBox">
                                <Setter Property="Background" Value="#2D2D30"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#005A9E"/>
                                <Setter Property="BorderThickness" Value="1"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>

                                <!-- Dropdown items -->
                                <Setter Property="ItemContainerStyle">
                                    <Setter.Value>
                                        <Style TargetType="ComboBoxItem">
                                            <Setter Property="Background" Value="#2D2D30"/>
                                            <Setter Property="Foreground" Value="#FFFFFF"/>
                                            <Setter Property="Padding" Value="4"/>
                                            <Setter Property="Margin" Value="2"/>
                                            <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                            <Setter Property="VerticalContentAlignment" Value="Center"/>
                                        </Style>
                                    </Setter.Value>
                                </Setter>

                                <!-- Selected item -->
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="ComboBox">
                                            <Grid>
                                                <ToggleButton Name="ToggleButton"
              Background="#2D2D30"
              Foreground="#FFFFFF"
              BorderBrush="#005A9E"
              BorderThickness="1"
              Focusable="False"
              HorizontalContentAlignment="Left"
              IsChecked="{Binding Path=IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}"
              ClickMode="Press">

<Grid>
    <!-- Dropdown arrow on the LEFT -->
    <Path Data="M 0 0 L 4 4 L 8 0 Z"
          Fill="#FFFFFF"
          HorizontalAlignment="Left"
          VerticalAlignment="Center"
          Margin="8,0,0,0"/>

    <!-- Selected text shifted right -->
    <ContentPresenter Margin="24,0,4,0"
                      HorizontalAlignment="Left"
                      VerticalAlignment="Center"/>
</Grid>



                                                </ToggleButton>

                                                <Popup Name="Popup"
                                                       Placement="Bottom"
                                                       IsOpen="{TemplateBinding IsDropDownOpen}"
                                                       AllowsTransparency="True"
                                                       Focusable="False">
                                                    <Border Background="#2D2D30"
                                                            BorderBrush="#005A9E"
                                                            BorderThickness="1">
                                                        <ScrollViewer>
                                                            <ItemsPresenter/>
                                                        </ScrollViewer>
                                                    </Border>
                                                </Popup>
                                            </Grid>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>

                            <!-- BUTTON STYLE -->
                            <Style TargetType="Button">
                                <Setter Property="Background" Value="#003366"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#FF3A3A"/>
                                <Setter Property="BorderThickness" Value="2"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>
                                <Setter Property="FontWeight" Value="Bold"/>
                                <Setter Property="Cursor" Value="Hand"/>
                            </Style>

                            <!-- LABEL STYLE -->
                            <Style TargetType="Label">
                                <Setter Property="Foreground" Value="#E0E0E0"/>
                                <Setter Property="VerticalAlignment" Value="Center"/>
                                <Setter Property="Margin" Value="5"/>
                            </Style>

                        </Grid.Resources>

                        <Label Grid.Row="0" Grid.Column="0" Content="User:"/>
                        <ComboBox x:Name="cbUser_Commercial" Grid.Row="0" Grid.Column="1"/>

                        <Label Grid.Row="1" Grid.Column="0" Content="Source (Commercial):"/>
                        <TextBox x:Name="txtSource_Commercial" Grid.Row="1" Grid.Column="1"/>
                        <Button x:Name="btnBrowseSource_Commercial"
                                Grid.Row="1" Grid.Column="2"
                                Content="Browse"/>

                        <Label Grid.Row="2" Grid.Column="0" Content="Destination (Drive):"/>
                        <TextBox x:Name="txtDest_Commercial" Grid.Row="2" Grid.Column="1"/>
                        <Button x:Name="btnBrowseDest_Commercial"
                                Grid.Row="2" Grid.Column="2"
                                Content="Browse"/>

                    </Grid>
                </TabItem>
                <!-- ========================= -->
                <!-- TAB 2 — Drive → MPN -->
                <!-- ========================= -->
                <TabItem Header="From Drive (Drive → MPN)">
                    <Grid Margin="10">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="120"/>
                        </Grid.ColumnDefinitions>

                        <Grid.Resources>

                            <!-- TEXTBOX STYLE -->
                            <Style TargetType="TextBox">
                                <Setter Property="Background" Value="#2D2D30"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#005A9E"/>
                                <Setter Property="BorderThickness" Value="1"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>
                            </Style>

                            <!-- COMBOBOX STYLE (FULL DARK THEME FIX) -->
                            <Style TargetType="ComboBox">
                                <Setter Property="Background" Value="#2D2D30"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#005A9E"/>
                                <Setter Property="BorderThickness" Value="1"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>

                                <!-- Dropdown items -->
                                <Setter Property="ItemContainerStyle">
                                    <Setter.Value>
                                        <Style TargetType="ComboBoxItem">
                                            <Setter Property="Background" Value="#2D2D30"/>
                                            <Setter Property="Foreground" Value="#FFFFFF"/>
                                            <Setter Property="Padding" Value="4"/>
                                            <Setter Property="Margin" Value="2"/>
                                            <Setter Property="HorizontalContentAlignment" Value="Left"/>
                                            <Setter Property="VerticalContentAlignment" Value="Center"/>
                                        </Style>
                                    </Setter.Value>
                                </Setter>

                                <!-- Selected item -->
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="ComboBox">
                                            <Grid>
                                                <ToggleButton Name="ToggleButton"
              Background="#2D2D30"
              Foreground="#FFFFFF"
              BorderBrush="#005A9E"
              BorderThickness="1"
              Focusable="False"
              HorizontalContentAlignment="Left"
              IsChecked="{Binding Path=IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}"
              ClickMode="Press">

<Grid>
    <!-- Dropdown arrow on the LEFT -->
    <Path Data="M 0 0 L 4 4 L 8 0 Z"
          Fill="#FFFFFF"
          HorizontalAlignment="Left"
          VerticalAlignment="Center"
          Margin="8,0,0,0"/>

    <!-- Selected text shifted right -->
    <ContentPresenter Margin="24,0,4,0"
                      HorizontalAlignment="Left"
                      VerticalAlignment="Center"/>
</Grid>


                                                </ToggleButton>

                                                <Popup Name="Popup"
                                                       Placement="Bottom"
                                                       IsOpen="{TemplateBinding IsDropDownOpen}"
                                                       AllowsTransparency="True"
                                                       Focusable="False">
                                                    <Border Background="#2D2D30"
                                                            BorderBrush="#005A9E"
                                                            BorderThickness="1">
                                                        <ScrollViewer>
                                                            <ItemsPresenter/>
                                                        </ScrollViewer>
                                                    </Border>
                                                </Popup>
                                            </Grid>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>

                            <!-- BUTTON STYLE -->
                            <Style TargetType="Button">
                                <Setter Property="Background" Value="#003366"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter Property="BorderBrush" Value="#FF3A3A"/>
                                <Setter Property="BorderThickness" Value="2"/>
                                <Setter Property="Padding" Value="6"/>
                                <Setter Property="Margin" Value="5"/>
                                <Setter Property="FontWeight" Value="Bold"/>
                                <Setter Property="Cursor" Value="Hand"/>
                            </Style>

                            <!-- LABEL STYLE -->
                            <Style TargetType="Label">
                                <Setter Property="Foreground" Value="#E0E0E0"/>
                                <Setter Property="VerticalAlignment" Value="Center"/>
                                <Setter Property="Margin" Value="5"/>
                            </Style>

                        </Grid.Resources>

                        <Label Grid.Row="0" Grid.Column="0" Content="User:"/>
                        <ComboBox x:Name="cbUser_MPN" Grid.Row="0" Grid.Column="1"/>

                        <Label Grid.Row="1" Grid.Column="0" Content="Source (Drive):"/>
                        <TextBox x:Name="txtSource_MPN" Grid.Row="1" Grid.Column="1"/>
                        <Button x:Name="btnBrowseSource_MPN"
                                Grid.Row="1" Grid.Column="2"
                                Content="Browse"/>

                        <Label Grid.Row="2" Grid.Column="0" Content="Destination (MPN):"/>
                        <TextBox x:Name="txtDest_MPN" Grid.Row="2" Grid.Column="1"/>
                        <Button x:Name="btnBrowseDest_MPN"
                                Grid.Row="2" Grid.Column="2"
                                Content="Browse"/>

                    </Grid>
                </TabItem>
                </TabControl>


            <!-- PROGRESS + STATUS PANEL -->
            <StackPanel Grid.Row="3" Margin="5">

                <!-- Progress Header -->
                <StackPanel Orientation="Vertical" Margin="0,0,0,10">
                    <TextBlock Text="Transfer Progress"
                               FontSize="18"
                               FontWeight="Bold"
                               Foreground="#FF3A3A"
                               Margin="0,0,0,5"/>

                    <!-- Progress Bar -->
                    <ProgressBar x:Name="pbProgress"
                                 Height="20"
                                 Minimum="0"
                                 Maximum="100"
                                 Value="0"
                                 Background="#2D2D30"
                                 Foreground="#3FA9F5"/>

                    <!-- Progress Summary -->
                    <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                        <TextBlock x:Name="lblProgressSummary"
                                   Text="Files: 0 / 0 | Copied: 0 | Skipped: 0"
                                   Foreground="#E0E0E0"
                                   Margin="0,0,20,0"/>

                        <TextBlock x:Name="lblCurrentFile"
                                   Text="Current: (none)"
                                   Foreground="#E0E0E0"/>
                    </StackPanel>
                </StackPanel>

                <!-- STATUS LOG TEXTBOX -->
                <TextBox x:Name="txtStatus"
                         Height="150"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         Background="#252526"
                         Foreground="#E0E0E0"
                         BorderBrush="#005A9E"
                         BorderThickness="1"/>
            </StackPanel>
            <!-- GLOBAL METADATA SECTION -->
            <Border Grid.Row="4"
                    Background="#2D2D30"
                    Padding="10"
                    CornerRadius="6"
                    Margin="0,10,0,10"
                    BorderBrush="#005A9E"
                    BorderThickness="2">
                <StackPanel>

                    <TextBlock Text="DTA Logging Info"
                               FontSize="20"
                               FontWeight="Bold"
                               Foreground="#FF3A3A"
                               Margin="0,0,0,10"/>

                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Label Grid.Row="0" Grid.Column="0" Content="Authorizing Manager:"/>
                        <TextBox x:Name="txtManager"
                                 Grid.Row="0" Grid.Column="1"
                                 Text="Kevin Rockel"/>

                        <Label Grid.Row="1" Grid.Column="0" Content="Source System:"/>
                        <TextBox x:Name="txtSourceSystem"
                                 Grid.Row="1" Grid.Column="1"
                                 Text="Commercial"/>

                        <Label Grid.Row="2" Grid.Column="0" Content="Destination System:"/>
                        <TextBox x:Name="txtDestSystem"
                                 Grid.Row="2" Grid.Column="1"
                                 Text="MPN DTA Station"/>

                        <Label Grid.Row="3" Grid.Column="0" Content="File Classification:"/>
                        <TextBox x:Name="txtClassification"
                                 Grid.Row="3" Grid.Column="1"
                                 Text="Unclassified"/>

                        <Label Grid.Row="4" Grid.Column="0" Content="Media Used:"/>
                        <TextBox x:Name="txtMediaUsed"
                                 Grid.Row="4" Grid.Column="1"
                                 Text="Aegis Fortress L3 - 121400002465"/>

                        <Label Grid.Row="5" Grid.Column="0" Content="Justification:"/>
                        <TextBox x:Name="txtJustification"
                                 Grid.Row="5" Grid.Column="1"
                                 Text="NA"/>

                        <Label Grid.Row="6" Grid.Column="0" Content="Scan/Review Verification:"/>
                        <TextBox x:Name="txtScanVerify"
                                 Grid.Row="6" Grid.Column="1"
                                 Text="Justin M Dobson"/>

                    </Grid>
                </StackPanel>
            </Border>
            <!-- BUTTONS -->
            <StackPanel Grid.Row="5"
                        Orientation="Horizontal"
                        HorizontalAlignment="Right">
                <Button x:Name="btnRun" Content="Run" Width="120" Margin="5"/>
                <Button x:Name="btnClose" Content="Close" Width="120" Margin="5"/>
            </StackPanel>

        </Grid>
</Window>
"@
# ============================
# PRESET TABLES
# ============================

# TAB 1 — Commercial → Drive
$Presets_Commercial = @{
    Ben   = @{ Source="C:\Viper\DTA\Ben";   Dest="E:\DTA\Ben" }
    Corey = @{ Source="C:\Viper\DTA\Corey"; Dest="E:\DTA\Corey" }
    Daily = @{ Source="C:\Viper\DTA\Daily"; Dest="E:\DTA\Daily" }
    Eddy  = @{ Source="C:\Viper\DTA\Eddy";  Dest="E:\DTA\Eddy" }
    Jawid = @{ Source="C:\Viper\DTA\Jawid"; Dest="E:\DTA\Jawid" }
    Josh  = @{ Source="C:\Viper\DTA\Josh";  Dest="E:\DTA\Josh" }
    Julia = @{ Source="C:\Viper\DTA\Julia"; Dest="E:\DTA\Julia" }
    Justin= @{ Source="C:\Viper\DTA\Justin";Dest="E:\DTA\Justin" }
    Kevin = @{ Source="C:\Viper\DTA\Kevin"; Dest="E:\DTA\Kevin" }
    Kris  = @{ Source="C:\Viper\DTA\Kris";  Dest="E:\DTA\Kris" }
    Miles = @{ Source="C:\Viper\DTA\Miles"; Dest="E:\DTA\Miles" }
    Mike  = @{ Source="C:\Viper\DTA\Mike";  Dest="E:\DTA\Mike" }
    Tamir = @{ Source="C:\Viper\DTA\Tamir"; Dest="E:\DTA\Tamir" }

}

# TAB 2 — Drive → MPN
$Presets_MPN = @{
    Ben   = @{ Source="E:\DTA\Ben";   Dest="\\X.X.X.X\admin\systems\DTA\Ben" }
    Corey = @{ Source="E:\DTA\Corey"; Dest="\\X.X.X.X\admin\systems\DTA\Corey" }
    Daily = @{ Source="E:\DTA\Daily"; Dest="\\X.X.X.X\admin\systems\DTA\Daily" }
    Eddy  = @{ Source="E:\DTA\Eddy";  Dest="\\X.X.X.X\admin\systems\DTA\Eddy" }
    Jawid = @{ Source="E:\DTA\Jawid"; Dest="\\X.X.X.X\admin\systems\DTA\Jawid" }
    Josh  = @{ Source="E:\DTA\Josh";  Dest="\\X.X.X.X\admin\systems\DTA\Josh" }
    Julia = @{ Source="E:\DTA\Julia"; Dest="\\X.X.X.X\admin\systems\DTA\Julia" }
    Justin= @{ Source="E:\DTA\Justin";Dest="\\X.X.X.X\admin\systems\DTA\Justin" }
    Kevin = @{ Source="E:\DTA\Kevin"; Dest="\\X.X.X.X\admin\systems\DTA\Kevin" }
    Kris  = @{ Source="E:\DTA\Kris";  Dest="\\X.X.X.X\admin\systems\DTA\Kris" }
    Miles = @{ Source="E:\DTA\Miles"; Dest="\\X.X.X.X\admin\systems\DTA\Miles" }
    Mike  = @{ Source="E:\DTA\Mike";  Dest="\\X.X.X.X\admin\systems\DTA\Mike" }
    Tamir = @{ Source="E:\DTA\Tamir"; Dest="\\X.X.X.X\admin\systems\DTA\Tamir" }

}

# ============================
# ENSURE FOLDER STRUCTURE EXISTS
# ============================
foreach ($preset in $Presets_Commercial.Values) {
    if (-not (Test-Path $preset.Source)) { New-Item -ItemType Directory -Path $preset.Source -Force | Out-Null }
    if (-not (Test-Path $preset.Dest))   { New-Item -ItemType Directory -Path $preset.Dest   -Force | Out-Null }
}
foreach ($preset in $Presets_MPN.Values) {
    if (-not (Test-Path $preset.Source)) { New-Item -ItemType Directory -Path $preset.Source -Force | Out-Null }
    if (-not (Test-Path $preset.Dest))   { New-Item -ItemType Directory -Path $preset.Dest   -Force | Out-Null }
}

# ============================
# LOAD XAML
# ============================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Force UI to fully render before binding
$Window.Dispatcher.Invoke([action]{}, "Render")

# ============================
# UI CONTROL BINDINGS
# ============================

# Tabs
$tabMain = $Window.FindName("tabMain")

# Tab 1 controls
$cbUser_Commercial        = $Window.FindName("cbUser_Commercial")
$txtSource_Commercial     = $Window.FindName("txtSource_Commercial")
$txtDest_Commercial       = $Window.FindName("txtDest_Commercial")
$btnBrowseSource_Commercial = $Window.FindName("btnBrowseSource_Commercial")
$btnBrowseDest_Commercial   = $Window.FindName("btnBrowseDest_Commercial")

# Tab 2 controls
$cbUser_MPN               = $Window.FindName("cbUser_MPN")
$txtSource_MPN            = $Window.FindName("txtSource_MPN")
$txtDest_MPN              = $Window.FindName("txtDest_MPN")
$btnBrowseSource_MPN      = $Window.FindName("btnBrowseSource_MPN")
$btnBrowseDest_MPN        = $Window.FindName("btnBrowseDest_MPN")

# Global metadata
$txtManager        = $Window.FindName("txtManager")
$txtSourceSystem   = $Window.FindName("txtSourceSystem")
$txtDestSystem     = $Window.FindName("txtDestSystem")
$txtClassification = $Window.FindName("txtClassification")
$txtMediaUsed      = $Window.FindName("txtMediaUsed")
$txtJustification  = $Window.FindName("txtJustification")
$txtScanVerify     = $Window.FindName("txtScanVerify")

# Status + buttons
$txtStatus = $Window.FindName("txtStatus")
$btnRun    = $Window.FindName("btnRun")
$btnClose  = $Window.FindName("btnClose")

# Progress controls
$pbProgress         = $Window.FindName("pbProgress")
$lblProgressSummary = $Window.FindName("lblProgressSummary")
$lblCurrentFile     = $Window.FindName("lblCurrentFile")
# ============================
# POPULATE USER DROPDOWNS
# ============================

# Tab 1 users
if ($cbUser_Commercial -ne $null) {
    $cbUser_Commercial.ItemsSource = $Presets_Commercial.Keys
} else {
    Write-Status "ERROR: cbUser_Commercial not found in XAML"
}

# Tab 2 users
if ($cbUser_MPN -ne $null) {
    $cbUser_MPN.ItemsSource = $Presets_MPN.Keys
} else {
    Write-Status "ERROR: cbUser_MPN not found in XAML"
}

# ============================
# USER SELECTION HANDLERS
# ============================

# Tab 1 — Commercial → Drive
$cbUser_Commercial.Add_SelectionChanged({
    $user = $cbUser_Commercial.SelectedItem
    if ($user -and $Presets_Commercial.ContainsKey($user)) {
        $txtSource_Commercial.Text = $Presets_Commercial[$user].Source
        $txtDest_Commercial.Text   = $Presets_Commercial[$user].Dest
        Write-Status "Loaded preset for $user"
    }
})

# Tab 2 — Drive → MPN
$cbUser_MPN.Add_SelectionChanged({
    $user = $cbUser_MPN.SelectedItem
    if ($user -and $Presets_MPN.ContainsKey($user)) {
        $txtSource_MPN.Text = $Presets_MPN[$user].Source
        $txtDest_MPN.Text   = $Presets_MPN[$user].Dest
        Write-Status "Loaded preset for $user"
    }
})


# ============================
# STATUS LOGGING
# ============================
$LogRoot = "C:\VIPER\DTA"
if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile = Join-Path $LogRoot ("TransferLog_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

function Write-Status {
    param([string]$msg)

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $msg"

    $txtStatus.AppendText("$line`r`n")
    $txtStatus.ScrollToEnd()

    Add-Content -Path $LogFile -Value $line
}

# ============================
# CSV LOGGING
# ============================
#$CsvLogPath = "C:\VIPER\DTA\DataTransferLog.csv"

#function Initialize-CsvLog {
#    if (-not (Test-Path $CsvLogPath)) {
#        $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
#        Set-Content -Path $CsvLogPath -Value $headers
#    }
#}
#Initialize-CsvLog

function Add-CsvLogEntry {
    param(
        [string]$DTAName,
        [string]$Manager,
        [string]$SourceSystem,
        [string]$DestSystem,
        [string]$FileName,
        [string]$Classification,
        [string]$FileSize,
        [string]$Checksum,
        [string]$MediaUsed,
        [string]$Justification,
        [string]$ScanVerify
    )

    $lineCount = (Measure-Object -Line -Path $CsvLogPath).Lines
    $seq = "{0:D3}" -f ($lineCount)
    $year = (Get-Date).Year
    $logNumber = "$year-$seq"
    $utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm'Z'")

    $fields = @(
        $logNumber, $DTAName, $Manager, $utc, $SourceSystem, $DestSystem,
        $FileName, $Classification, $FileSize, $Checksum,
        $MediaUsed, $Justification, $ScanVerify
    ) | ForEach-Object { '"' + ($_ -replace '"','""') + '"' }

    Add-Content -Path $CsvLogPath -Value ($fields -join ",")
}

# ============================
# HASHING
# ============================
function Get-FileHashSHA256 {
    param([string]$filePath)
    (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
}

# ============================
# TRANSFER STATE / PROGRESS
# ============================
$script:TotalFiles   = 0
$script:FilesCopied  = 0
$script:FilesSkipped = 0
$script:StartTime    = $null

function Update-ProgressUI {
    if ($script:TotalFiles -gt 0) {
        $percent = [math]::Round(
            ($script:FilesCopied + $script:FilesSkipped) / $script:TotalFiles * 100, 0
        )
    } else {
        $percent = 0
    }

    $pbProgress.Value = $percent

    $lblProgressSummary.Text =
        "Files: $($script:FilesCopied + $script:FilesSkipped) / $($script:TotalFiles) | Copied: $($script:FilesCopied) | Skipped: $($script:FilesSkipped)"
}

function Set-CurrentFileLabel {
    param([string]$relativePath)
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $lblCurrentFile.Text = "Current: (none)"
    } else {
        $lblCurrentFile.Text = "Current: $relativePath"
    }
}

# ============================
# RETRY LOGIC FOR COPY
# ============================
function Copy-WithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$MaxRetries = 3
    )

    # Verify source exists before attempting copy
    if (-not (Test-Path $Source)) {
        Write-Status "✗ Source file not found: $Source"
        return $false
    }

    # Backup destination if it exists
    $destExists = Test-Path $Destination
    $backupPath = $null
    if ($destExists) {
        $backupPath = "$Destination.backup"
        if (Test-Path $backupPath) {
            Remove-Item $backupPath -Force | Out-Null
        }
        Copy-Item -Path $Destination -Destination $backupPath -Force | Out-Null
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            Copy-Item -Path $Source -Destination $Destination -Force
            
            # Clean up backup if copy succeeded
            if ($backupPath -and (Test-Path $backupPath)) {
                Remove-Item $backupPath -Force | Out-Null
            }
            
            return $true
        }
        catch {
            $attempt++
            Write-Status "Error copying '$Source' (attempt $attempt of $MaxRetries): $($_.Exception.Message)"
            
            # Restore backup on final failure
            if ($attempt -eq $MaxRetries -and $backupPath -and (Test-Path $backupPath)) {
                Copy-Item -Path $backupPath -Destination $Destination -Force | Out-Null
                Write-Status "Restored backup for: $Destination"
                Remove-Item $backupPath -Force | Out-Null
            }
            
            Start-Sleep -Seconds 1
        }
    }

    return $false
}
# ============================
# INCREMENTAL COPY ENGINE (UPGRADED)
# ============================
function Copy-Files {

    # Determine active tab
    $activeTab = $tabMain.SelectedIndex

    # ============================
# SELECT CSV LOG LOCATION BASED ON TAB
# ============================
if ($activeTab -eq 0) {
    # Tab 1 — Commercial → Drive
    $CsvLogPath = "E:\DTA\Logging\DataTransferLog.csv"
}
else {
    # Tab 2 — Drive → MPN
    $CsvLogPath = "C:\VIPER\DTA\DataTransferLog.csv"
}

# Ensure CSV exists
if (-not (Test-Path $CsvLogPath)) {
    $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
    Set-Content -Path $CsvLogPath -Value $headers
}


    if ($activeTab -eq 0) {
        # TAB 1 — Commercial → Drive
        $src = $txtSource_Commercial.Text.Trim()
        $dstRoot = $txtDest_Commercial.Text.Trim()
        $user = $cbUser_Commercial.SelectedItem
    }
    elseif ($activeTab -eq 1) {
        # TAB 2 — Drive → MPN
        $src = $txtSource_MPN.Text.Trim()
        $dstRoot = $txtDest_MPN.Text.Trim()
        $user = $cbUser_MPN.SelectedItem
    }
    else {
        Write-Status "Unknown tab selected."
        return
    }

    if (-not $user) {
        Write-Status "No user selected."
        return
    }

    if (-not (Test-Path $src)) {
        Write-Status "Source path does not exist: $src"
        return
    }

    if ([string]::IsNullOrWhiteSpace($dstRoot)) {
        Write-Status "Destination path is empty."
        return
    }

    # Create dated folder
    $dateFolder = (Get-Date -Format "yyyyMMdd")
    $dst = Join-Path $dstRoot $dateFolder

    if (-not (Test-Path $dst)) {
        Write-Status "Creating destination folder: $dst"
        try {
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
        }
        catch {
            Write-Status "Failed to create destination: $($_.Exception.Message)"
            return
        }
    }

    Write-Status "Scanning source files for changes..."

    $files = Get-ChildItem -Path $src -Recurse -File
    $script:TotalFiles   = $files.Count
    $script:FilesCopied  = 0
    $script:FilesSkipped = 0
    $script:StartTime    = Get-Date

    # Reset UI
    $pbProgress.Value = 0
    Update-ProgressUI
    Set-CurrentFileLabel ""

    foreach ($file in $files) {

        $relativePath = $file.FullName.Substring($src.Length).TrimStart("\","/")
        Set-CurrentFileLabel $relativePath

        $destFile = Join-Path $dst $relativePath
        $destDir = Split-Path $destFile -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        $shouldCopy = $true

        # Check if destination file already exists
        if (Test-Path $destFile) {
            $destInfo = Get-Item $destFile
            $sourceSize = $file.Length
            $destSize = $destInfo.Length
            
            # Skip if destination is newer or same timestamp
            if ($destInfo.LastWriteTimeUtc -ge $file.LastWriteTimeUtc) {
                Write-Status "⊘ File exists (destination newer/same): $relativePath [Source: $($file.LastWriteTimeUtc), Dest: $($destInfo.LastWriteTimeUtc)]"
                $script:FilesSkipped++
                Update-ProgressUI
                continue
            }
            
            # Warn if file exists but is older (will be overwritten)
            if ($sourceSize -ne $destSize) {
                Write-Status "⚠ File exists with different size (will overwrite): $relativePath [Source: {0:N0} bytes, Dest: {1:N0} bytes]" -f $sourceSize, $destSize
            }
            else {
                Write-Status "⚠ File exists with same size (checking hash): $relativePath"
            }
        }

        # Copy with retry
        $copied = Copy-WithRetry -Source $file.FullName -Destination $destFile -MaxRetries 3
        if (-not $copied) {
            Write-Status "Failed to copy after retries: $relativePath"
            $script:FilesSkipped++
            Update-ProgressUI
            continue
        }

        Write-Status "Copied: $relativePath"

        try {
            # Hash verification
            $sourceHash = Get-FileHashSHA256 $file.FullName
            $destHash   = Get-FileHashSHA256 $destFile

            if ($sourceHash -ne $destHash) {
                Write-Status "HASH MISMATCH: $relativePath"
            }
            else {
                Write-Status "Hash verified: $relativePath"
            }

            # File size
            $size = "{0:N0} KB" -f ($file.Length / 1KB)

            # CSV log entry
            Add-CsvLogEntry `
                -DTAName        $user `
                -Manager        $txtManager.Text `
                -SourceSystem   $txtSourceSystem.Text `
                -DestSystem     $txtDestSystem.Text `
                -FileName       $relativePath `
                -Classification $txtClassification.Text `
                -FileSize       $size `
                -Checksum       $destHash `
                -MediaUsed      $txtMediaUsed.Text `
                -Justification  $txtJustification.Text `
                -ScanVerify     $txtScanVerify.Text

            Write-Status "Logged: $relativePath"
            $script:FilesCopied++
        }
        catch {
            Write-Status "Failed to hash/log $relativePath : $($_.Exception.Message)"
            $script:FilesSkipped++
        }

        Update-ProgressUI
    }

    # Summary
    $elapsed = (Get-Date) - $script:StartTime
    Write-Status "Transfer complete."
    Write-Status "Summary: Total=$($script:TotalFiles), Copied=$($script:FilesCopied), Skipped=$($script:FilesSkipped), Elapsed=$($elapsed.ToString())"

    Set-CurrentFileLabel ""
}
# ============================
# BUTTON HANDLERS
# ============================

$btnRun.Add_Click({
    Write-Status "Starting transfer..."
    Copy-Files
})

$btnClose.Add_Click({
    Write-Status "Closing tool..."
    $Window.Close()
})

# ============================
# SHOW WINDOW
# ============================
$Window.ShowDialog() | Out-Null
