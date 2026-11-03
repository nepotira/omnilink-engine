"""Main Application Window for POCO Game Engine."""

import os
import threading
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Pango

from app.backend.adb import ADBManager, DeviceInfo, HostDisplayInfo
from app.backend.session import SessionManager, SessionOptions, SessionState
from app.ui.widgets import DeviceTelemetryCard


class MainWindow(Adw.ApplicationWindow):
    """Main Application Window with Libadwaita styling and real-time controls."""

    def __init__(self, app, script_path: str):
        super().__init__(application=app, title="POCO Zero-Latency Game Engine")
        self.set_default_size(720, 780)

        self.session_manager = SessionManager(script_path)
        self.device_info = ADBManager.get_device_info()
        self.host_info = ADBManager.get_host_display_info()
        self._is_polling = True

        # Toast Overlay
        self.toast_overlay = Adw.ToastOverlay()
        self.set_content(self.toast_overlay)

        # Main Box
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.toast_overlay.set_child(main_box)

        # HeaderBar
        header = Adw.HeaderBar()
        title_widget = Adw.WindowTitle(
            title="POCO Game Engine",
            subtitle="Snapdragon 8 Elite Gaming Suite"
        )
        header.set_title_widget(title_widget)
        main_box.append(header)

        # Scrolled Window
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        main_box.append(scrolled)

        # Content Page
        page = Adw.PreferencesPage()
        scrolled.set_child(page)

        # 1. Telemetry Card
        group_telemetry = Adw.PreferencesGroup()
        self.telemetry_card = DeviceTelemetryCard()
        group_telemetry.add(self.telemetry_card)
        page.add(group_telemetry)

        # 2. Execution Profiles
        group_modes = Adw.PreferencesGroup(
            title="Perfil de Desempenho",
            description="Escolha a resolução e o pipeline de aceleração gráfica"
        )
        self.combo_mode = Adw.ComboRow(title="Modo de Operação")
        mode_model = Gtk.StringList.new([
            "🎮 Gamer Max (1920x1280 3:2 @ 16M - Ultra Imersivo)",
            "⚡ Esports Eco (1280x854 3:2 @ 8M - Baixa Temperatura)",
            "🖥️ Desktop / DeX (Janelas Flutuantes, Tela Nativa Intacta)",
            "📱 Display Secundário (Tela Virtual Independente)",
            "⌨️ Modo OTG Dock (KVM Teclado/Mouse sem Vídeo)"
        ])
        self.combo_mode.set_model(mode_model)
        self.combo_mode.set_selected(0)
        group_modes.add(self.combo_mode)
        page.add(group_modes)

        # 3. Hardware & Display Adjustments
        group_settings = Adw.PreferencesGroup(
            title="Ajustes de Tela e Conforto",
            description="Sincronização de rotação, sensores e áudio de baixa latência"
        )

        # Phone Rotation
        self.combo_rotation = Adw.ComboRow(title="Orientação da Tela do Celular")
        rot_model = Gtk.StringList.new([
            "🔄 Forçar Paisagem (270° - Padrão p/ Games)",
            "📱 Forçar Retrato (0°)",
            "🌐 Automática / Livre"
        ])
        self.combo_rotation.set_model(rot_model)
        self.combo_rotation.set_selected(0)
        group_settings.add(self.combo_rotation)

        # Laptop Orientation Lock
        self.switch_laptop_lock = Adw.SwitchRow(
            title="Travar Rotação do Notebook Zorin",
            subtitle="Evita que o sensor de toque e aceleração do laptop gire durante o jogo"
        )
        self.switch_laptop_lock.set_active(True)
        group_settings.add(self.switch_laptop_lock)

        # Audio Routing
        self.combo_audio = Adw.ComboRow(title="Roteamento de Áudio")
        audio_model = Gtk.StringList.new([
            "🔊 Dual (PC e Celular simultâneos)",
            "💻 Somente no Computador",
            "🔇 Somente no Celular (Silêncio no PC)"
        ])
        self.combo_audio.set_model(audio_model)
        self.combo_audio.set_selected(0)
        group_settings.add(self.combo_audio)

        # Thermal Screen Off
        self.switch_screen_off = Adw.SwitchRow(
            title="Economia Térmica (Apagar Tela Física)",
            subtitle="Desliga o painel do POCO enquanto espelha, reduzindo calor e consumo"
        )
        self.switch_screen_off.set_active(True)
        group_settings.add(self.switch_screen_off)

        page.add(group_settings)

        # 4. Diagnostic & Live Logs
        group_logs = Adw.PreferencesGroup(
            title="Terminal de Diagnósticos e Logs",
            description="Acompanhamento em tempo real das mensagens do ADB e scrcpy"
        )
        self.expander_logs = Adw.ExpanderRow(title="Visualizar Logs em Tempo Real")
        
        log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        log_box.set_margin_top(8)
        log_box.set_margin_bottom(8)
        log_box.set_margin_start(12)
        log_box.set_margin_end(12)

        scrolled_log = Gtk.ScrolledWindow()
        scrolled_log.set_min_content_height(140)
        scrolled_log.set_max_content_height(200)
        scrolled_log.set_vexpand(True)

        self.text_log = Gtk.TextView()
        self.text_log.set_editable(False)
        self.text_log.set_cursor_visible(False)
        self.text_log.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.text_log.add_css_class("log-view")
        self.log_buffer = self.text_log.get_buffer()
        scrolled_log.set_child(self.text_log)
        log_box.append(scrolled_log)

        # Clear logs button
        btn_clear_log = Gtk.Button(label="Limpar Logs")
        btn_clear_log.set_halign(Gtk.Align.END)
        btn_clear_log.connect("clicked", lambda _: self.log_buffer.set_text(""))
        log_box.append(btn_clear_log)

        self.expander_logs.add_row(log_box)
        group_logs.add(self.expander_logs)
        page.add(group_logs)

        # 5. Bottom Action Bar
        bottom_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        bottom_bar.set_margin_top(12)
        bottom_bar.set_margin_bottom(16)
        bottom_bar.set_margin_start(24)
        bottom_bar.set_margin_end(24)

        # Emergency Reset Button
        self.btn_reset = Gtk.Button(label="🔄 Restaurar Padrões")
        self.btn_reset.set_tooltip_text("Restaura a resolução nativa, densidade, Hz, rotação e launcher do POCO")
        self.btn_reset.connect("clicked", self.on_reset_clicked)
        bottom_bar.append(self.btn_reset)

        # Spacer
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        bottom_bar.append(spacer)

        # Primary Launch/Stop Button
        self.btn_action = Gtk.Button(label="🎮 INICIAR JOGO")
        self.btn_action.add_css_class("suggested-action")
        self.btn_action.add_css_class("pill")
        self.btn_action.add_css_class("action-btn-primary")
        self.btn_action.connect("clicked", self.on_action_clicked)
        bottom_bar.append(self.btn_action)

        main_box.append(bottom_bar)

        # Start Telemetry Polling Timer
        self._update_ui_telemetry()
        GLib.timeout_add_seconds(3, self._poll_telemetry_loop)

        # Window Close Handler
        self.connect("close-request", self.on_window_close)

    def _append_log(self, text: str):
        end_iter = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end_iter, text)
        # Auto scroll to bottom
        mark = self.log_buffer.create_mark(None, self.log_buffer.get_end_iter(), False)
        self.text_log.scroll_to_mark(mark, 0.05, False, 0.0, 1.0)

    def _show_toast(self, message: str):
        toast = Adw.Toast.new(message)
        toast.set_timeout(3)
        self.toast_overlay.add_toast(toast)

    def _update_ui_telemetry(self):
        self.telemetry_card.update_data(self.device_info, self.host_info)

    def _poll_telemetry_loop(self):
        if not self._is_polling:
            return False

        def fetch():
            dev = ADBManager.get_device_info()
            host = ADBManager.get_host_display_info()
            def update():
                self.device_info = dev
                self.host_info = host
                self._update_ui_telemetry()
                return False
            GLib.idle_add(update)

        t = threading.Thread(target=fetch, daemon=True)
        t.start()
        return True

    def on_action_clicked(self, _button):
        if self.session_manager.is_running():
            # Stop session
            self.btn_action.set_sensitive(False)
            self.btn_action.set_label("⏳ Restaurando...")
            self._append_log("[INFO] Solicitando encerramento da sessão...\n")
            self.session_manager.stop_session(self._on_state_changed)
        else:
            # Check connection first
            if not self.device_info.is_connected:
                self._show_toast("Nenhum celular POCO detectado. Conecte o cabo USB!")
                self._append_log("[ERRO] Dispositivo não conectado ao tentar iniciar.\n")
                return

            # Debounce protection: disable button immediately to absorb double-clicks
            self.btn_action.set_sensitive(False)
            self.btn_action.set_label("⏳ Conectando...")
            self.btn_reset.set_sensitive(False)

            # Prepare options
            mode_idx = self.combo_mode.get_selected()
            modes = ["max", "eco", "dex", "virtual", "otg"]
            selected_mode = modes[mode_idx] if mode_idx < len(modes) else "max"

            rot_idx = self.combo_rotation.get_selected()
            rotations = ["landscape", "portrait", "auto"]
            selected_rot = rotations[rot_idx] if rot_idx < len(rotations) else "landscape"

            audio_idx = self.combo_audio.get_selected()
            audios = ["dual", "pc", "off"]
            selected_audio = audios[audio_idx] if audio_idx < len(audios) else "dual"

            options = SessionOptions(
                mode=selected_mode,
                orientation=selected_rot,
                lock_laptop=self.switch_laptop_lock.get_active(),
                audio_route=selected_audio,
                screen_off=self.switch_screen_off.get_active(),
            )

            self._append_log(f"\n===> Iniciando Sessão ({selected_mode.upper()}) <===\n")
            self.session_manager.start_session(
                options=options,
                on_log=self._append_log,
                on_state_change=self._on_state_changed,
            )

    def _on_state_changed(self, state: SessionState):
        if state == SessionState.STARTING:
            self.btn_action.set_label("⏳ Conectando...")
            self.btn_action.set_sensitive(False)
            self.btn_reset.set_sensitive(False)
        elif state == SessionState.RUNNING:
            self.btn_action.set_label("🛑 PARAR SESSÃO")
            self.btn_action.remove_css_class("suggested-action")
            self.btn_action.add_css_class("destructive-action")
            self.btn_reset.set_sensitive(False)
            self._show_toast("🎮 Sessão iniciada com sucesso!")

            # 2.5s Grace period: prevent rapid accidental clicking from immediately terminating
            def enable_stop_btn():
                if self.session_manager.is_running():
                    self.btn_action.set_sensitive(True)
                return False
            GLib.timeout_add(2500, enable_stop_btn)

        elif state == SessionState.STOPPING:
            self.btn_action.set_label("⏳ Restaurando...")
            self.btn_action.set_sensitive(False)
        elif state == SessionState.IDLE:
            self.btn_action.set_label("🎮 INICIAR JOGO")
            self.btn_action.set_sensitive(True)
            self.btn_action.remove_css_class("destructive-action")
            self.btn_action.add_css_class("suggested-action")
            self.btn_reset.set_sensitive(True)
            self._show_toast("Dispositivo e tela restaurados com sucesso.")
        elif state == SessionState.ERROR:
            self.btn_action.set_label("🎮 INICIAR JOGO")
            self.btn_action.set_sensitive(True)
            self.btn_action.remove_css_class("destructive-action")
            self.btn_action.add_css_class("suggested-action")
            self.btn_reset.set_sensitive(True)
            self._show_toast("Erro durante a execução. Verifique os logs.")

    def on_reset_clicked(self, _button):
        self.btn_reset.set_sensitive(False)
        self._show_toast("Executando restauração dos padrões...")
        
        def on_done(success: bool):
            self.btn_reset.set_sensitive(True)
            if success:
                self._show_toast("✅ Padrões originais do POCO restaurados!")
            else:
                self._show_toast("⚠️ Restauração concluída com avisos.")
            self._poll_telemetry_loop()

        self.session_manager.run_reset_task(
            on_log=self._append_log,
            on_complete=on_done,
        )

    def on_window_close(self, _win):
        self._is_polling = False
        if self.session_manager.is_running():
            self.session_manager.stop_session()
        return False
