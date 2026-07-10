# ============================
# HIDE CONSOLE WINDOW
# ============================
# This is a GUI (WPF) tool; hide the powershell.exe console it launched in.
# No-op if there's no console to hide (e.g. run from the ISE/VS Code terminal).
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$ConsoleWindowHandle = [Console.Window]::GetConsoleWindow()
if ($ConsoleWindowHandle -ne [IntPtr]::Zero) {
    [Console.Window]::ShowWindow($ConsoleWindowHandle, 0) | Out-Null  # 0 = SW_HIDE
}

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
                <TabItem x:Name="tabCommercial" Header="To Drive (Commercial → Drive)">
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
                <TabItem x:Name="tabMPN" Header="From Drive (Drive → MPN)">
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

                    <!-- Current File Byte Progress -->
                    <ProgressBar x:Name="pbCurrentFile"
                                 Height="14"
                                 Minimum="0"
                                 Maximum="100"
                                 Value="0"
                                 Margin="0,5,0,0"
                                 Background="#2D2D30"
                                 Foreground="#3FA9F5"/>

                    <TextBlock x:Name="lblCurrentFileProgress"
                               Text=""
                               Foreground="#E0E0E0"
                               Margin="0,3,0,0"/>
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
# DOMAIN DETECTION
# ============================
# Commercial (non-domain-joined) boxes only need Commercial -> Drive.
# EUR* domain boxes only need Drive -> MPN (that portion's network share is
# only reachable there). Skipping the inapplicable portion avoids the
# "network path was not found" spam from probing shares that can't be reached.
$ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$IsDomainJoined = $ComputerSystem.PartOfDomain
$DomainName     = $ComputerSystem.Domain

