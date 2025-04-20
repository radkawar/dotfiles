#!/usr/bin/env python3
from dataclasses import dataclass
from typing import List, Tuple, Optional
from pathlib import Path
import shlex
import datetime
import os
import subprocess
import logging
import sys

# --- Helper Functions ---


def is_running_as_sudo() -> bool:
    """Check if the script is running with sudo privileges."""
    return os.geteuid() == 0


def run_command(command: str, capture_output: bool = False, check: bool = False, timeout: int = 30) -> Tuple[bool, Optional[str], Optional[str]]:
    """Run a shell command safely using subprocess.run."""
    try:
        args = shlex.split(command)
        process = subprocess.run(
            args,
            capture_output=capture_output,
            text=True,
            check=check,
            timeout=timeout
        )
        success = process.returncode == 0
        stdout = process.stdout if capture_output else None
        stderr = process.stderr if capture_output else None
        if not success and not capture_output and not check:
            logging.warning(
                f"Command failed (exit code {process.returncode}): {command}")
            if process.stderr:
                logging.warning(f"Stderr: {process.stderr.strip()}")
        return success, stdout, stderr
    except FileNotFoundError:
        logging.error(f"Command not found: {shlex.split(command)[0]}")
        return False, None, None
    except subprocess.TimeoutExpired:
        logging.error(f"Command timed out after {timeout}s: {command}")
        return False, None, None
    except subprocess.CalledProcessError as e:
        logging.error(
            f"Command '{command}' failed with exit code {e.returncode}.")
        if e.stderr:
            logging.error(f"Stderr: {e.stderr.strip()}")
        return False, e.stdout, e.stderr
    except Exception as e:
        logging.error(f"Error running command '{command}': {e}")
        return False, None, None


def backup_domains(domains: List[str], backup_dir: Path) -> None:
    """Back up specified preference domains using 'defaults export'."""
    logging.info(
        f"Backing up {len(domains)} preference domains to {backup_dir}...")
    backup_dir.mkdir(parents=True, exist_ok=True)
    backed_up_count = 0
    failed_count = 0
    skipped_count = 0

    for domain in domains:
        filename = domain.replace('/', '_') + ".plist"
        backup_path = backup_dir / filename
        command = f"defaults export {shlex.quote(domain)} {shlex.quote(str(backup_path))}"
        success, _, stderr = run_command(command, capture_output=True)

        if success:
            backed_up_count += 1
        else:
            if stderr and ("does not exist" in stderr or "Domain" in stderr and "not found" in stderr):
                skipped_count += 1
            else:
                failed_count += 1
                logging.warning(f"Could not back up domain '{domain}'.")

    logging.info(
        f"Backup complete: {backed_up_count} succeeded, {failed_count} failed, {skipped_count} skipped.")


def restart_services() -> None:
    """Restart services required for some settings to take effect."""
    logging.info("Applying changes by restarting relevant processes...")
    services_to_restart = ["Finder", "Dock", "SystemUIServer", "ControlCenter"]
    killed_any = False
    for service in services_to_restart:
        command = f"pkill -x {shlex.quote(service)}"
        success, _, _ = run_command(command)
        if success:
            logging.info(f"Attempted restart for {service}.")
            killed_any = True

    if not killed_any:
        logging.info("No relevant services found running to restart.")
    logging.info("Service restarts attempted.")
    logging.info("Note: Some changes may require a logout or system restart.")

# --- Settings Definitions ---


@dataclass
class Setting:
    domain: str
    key: str
    setting_type: str  # "regular", "array_add", "dict"
    type_flag: str = ""
    value: str = ""
    dict_items: Optional[List[Tuple[str, str, str]]] = None
    description: str = ""
    requires_sudo: bool = False

    def apply(self):
        if self.requires_sudo and not is_running_as_sudo():
            logging.warning(
                f"Setting {self.key} in {self.domain} requires sudo. Skipping.")
            return
        if self.setting_type == "regular":
            _apply(self.domain, self.key, self.type_flag,
                   self.value, self.description)
        elif self.setting_type == "array_add":
            _apply_array_add(self.domain, self.key,
                             self.value, self.description)
        elif self.setting_type == "dict":
            if self.dict_items is None:
                logging.error("dict_items not provided for dict setting.")
                return
            _apply_dict(self.domain, self.key,
                        self.dict_items, self.description)
        else:
            logging.error(f"Unknown setting type: {self.setting_type}")


