"""Main entrypoint for the POCO Game Engine Application."""

import os
import sys
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio

from app.ui.widgets import load_application_css
from app.ui.window import MainWindow


class PocoGamingApp(Adw.Application):
    """Adwaita Application instance."""

    def __init__(self, script_path: str):
        super().__init__(
            application_id="com.poco.gaming.engine",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.script_path = script_path
        self.window = None

    def do_activate(self):
        load_application_css()
        if not self.window:
            self.window = MainWindow(self, self.script_path)
        self.window.present()


def main():
    # Base directory
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(base_dir, "poco-gaming.sh")

    app = PocoGamingApp(script_path)
    return app.run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