if (-not $IsDomainJoined) {
    $ToolMode = "Commercial"
}
elseif ($DomainName -like "EUR*") {
    $ToolMode = "MPN"
}
else {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "This machine's domain ('$DomainName') is not recognized by the MPN DTA Tool.`n`nExpected either a non-domain-joined (commercial) machine or a domain starting with 'EUR'. Contact IT before running this tool.",
        "MPN DTA Tool - Unsupported Domain",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

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
if ($ToolMode -eq "Commercial") {
    foreach ($preset in $Presets_Commercial.Values) {
        if (-not (Test-Path $preset.Source)) { New-Item -ItemType Directory -Path $preset.Source -Force | Out-Null }
        if (-not (Test-Path $preset.Dest))   { New-Item -ItemType Directory -Path $preset.Dest   -Force | Out-Null }
    }
}
elseif ($ToolMode -eq "MPN") {
    foreach ($preset in $Presets_MPN.Values) {
        if (-not (Test-Path $preset.Source)) { New-Item -ItemType Directory -Path $preset.Source -Force | Out-Null }
        if (-not (Test-Path $preset.Dest))   { New-Item -ItemType Directory -Path $preset.Dest   -Force | Out-Null }
    }
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
$tabMain       = $Window.FindName("tabMain")
$tabCommercial = $Window.FindName("tabCommercial")
$tabMPN        = $Window.FindName("tabMPN")

# Hide whichever portion doesn't apply on this machine (see DOMAIN DETECTION)
if ($ToolMode -eq "Commercial") {
    $tabMPN.Visibility = "Collapsed"
    $tabCommercial.IsSelected = $true
}
elseif ($ToolMode -eq "MPN") {
    $tabCommercial.Visibility = "Collapsed"
    $tabMPN.IsSelected = $true
}

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
$pbProgress             = $Window.FindName("pbProgress")
$lblProgressSummary     = $Window.FindName("lblProgressSummary")
$lblCurrentFile         = $Window.FindName("lblCurrentFile")
$pbCurrentFile          = $Window.FindName("pbCurrentFile")
$lblCurrentFileProgress = $Window.FindName("lblCurrentFileProgress")
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
# AUTO-ARCHIVE OLD DATA (Commercial mode only)
# ============================
# Runs once at launch. Keeps both the flat Viper source and the dated drive
# folders from growing forever, and keeps the MPN-side scan (which skips each
# Archive folder, see the source-file scan above) from re-pushing old data.

# Drive side: E:\DTA\<user>\yyyyMMdd folders older than 1 week -> E:\DTA\<user>\Archive\yyyyMMdd
function Invoke-DriveArchiveSweep {
    Write-Status "Archive sweep: scanning drive folders for dated folders older than 1 week..."
    $cutoff = (Get-Date).Date.AddDays(-7)
    $archivedCount = 0

    foreach ($presetUser in $Presets_Commercial.Keys) {
        $userDest = $Presets_Commercial[$presetUser].Dest
        if (-not (Test-Path $userDest)) { continue }

        $archiveRoot = Join-Path $userDest "Archive"

        $dateFolders = Get-ChildItem -Path $userDest -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "Archive" -and $_.Name -match '^\d{8}$' }

        foreach ($folder in $dateFolders) {
            $folderDate = [datetime]::MinValue
            $parsed = [datetime]::TryParseExact(
                $folder.Name, "yyyyMMdd",
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$folderDate)

            if ($parsed -and $folderDate -lt $cutoff) {
                if (-not (Test-Path $archiveRoot)) {
                    New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
                }

                $archiveDest = Join-Path $archiveRoot $folder.Name
                if (Test-Path $archiveDest) {
                    Write-Status "Archive sweep: skipped drive\$presetUser\$($folder.Name) (already archived)"
                    continue
                }

                try {
                    Move-Item -Path $folder.FullName -Destination $archiveDest -Force
                    Write-Status "Archive sweep: archived drive\$presetUser\$($folder.Name)"
                    $archivedCount++
                }
                catch {
                    Write-Status "Archive sweep: failed to archive drive\$presetUser\$($folder.Name): $($_.Exception.Message)"
                }
            }
        }
    }

    Write-Status "Drive archive sweep complete. $archivedCount folder(s) archived."
}

# Source side: C:\Viper\DTA\<user> is flat (no date-named folders), so age is
# judged per top-level item by LastWriteTime instead of by name.
function Invoke-SourceArchiveSweep {
    Write-Status "Archive sweep: scanning source folders for items older than 1 week..."
    $cutoff = (Get-Date).AddDays(-7)
    $archivedCount = 0

    foreach ($presetUser in $Presets_Commercial.Keys) {
        $userSource = $Presets_Commercial[$presetUser].Source
        if (-not (Test-Path $userSource)) { continue }

        $archiveRoot = Join-Path $userSource "Archive"

        # Use whichever of CreationTime/LastWriteTime is newer: Copy-Item preserves
        # the source file's original modified date (so a file authored weeks ago
        # but copied in just now would look immediately archivable by CreationTime
        # alone), while a file edited in place after landing here would look
        # immediately archivable by LastWriteTime alone. Only archive once both
        # are stale.
        $items = Get-ChildItem -Path $userSource -ErrorAction SilentlyContinue |
            Where-Object {
                $mostRecent = if ($_.CreationTime -gt $_.LastWriteTime) { $_.CreationTime } else { $_.LastWriteTime }
                $_.Name -ne "Archive" -and $mostRecent -lt $cutoff
            }

        foreach ($item in $items) {
            if (-not (Test-Path $archiveRoot)) {
                New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
            }

            $archiveDest = Join-Path $archiveRoot $item.Name
            if (Test-Path $archiveDest) {
                Write-Status "Archive sweep: skipped source\$presetUser\$($item.Name) (already archived)"
                continue
            }

            try {
                Move-Item -Path $item.FullName -Destination $archiveDest -Force
                Write-Status "Archive sweep: archived source\$presetUser\$($item.Name)"
                $archivedCount++
            }
            catch {
                Write-Status "Archive sweep: failed to archive source\$presetUser\$($item.Name): $($_.Exception.Message)"
            }
        }
    }

    Write-Status "Source archive sweep complete. $archivedCount item(s) archived."
}

if ($ToolMode -eq "Commercial") {
    Invoke-DriveArchiveSweep
    Invoke-SourceArchiveSweep
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

    $lineCount = (Get-Content -Path $CsvLogPath | Measure-Object -Line).Lines
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
# RESUMABLE COPY ENGINE
# ============================
# Copies Source -> Destination in chunks via a "<Destination>.partial" file,
# hashing the source incrementally as it reads (no separate full hash pass on
# the happy path). Only renames .partial onto Destination once a post-copy
# hash check passes, so Destination is never touched mid-copy. A sidecar
# "<Destination>.partial.meta" records the source's Length/LastWriteTimeUtc
# so an interrupted copy can resume later -- even after a full app restart --
# as long as the source hasn't changed; otherwise it restarts from byte 0.
function Copy-FileResumable {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [int]$ChunkSizeBytes = 4MB,
        [scriptblock]$ProgressCallback = $null,
        [int[]]$RetryDelaySeconds = @(2,5,15,30,60),
        [int]$MaxAttempts = 15
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return [PSCustomObject]@{ Success = $false; SourceHash = $null; DestHash = $null; Error = "Source file not found: $Source" }
    }

    $sourceInfo = Get-Item -LiteralPath $Source
    $sourceLength = $sourceInfo.Length
    $sourceWriteTicks = $sourceInfo.LastWriteTimeUtc.Ticks

    $partialPath = "$Destination.partial"
    $metaPath = "$Destination.partial.meta"

    function Get-ResumeOffset {
        if (-not (Test-Path -LiteralPath $partialPath)) { return 0L }
        if (-not (Test-Path -LiteralPath $metaPath)) {
            Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
            return 0L
        }
        $metaLines = @(Get-Content -LiteralPath $metaPath -ErrorAction SilentlyContinue)
        if ($metaLines.Count -lt 2 -or $metaLines[0] -ne "$sourceLength" -or $metaLines[1] -ne "$sourceWriteTicks") {
            Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
            return 0L
        }
        return (Get-Item -LiteralPath $partialPath).Length
    }

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $resumeOffset = Get-ResumeOffset

        if ($resumeOffset -eq 0L -and -not (Test-Path -LiteralPath $metaPath)) {
            Set-Content -LiteralPath $metaPath -Value @("$sourceLength", "$sourceWriteTicks")
        }

        $sourceStream = $null
        $partialStream = $null
        $hasher = [System.Security.Cryptography.SHA256]::Create()

        try {
            $sourceStream = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $partialStream = [System.IO.File]::Open($partialPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

            $buffer = New-Object byte[] $ChunkSizeBytes

            # Resuming: re-hash the already-copied prefix by re-reading it from
            # the source (ground truth), so the final hash is still correct
            # for the whole file even though we didn't keep hash state across
            # attempts/restarts.
            $hashed = 0L
            while ($hashed -lt $resumeOffset) {
                $toRead = [Math]::Min($ChunkSizeBytes, $resumeOffset - $hashed)
                $read = $sourceStream.Read($buffer, 0, $toRead)
                if ($read -le 0) { break }
                $hasher.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
                $hashed += $read
            }

            $partialStream.Seek($resumeOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $partialStream.SetLength($resumeOffset)

            $bytesDone = $resumeOffset
            $lastReport = Get-Date

            while ($true) {
                $read = $sourceStream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }

                $hasher.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
                $partialStream.Write($buffer, 0, $read)
                $bytesDone += $read

                if ($ProgressCallback -and ((Get-Date) - $lastReport).TotalMilliseconds -ge 250) {
                    & $ProgressCallback $bytesDone $sourceLength
                    $lastReport = Get-Date
                }
            }

            $hasher.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
            $sourceHash = ([BitConverter]::ToString($hasher.Hash) -replace '-', '')

            if ($ProgressCallback) { & $ProgressCallback $bytesDone $sourceLength }

            $partialStream.Close(); $partialStream = $null
            $sourceStream.Close(); $sourceStream = $null

            $destHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash

            if ($sourceHash -ne $destHash) {
                Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
                $lastError = "Hash mismatch after copy (source $sourceHash, dest $destHash)"
            }
            else {
                Move-Item -LiteralPath $partialPath -Destination $Destination -Force
                Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
                return [PSCustomObject]@{ Success = $true; SourceHash = $sourceHash; DestHash = $destHash; Error = $null }
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        finally {
            if ($partialStream) { $partialStream.Dispose() }
            if ($sourceStream) { $sourceStream.Dispose() }
            $hasher.Dispose()
        }

        if ($attempt -lt $MaxAttempts) {
            $delayIndex = [Math]::Min($attempt - 1, $RetryDelaySeconds.Count - 1)
            Start-Sleep -Seconds $RetryDelaySeconds[$delayIndex]
        }
    }

    return [PSCustomObject]@{ Success = $false; SourceHash = $null; DestHash = $null; Error = $lastError }
}

# ============================
# INCREMENTAL COPY ENGINE (ASYNC)
# ============================
function Copy-Files {

    $activeTab = $tabMain.SelectedIndex

    if ($activeTab -eq 0) {
        $CsvLogPath = "E:\DTA\Logging\DataTransferLog.csv"
    }
    else {
        $CsvLogPath = "C:\VIPER\DTA\DataTransferLog.csv"
    }

    if (-not (Test-Path $CsvLogPath)) {
        $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
        Set-Content -Path $CsvLogPath -Value $headers
    }

    if ($activeTab -eq 0) {
        $src = $txtSource_Commercial.Text.Trim()
        $dstRoot = $txtDest_Commercial.Text.Trim()
        $user = $cbUser_Commercial.SelectedItem
    }
    elseif ($activeTab -eq 1) {
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

    $archivePrefix = (Join-Path $src "Archive") + [System.IO.Path]::DirectorySeparatorChar
    $files = Get-ChildItem -Path $src -Recurse -File |
        Where-Object { -not $_.FullName.StartsWith($archivePrefix, [System.StringComparison]::OrdinalIgnoreCase) }

    if ($files.Count -eq 0) {
        Write-Status "No files found to transfer."
        return
    }

    # Snapshot everything the background runspace needs from UI controls now --
    # it's not safe to read WPF control properties from another thread.
    $snapshot = [PSCustomObject]@{
        DtaName        = $user
        Manager        = $txtManager.Text
        SourceSystem   = $txtSourceSystem.Text
        DestSystem     = $txtDestSystem.Text
        Classification = $txtClassification.Text
        MediaUsed      = $txtMediaUsed.Text
        Justification  = $txtJustification.Text
        ScanVerify     = $txtScanVerify.Text
    }

    $pbProgress.Value = 0
    $pbCurrentFile.Value = 0
    $lblProgressSummary.Text = "Files: 0 / $($files.Count) | Copied: 0 | Skipped: 0"
    $lblCurrentFile.Text = "Current: (none)"
    $lblCurrentFileProgress.Text = ""
    $btnRun.IsEnabled = $false
    $btnClose.IsEnabled = $false

    try {
    $copyFileResumableBody = (Get-Item Function:\Copy-FileResumable).ScriptBlock.ToString()
    $addCsvLogEntryBody    = (Get-Item Function:\Add-CsvLogEntry).ScriptBlock.ToString()

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Copy-FileResumable", $copyFileResumableBody)))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Add-CsvLogEntry", $addCsvLogEntryBody)))

    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    $runspace.SessionStateProxy.SetVariable("Dispatcher", $Window.Dispatcher)
    $runspace.SessionStateProxy.SetVariable("pbProgress", $pbProgress)
    $runspace.SessionStateProxy.SetVariable("lblProgressSummary", $lblProgressSummary)
    $runspace.SessionStateProxy.SetVariable("lblCurrentFile", $lblCurrentFile)
    $runspace.SessionStateProxy.SetVariable("pbCurrentFile", $pbCurrentFile)
    $runspace.SessionStateProxy.SetVariable("lblCurrentFileProgress", $lblCurrentFileProgress)
    $runspace.SessionStateProxy.SetVariable("txtStatus", $txtStatus)
    $runspace.SessionStateProxy.SetVariable("LogFile", $LogFile)
    $runspace.SessionStateProxy.SetVariable("CsvLogPath", $CsvLogPath)
    $runspace.SessionStateProxy.SetVariable("Files", $files)
    $runspace.SessionStateProxy.SetVariable("SrcRoot", $src)
    $runspace.SessionStateProxy.SetVariable("DstRoot", $dst)
    $runspace.SessionStateProxy.SetVariable("DstUserRoot", $dstRoot)
    $runspace.SessionStateProxy.SetVariable("Snapshot", $snapshot)

    $batchScript = {
        $totalFiles   = $Files.Count
        $filesCopied  = 0
        $filesSkipped = 0
        $startTime    = Get-Date

        function Write-BackgroundStatus {
            param([string]$msg)
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $line = "[$timestamp] $msg"
            Add-Content -Path $LogFile -Value $line
            $Dispatcher.Invoke([action]{
                $txtStatus.AppendText("$line`r`n")
                $txtStatus.ScrollToEnd()
            }, "Normal")
        }

        function Update-BackgroundProgress {
            $percent = [math]::Round((($filesCopied + $filesSkipped) / $totalFiles) * 100, 0)
            $Dispatcher.Invoke([action]{
                $pbProgress.Value = $percent
                $lblProgressSummary.Text = "Files: $($filesCopied + $filesSkipped) / $totalFiles | Copied: $filesCopied | Skipped: $filesSkipped"
            }, "Normal")
        }

        # Look back up to 7 days for an orphaned .partial from an interrupted transfer
        # that crossed a midnight boundary before today's dated folder existed. Keyed
        # by relative path so the per-file loop below is an O(1) hashtable lookup,
        # not a repeated network Test-Path per file.
        $orphanedPartials = @{}
        for ($daysAgo = 1; $daysAgo -le 7; $daysAgo++) {
            $candidateDateFolder = Join-Path $DstUserRoot ((Get-Date).AddDays(-$daysAgo).ToString("yyyyMMdd"))
            if (-not (Test-Path $candidateDateFolder)) { continue }
            Get-ChildItem -Path $candidateDateFolder -Recurse -File -Filter "*.partial" -ErrorAction SilentlyContinue | ForEach-Object {
                $relPath = $_.FullName.Substring($candidateDateFolder.Length).TrimStart("\", "/") -replace '\.partial$', ''
                if (-not $orphanedPartials.ContainsKey($relPath)) {
                    $orphanedPartials[$relPath] = $_.FullName
                }
            }
        }

        foreach ($file in $Files) {
            $relativePath = $file.FullName.Substring($SrcRoot.Length).TrimStart("\", "/")

            $Dispatcher.Invoke([action]{
                $lblCurrentFile.Text = "Current: $relativePath"
                $pbCurrentFile.Value = 0
                $lblCurrentFileProgress.Text = ""
            }, "Normal")

            $destFile = Join-Path $DstRoot $relativePath
            $destDir = Split-Path $destFile -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            if (Test-Path $destFile) {
                $destInfo = Get-Item $destFile
                if ($destInfo.LastWriteTimeUtc -ge $file.LastWriteTimeUtc) {
                    Write-BackgroundStatus "(skip) File exists (destination newer/same): $relativePath"
                    $filesSkipped++
                    Update-BackgroundProgress
                    continue
                }
                Write-BackgroundStatus "(overwrite) File exists, source is newer: $relativePath"
            }

            $progressCallback = {
                param($bytesDone, $bytesTotal)
                $percent = if ($bytesTotal -gt 0) { [math]::Round(($bytesDone / $bytesTotal) * 100, 0) } else { 0 }
                $doneMb = [math]::Round($bytesDone / 1MB, 1)
                $totalMb = [math]::Round($bytesTotal / 1MB, 1)
                $Dispatcher.Invoke([action]{
                    $pbCurrentFile.Value = $percent
                    $lblCurrentFileProgress.Text = "$doneMb MB / $totalMb MB"
                }, "Normal")
            }.GetNewClosure()

            if (-not (Test-Path "$destFile.partial") -and $orphanedPartials.ContainsKey($relativePath)) {
                $orphanPartial = $orphanedPartials[$relativePath]
                $orphanMeta = "$orphanPartial.meta"
                if (Test-Path $orphanMeta) {
                    $metaLines = @(Get-Content -LiteralPath $orphanMeta -ErrorAction SilentlyContinue)
                    $srcInfo = Get-Item -LiteralPath $file.FullName
                    if ($metaLines.Count -ge 2 -and $metaLines[0] -eq "$($srcInfo.Length)" -and $metaLines[1] -eq "$($srcInfo.LastWriteTimeUtc.Ticks)") {
                        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                        try {
                            Move-Item -LiteralPath $orphanPartial -Destination "$destFile.partial" -Force
                            Move-Item -LiteralPath $orphanMeta -Destination "$destFile.partial.meta" -Force
                            Write-BackgroundStatus "Adopting orphaned partial copy for $relativePath (resuming across a day boundary)"
                        }
                        catch {
                            Write-BackgroundStatus "Failed to adopt orphaned partial copy for $relativePath : $($_.Exception.Message)"
                            foreach ($stray in @("$destFile.partial", "$destFile.partial.meta", $orphanPartial, $orphanMeta)) {
                                if (Test-Path -LiteralPath $stray) { Remove-Item -LiteralPath $stray -Force -ErrorAction SilentlyContinue }
                            }
                        }
                    }
                }
            }

            $result = Copy-FileResumable -Source $file.FullName -Destination $destFile -ProgressCallback $progressCallback

            if (-not $result.Success) {
                Write-BackgroundStatus "Failed to copy $relativePath after retries: $($result.Error)"
                $filesSkipped++
                Update-BackgroundProgress
                continue
            }

            Write-BackgroundStatus "Copied and hash-verified: $relativePath"

            try {
                $size = "{0:N0} KB" -f ($file.Length / 1KB)
                Add-CsvLogEntry `
                    -DTAName        $Snapshot.DtaName `
                    -Manager        $Snapshot.Manager `
                    -SourceSystem   $Snapshot.SourceSystem `
                    -DestSystem     $Snapshot.DestSystem `
                    -FileName       $relativePath `
                    -Classification $Snapshot.Classification `
                    -FileSize       $size `
                    -Checksum       $result.DestHash `
                    -MediaUsed      $Snapshot.MediaUsed `
                    -Justification  $Snapshot.Justification `
                    -ScanVerify     $Snapshot.ScanVerify

                Write-BackgroundStatus "Logged: $relativePath"
                $filesCopied++
            }
            catch {
                Write-BackgroundStatus "Failed to write CSV log for $relativePath : $($_.Exception.Message)"
                $filesSkipped++
            }

            Update-BackgroundProgress
        }

        $elapsed = (Get-Date) - $startTime
        Write-BackgroundStatus "Transfer complete."
        Write-BackgroundStatus "Summary: Total=$totalFiles, Copied=$filesCopied, Skipped=$filesSkipped, Elapsed=$($elapsed.ToString())"

        $Dispatcher.Invoke([action]{
            $lblCurrentFile.Text = "Current: (none)"
            $pbCurrentFile.Value = 0
            $lblCurrentFileProgress.Text = ""
        }, "Normal")
    }

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $powershell.AddScript($batchScript) | Out-Null
    $asyncResult = $powershell.BeginInvoke()
    }
    catch {
        Write-Status "Failed to start transfer: $($_.Exception.Message)"

        if ($powershell) { $powershell.Dispose() }
        if ($runspace) { $runspace.Close(); $runspace.Dispose() }

        $btnRun.IsEnabled = $true
        $btnClose.IsEnabled = $true
        return
    }

    $transferStartTime = Get-Date
    $stallTimeout = [TimeSpan]::FromMinutes(10)

    $completionTimer = New-Object System.Windows.Threading.DispatcherTimer
    $completionTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $completionTimer.Add_Tick({
        if (-not $asyncResult.IsCompleted) {
            # Safety net: if the background transfer never signals completion
            # (for any reason), don't leave the UI permanently disabled --
            # force it back to usable after a generous timeout instead.
            if (((Get-Date) - $transferStartTime) -gt $stallTimeout) {
                $completionTimer.Stop()
                Write-Status "Transfer did not finish within $([int]$stallTimeout.TotalMinutes) minutes and appears stalled. Re-enabling controls; verify the destination files manually, since the background transfer's true state is now unknown."
                try { $powershell.Stop() } catch {}
                $btnRun.IsEnabled = $true
                $btnClose.IsEnabled = $true
            }
            return
        }

        $completionTimer.Stop()

        try {
            try {
                $powershell.EndInvoke($asyncResult) | Out-Null
            }
            catch {
                Write-Status "Transfer runspace error: $($_.Exception.Message)"
            }

            foreach ($errorRecord in $powershell.Streams.Error) {
                Write-Status "Transfer error: $errorRecord"
            }

            $powershell.Dispose()
            $runspace.Close()
            $runspace.Dispose()
        }
        catch {
            Write-Status "Error cleaning up transfer runspace: $($_.Exception.Message)"
        }
        finally {
            # However cleanup goes, the UI must never stay stuck disabled.
            $btnRun.IsEnabled = $true
            $btnClose.IsEnabled = $true
        }
    }.GetNewClosure())
    $completionTimer.Start()
}
# ============================
# BUTTON HANDLERS
# ============================

function Show-FolderBrowser {
    param([string]$InitialPath)

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select a folder"
    if ($InitialPath -and (Test-Path $InitialPath)) {
        $dialog.SelectedPath = $InitialPath
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

$btnBrowseSource_Commercial.Add_Click({
    $selected = Show-FolderBrowser -InitialPath $txtSource_Commercial.Text
    if ($selected) { $txtSource_Commercial.Text = $selected }
})

$btnBrowseDest_Commercial.Add_Click({
    $selected = Show-FolderBrowser -InitialPath $txtDest_Commercial.Text
    if ($selected) { $txtDest_Commercial.Text = $selected }
})

$btnBrowseSource_MPN.Add_Click({
    $selected = Show-FolderBrowser -InitialPath $txtSource_MPN.Text
    if ($selected) { $txtSource_MPN.Text = $selected }
})

$btnBrowseDest_MPN.Add_Click({
    $selected = Show-FolderBrowser -InitialPath $txtDest_MPN.Text
    if ($selected) { $txtDest_MPN.Text = $selected }
})

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