def _apply(domain: str, key: str, type_flag: str, value: str, desc: str) -> None:
    command = f"defaults write {shlex.quote(domain)} {shlex.quote(key)} {type_flag} {shlex.quote(value)}"
    success, _, stderr = run_command(command, capture_output=True)
    if success and desc:
        logging.info(desc)
    elif not success:
        logging.error(
            f"Failed to apply setting: {key}={value} ({desc}) for domain {domain}")
        if stderr:
            logging.error(f"Stderr: {stderr.strip()}")


def _apply_array_add(domain: str, key: str, value: str, desc: str) -> None:
    command = f"defaults write {shlex.quote(domain)} {shlex.quote(key)} -array-add {shlex.quote(value)}"
    success, _, stderr = run_command(command, capture_output=True)
    if success and desc:
        logging.info(desc)
    elif not success:
        logging.warning(
            f"Failed to add to array: {key} += {value} ({desc}) for domain {domain}")
        if stderr:
            logging.warning(f"Stderr: {stderr.strip()}")


def _apply_dict(domain: str, key: str, dict_items: List[Tuple[str, str, str]], desc: str) -> None:
    parts = [f"{shlex.quote(d_key)} {d_type} {shlex.quote(str(d_value))}" for d_key,
             d_type, d_value in dict_items]
    command = f"defaults write {shlex.quote(domain)} {shlex.quote(key)} -dict {' '.join(parts)}"
    success, _, stderr = run_command(command, capture_output=True)
    if success and desc:
        logging.info(desc)
    elif not success:
        logging.error(
            f"Failed to apply dict setting: {key} ({desc}) for domain {domain}")
        if stderr:
            logging.error(f"Stderr: {stderr.strip()}")

# --- Define All Settings ---


global_settings = [
    Setting("NSGlobalDomain", "AppleShowAllExtensions", "regular",
            "-bool", "true", description="Show all filename extensions"),
    Setting("NSGlobalDomain", "AppleActionOnDoubleClick", "regular",
            "-string", "Maximize", description="Double-click title bar to zoom"),
    Setting("NSGlobalDomain", "AppleWindowTabbingMode", "regular",
            "-string", "fullscreen", description="Prefer tabs in full screen"),
    Setting("NSGlobalDomain", "NSCloseAlwaysConfirmsChanges", "regular", "-bool",
            "true", description="Ask to keep changes when closing documents"),
    Setting("NSGlobalDomain", "com.apple.trackpad.scaling", "regular",
            "-float", "0.5", description="Set slower trackpad cursor speed"),
    Setting("NSGlobalDomain", "com.apple.mouse.scaling", "regular",
            "-float", "0.5", description="Set slower mouse cursor speed"),
    Setting("NSGlobalDomain", "KeyRepeat", "regular", "-int",
            "2", description="Set key repeat rate to fast"),
    Setting("NSGlobalDomain", "InitialKeyRepeat", "regular", "-int",
            "15", description="Set delay until repeat to short"),
    Setting("NSGlobalDomain", "AppleKeyboardUIMode", "regular", "-int",
            "0", description="Disable keyboard navigation for controls"),
    Setting("NSGlobalDomain", "_HIHideMenuBar", "regular", "-bool",
            "true", description="Disable menu bar auto-hiding"),
]

finder_settings = [
    Setting("com.apple.finder", "AppleShowAllFiles", "regular",
            "-bool", "true", description="Show hidden files"),
    Setting("com.apple.finder", "FXPreferredViewStyle", "regular",
            "-string", "Nlsv", description="Set Finder to list view"),
    Setting("com.apple.finder", "ShowPathbar", "regular", "-bool",
            "true", description="Enable Finder path bar"),
]

