"""OmniLink Mobile Engine - Main entrypoint."""

import os
import sys
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio

from app.ui.widgets import load_application_css
from app.ui.window import MainWindow


class OmniLinkApp(Adw.Application):
    """Adwaita Application instance for OmniLink Mobile Engine."""

    def __init__(self, script_path: str):
        super().__init__(
            application_id="com.omnilink.engine",
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
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(base_dir, "omnilink.sh")
    if not os.path.exists(script_path):
        script_path = os.path.join(base_dir, "poco-gaming.sh")

    app = OmniLinkApp(script_path)
    return app.run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
