"""UI Custom Widgets and Styling Components."""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gdk

CUSTOM_CSS = b"""
.card-telemetry {
    background: alpha(@theme_selected_bg_color, 0.08);
    border: 1px solid alpha(@theme_selected_bg_color, 0.25);
    border-radius: 12px;
    padding: 14px;
    margin-bottom: 8px;
}

.status-badge-ok {
    background-color: #26a269;
    color: white;
    font-size: 11px;
    font-weight: 700;
    border-radius: 12px;
    padding: 3px 10px;
}

.status-badge-warn {
    background-color: #e5a50a;
    color: black;
    font-size: 11px;
    font-weight: 700;
    border-radius: 12px;
    padding: 3px 10px;
}

.status-badge-err {
    background-color: #c01c28;
    color: white;
    font-size: 11px;
    font-weight: 700;
    border-radius: 12px;
    padding: 3px 10px;
}

.metric-title {
    font-size: 12px;
    color: @secondary_color;
    font-weight: 500;
}

.metric-value {
    font-size: 15px;
    font-weight: 700;
}

.log-view {
    font-family: monospace;
    font-size: 11px;
    background-color: #1e1e1e;
    color: #e0e0e0;
    border-radius: 8px;
    padding: 8px;
}

.action-btn-primary {
    font-weight: 800;
    font-size: 15px;
    padding: 10px 24px;
}
"""


def load_application_css():
    """Loads custom CSS styles for the application."""
    provider = Gtk.CssProvider()
    provider.load_from_data(CUSTOM_CSS)
    display = Gdk.Display.get_default()
    if display:
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )


class DeviceTelemetryCard(Gtk.Box):
    """Visual card displaying live battery, refresh rate, and resolution telemetry."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add_css_class("card-telemetry")

        # Top line: Device name & Status badge
        top_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        
        icon = Gtk.Image.new_from_icon_name("phone-symbolic")
        icon.set_pixel_size(24)
        top_box.append(icon)

        self.lbl_device_title = Gtk.Label(label="Procurando dispositivo POCO...", xalign=0)
        self.lbl_device_title.set_hexpand(True)
        self.lbl_device_title.add_css_class("metric-value")
        top_box.append(self.lbl_device_title)

        self.badge_status = Gtk.Label(label="DESCONECTADO")
        self.badge_status.add_css_class("status-badge-err")
        top_box.append(self.badge_status)

        self.append(top_box)

        # Separator
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Grid of metrics
        grid = Gtk.Grid()
        grid.set_column_spacing(24)
        grid.set_row_spacing(6)
        grid.set_hexpand(True)

        # Row 0: Bateria & Temp
        lbl_bat_title = Gtk.Label(label="Bateria & Térmica", xalign=0)
        lbl_bat_title.add_css_class("metric-title")
        grid.attach(lbl_bat_title, 0, 0, 1, 1)

        self.lbl_bat_val = Gtk.Label(label="--% (--°C)", xalign=0)
        self.lbl_bat_val.add_css_class("metric-value")
        grid.attach(self.lbl_bat_val, 0, 1, 1, 1)

        # Row 0 Col 1: Taxa de Hz
        lbl_hz_title = Gtk.Label(label="Taxa de Atualização", xalign=0)
        lbl_hz_title.add_css_class("metric-title")
        grid.attach(lbl_hz_title, 1, 0, 1, 1)

        self.lbl_hz_val = Gtk.Label(label="-- Hz", xalign=0)
        self.lbl_hz_val.add_css_class("metric-value")
        grid.attach(self.lbl_hz_val, 1, 1, 1, 1)

        # Row 0 Col 2: Tela do Host & Resolução
        lbl_host_title = Gtk.Label(label="Resolução & Proporção", xalign=0)
        lbl_host_title.add_css_class("metric-title")
        grid.attach(lbl_host_title, 2, 0, 1, 1)

        self.lbl_host_val = Gtk.Label(label="--x-- (Host)", xalign=0)
        self.lbl_host_val.add_css_class("metric-value")
        grid.attach(self.lbl_host_val, 2, 1, 1, 1)

        self.append(grid)

    def update_data(self, device_info, host_info):
        """Updates the card contents with fresh telemetry."""
        if device_info.is_connected:
            self.lbl_device_title.set_label(f"POCO / {device_info.model} [{device_info.soc}]")
            self.badge_status.set_label("CONECTADO")
            self.badge_status.remove_css_class("status-badge-err")
            self.badge_status.add_css_class("status-badge-ok")

            charging_str = " ⚡" if device_info.is_charging else ""
            self.lbl_bat_val.set_label(f"{device_info.battery_level}%{charging_str} ({device_info.battery_temp_c:.1f}°C)")

            sync_status = " (Sync 60Hz)" if host_info.refresh_rate_hz == 60 else ""
            self.lbl_hz_val.set_label(f"{device_info.refresh_rate_hz} Hz{sync_status}")

            self.lbl_host_val.set_label(f"{host_info.resolution} ({host_info.aspect_ratio})")
        else:
            self.lbl_device_title.set_label("Nenhum dispositivo POCO conectado")
            self.badge_status.set_label("DESCONECTADO")
            self.badge_status.remove_css_class("status-badge-ok")
            self.badge_status.add_css_class("status-badge-err")

            self.lbl_bat_val.set_label("--% (--°C)")
            self.lbl_hz_val.set_label("-- Hz")
            self.lbl_host_val.set_label(f"{host_info.resolution} ({host_info.aspect_ratio})")