dock_settings = [
    Setting("com.apple.dock", "tilesize", "regular", "-int",
            "36", description="Set Dock size to smaller"),
    Setting("com.apple.dock", "magnification", "regular", "-bool",
            "true", description="Enable Dock magnification"),
    Setting("com.apple.dock", "largesize", "regular", "-int",
            "64", description="Set magnification size"),
    Setting("com.apple.dock", "orientation", "regular", "-string",
            "bottom", description="Set Dock to bottom"),
    Setting("com.apple.dock", "mineffect", "regular", "-string",
            "genie", description="Set minimize effect to genie"),
    Setting("com.apple.dock", "minimize-to-application", "regular",
            "-bool", "false", description="Disable minimize to app icon"),
    Setting("com.apple.dock", "autohide", "regular", "-bool",
            "true", description="Enable Dock auto-hide"),
    Setting("com.apple.dock", "launchanim", "regular", "-bool",
            "true", description="Animate opening applications"),
    Setting("com.apple.dock", "show-process-indicators", "regular",
            "-bool", "true", description="Show indicators for open apps"),
    Setting("com.apple.dock", "show-recents", "regular", "-bool",
            "false", description="Disable recent apps in Dock"),
]

stage_manager_settings = [
    Setting("com.apple.WindowManager", "GloballyEnabled", "regular",
            "-bool", "true", description="Enable Stage Manager"),
    Setting("com.apple.WindowManager", "EnableStandardClickToShowDesktop",
            "regular", "-bool", "true", description="Click wallpaper to reveal desktop"),
    Setting("com.apple.WindowManager", "AutoHide", "regular", "-bool",
            "false", description="Disable Stage Manager auto-hide"),
    Setting("com.apple.WindowManager", "AppRecents", "regular", "-bool",
            "true", description="Enable recent apps in Stage Manager"),
    Setting("com.apple.WindowManager", "AppWindowGrouping", "regular",
            "-int", "1", description="Show one window per app"),
    Setting("com.apple.WindowManager", "ShowWidgetsOnDesktop", "regular",
            "-bool", "true", description="Enable widgets on Desktop"),
    Setting("com.apple.WindowManager", "ShowWidgetsInStageManager", "regular",
            "-bool", "true", description="Enable widgets in Stage Manager"),
    Setting("com.apple.WindowManager", "WidgetStyle", "regular",
            "-int", "0", description="Set widget style to automatic"),
]

launch_services_settings = [
    Setting("com.apple.LaunchServices/com.apple.launchservices.secure", "LSHandlers", "array_add",
            value='{LSHandlerRoleAll="com.google.chrome";LSHandlerURLScheme="http";}',
            description="Set Chrome as default for HTTP", requires_sudo=True),
    Setting("com.apple.LaunchServices/com.apple.launchservices.secure", "LSHandlers", "array_add",
            value='{LSHandlerRoleAll="com.google.chrome";LSHandlerURLScheme="https";}',
            description="Set Chrome as default for HTTPS", requires_sudo=True),
]

trackpad_settings = [
    Setting("com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerDrag",
            "regular", "-bool", "true", description="Enable three-finger drag"),
    Setting("com.apple.AppleMultitouchTrackpad", "Clicking", "regular",
            "-bool", "true", description="Enable tap to click"),
]

keyboard_extras_settings = [
    Setting("com.apple.BezelServices", "kDim", "regular", "-bool",
            "true", description="Adjust keyboard brightness in low light"),
    Setting("com.apple.BezelServices", "kDimTime", "regular", "-int",
            "300", description="Keyboard backlight off after 5 minutes"),
    Setting("com.apple.HIToolbox", "AppleFnUsageType", "regular", "-int",
            "2", description="Set Globe key to show Emoji & Symbols"),
]

security_settings = [
    Setting("com.apple.screensaver", "askForPassword", "regular",
            "-int", "1", description="Require password immediately"),
    Setting("com.apple.screensaver", "askForPasswordDelay", "regular",
            "-int", "0", description="Password required after sleep/screensaver"),
]

notification_settings = [
    Setting("com.apple.ncprefs", "notificationBannerStyle", "regular", "-string",
            "alert", description="Set default notification style to alerts"),
]

terminal_settings = [
    Setting("com.apple.Terminal", "ShellExitAction", "regular",
            "-int", "1", description="Close shell on exit"),
]

date_time_settings = [
    Setting("com.apple.menuextra.clock", "DateFormat", "regular",
            "-string", "'EEE d MMM h:mm:ss'", description="Set clock format"),
    Setting("com.apple.menuextra.clock", "ShowDate", "regular",
            "-int", "2", description="Always show date"),
    Setting("com.apple.menuextra.clock", "ShowDayOfWeek", "regular",
            "-bool", "true", description="Show day of week"),
    Setting("com.apple.menuextra.clock", "IsAnalog", "regular",
            "-bool", "false", description="Set time style to digital"),
    Setting("com.apple.menuextra.clock", "ShowAMPM", "regular",
            "-bool", "false", description="Disable AM/PM display"),
    Setting("com.apple.menuextra.clock", "FlashDateSeparators", "regular",
            "-bool", "false", description="Disable flashing time separators"),
    Setting("com.apple.menuextra.clock", "ShowSeconds", "regular",
            "-bool", "true", description="Display time with seconds"),
    Setting("com.apple.speech.synthesis.general.prefs", "TimeAnnouncementPrefs", "dict",
            dict_items=[
                ("TimeAnnouncementsEnabled", "-bool", "true"),
                ("TimeAnnouncerVolume", "-float", "0.5"),
                ("SpeakingRate", "-int", "180"),
            ], description="Enable announce the time on the hour"),
]

additional_settings = [
    Setting("com.apple.CoreBrightness", "NightShiftEnabled", "regular",
            "-bool", "true", description="Enable Night Shift"),
]

# --- Main Execution Logic ---


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    logging.info("Applying macOS Sonoma settings...")
    start_time = datetime.datetime.now()

    # Close System Settings to avoid conflicts
    logging.info("Closing System Settings...")
    run_command("osascript -e 'tell application \"System Settings\" to quit'")

    # Configure backup directory
    backup_base_dir = Path(os.path.expanduser("~")) / "macos_settings_backup"
    backup_dir = backup_base_dir / \
        f"backup_{start_time.strftime('%Y%m%d_%H%M%S')}"

    # Define settings groups
    settings_to_apply = [
        MacOSSetting("Global Domain Settings", global_settings),
        MacOSSetting("Finder Settings", finder_settings),
        MacOSSetting("Dock Settings", dock_settings),
        MacOSSetting("Stage Manager Settings", stage_manager_settings),
        MacOSSetting("Launch Services Settings", launch_services_settings),
        MacOSSetting("Trackpad Settings", trackpad_settings),
        MacOSSetting("Keyboard Extras Settings", keyboard_extras_settings),
        MacOSSetting("Security Settings", security_settings),
        MacOSSetting("Notification Settings", notification_settings),
        MacOSSetting("Terminal Settings", terminal_settings),
        MacOSSetting("Date and Time Settings", date_time_settings),
        MacOSSetting("Additional Settings", additional_settings),
    ]

    # Backup phase
    all_domains = {
        setting.domain for module in settings_to_apply for setting in module.settings}
    backup_domains(sorted(list(all_domains)), backup_dir)
    logging.info("-" * 30)

    # Apply phase
    logging.info("Applying settings...")
    for module in settings_to_apply:
        module.apply()
    logging.info("-" * 30)

    # Restart phase
    restart_services()
    logging.info("-" * 30)

    end_time = datetime.datetime.now()
    duration = end_time - start_time
    logging.info(f"Finished in {duration.total_seconds():.2f} seconds.")
    logging.info(f"Backups saved to: {backup_dir}")
    logging.info("Review warnings/errors above. Logout/restart may be needed.")

# --- MacOSSetting Class ---


class MacOSSetting:
    def __init__(self, description: str, settings: List[Setting]):
        self.description = description
        self.settings = settings

    def apply(self):
        logging.info(f"Configuring {self.description}...")
        for setting in self.settings:
            setting.apply()


if __name__ == "__main__":
    if sys.platform != "darwin":
        logging.error("This script is only supported on macOS.")
        sys.exit(1)
    main()
