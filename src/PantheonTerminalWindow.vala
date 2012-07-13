// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE

  Copyright (C) 2011-2012 David Gomes <davidrafagomes@gmail.com>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses/>

  END LICENSE
***/

using Gtk;
using Gdk;
using Vte;
using Granite;
using Pango;

namespace PantheonTerminal {

    public class PantheonTerminalWindow : Gtk.Window {

        public PantheonTerminalApp app;

        Notebook notebook;
        FontDescription system_font;
        private Button add_button;

        private GLib.List <TerminalWidget> terminals = new GLib.List <TerminalWidget> ();

        TerminalTab current_tab_label = null;
        public TerminalWidget current_terminal = null;
        Widget current_tab;
        private bool is_fullscreen = false;

        const string ui_string = """
            <ui>
            <popup name="MenuItemTool">
                <menuitem name="Quit" action="Quit"/>
                <menuitem name="New window" action="New window"/>
                <menuitem name="New tab" action="New tab"/>
                <menuitem name="CloseTab" action="CloseTab"/>
                <menuitem name="Copy" action="Copy"/>
                <menuitem name="Paste" action="Paste"/>
                <menuitem name="Select All" action="Select All"/>
                <menuitem name="About" action="About"/>

                <menuitem name="Fullscreen" action="Fullscreen"/>
            </popup>

            <popup name="AppMenu">
                <menuitem name="Copy" action="Copy"/>
                <menuitem name="Paste" action="Paste"/>
                <menuitem name="Select All" action="Select All"/>
                <separator />
                <menuitem name="About" action="About"/>
            </popup>
            </ui>
        """;

        public Gtk.ActionGroup main_actions;
        public Gtk.UIManager ui;

        public PantheonTerminalWindow (Granite.Application app) {
            this.app = app as PantheonTerminalApp;
            set_application (app);
            Notify.init (app.program_name);

            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
            title = _("Terminal");
            restore_saved_state ();

            /* Actions and UIManager */
            main_actions = new Gtk.ActionGroup ("MainActionGroup");
            main_actions.set_translation_domain ("pantheon-terminal");
            main_actions.add_actions (main_entries, this);

            ui = new Gtk.UIManager ();

            try {
                ui.add_ui_from_string (ui_string, -1);
            } catch (Error e) {
                error ("Couldn't load the UI: %s", e.message);
            }

            Gtk.AccelGroup accel_group = ui.get_accel_group();
            add_accel_group (accel_group);

            ui.insert_action_group (main_actions, 0);
            ui.ensure_update ();

            setup_ui ();
            show_all ();
            connect_signals ();

            system_font = FontDescription.from_string (get_system_font ());

            new_tab (true);
        }

        private void setup_ui () {
            /* Set up the Notebook */
            notebook = new Notebook ();
            var right_box = new HBox (false, 0);
            right_box.show ();
            notebook.set_action_widget (right_box, PackType.END);
            notebook.set_scrollable (true);
            notebook.can_focus = false;
            notebook.set_group_name ("pantheon-terminal");
            add (notebook);

            /* Set up the Add button */
            add_button = new Button ();
            Image add_image = null;
            add_image = new Image.from_icon_name ("list-add-symbolic", IconSize.MENU);
            add_button.set_image (add_image);
            add_button.show ();
            add_button.set_relief (ReliefStyle.NONE);
            add_button.set_tooltip_text (_("Open a new tab"));
            right_box.pack_start (add_button, false, false, 0);
        }

        private void connect_signals () {
            add_button.clicked.connect (() => { new_tab (false); } );
            notebook.switch_page.connect (on_switch_page);
            notebook.page_removed.connect (() => { if (notebook.get_n_pages () == 0) this.destroy (); });
        }

        private void restore_saved_state () {
            default_width = PantheonTerminal.saved_state.window_width;
            default_height = PantheonTerminal.saved_state.window_height;

            if (PantheonTerminal.saved_state.window_state == PantheonTerminalWindowState.MAXIMIZED)
                maximize ();
            else if (PantheonTerminal.saved_state.window_state == PantheonTerminalWindowState.FULLSCREEN)
                fullscreen ();
        }

        private void update_saved_state () {
            // Save window state
            if ((get_window ().get_state () & WindowState.MAXIMIZED) != 0)
                PantheonTerminal.saved_state.window_state = PantheonTerminalWindowState.MAXIMIZED;
            else if ((get_window ().get_state () & WindowState.FULLSCREEN) != 0)
                PantheonTerminal.saved_state.window_state = PantheonTerminalWindowState.FULLSCREEN;
            else
                PantheonTerminal.saved_state.window_state = PantheonTerminalWindowState.NORMAL;

            // Save window size
            if (PantheonTerminal.saved_state.window_state == PantheonTerminalWindowState.NORMAL) {
                int width, height;
                get_size (out width, out height);
                PantheonTerminal.saved_state.window_width = width;
                PantheonTerminal.saved_state.window_height = height;
            }
        }

        void on_switch_page (Widget page, uint n) {
            current_tab_label = notebook.get_tab_label (page) as TerminalTab;
            current_tab = notebook.get_nth_page ((int) n);
            current_terminal = ((Grid) page).get_child_at (0, 0) as TerminalWidget;
            title = current_terminal.window_title;
            page.grab_focus ();
        }

        public void remove_page (int page) {
            notebook.remove_page (page);
            if (notebook.get_n_pages () == 0) destroy ();
        }

        public bool on_scroll_event (EventScroll event) {
            if (event.direction == ScrollDirection.UP || event.direction == ScrollDirection.LEFT) {
                if (notebook.get_current_page() != 0) {
                    notebook.set_current_page (notebook.get_current_page() - 1);
                }
            } else if (event.direction == ScrollDirection.DOWN || event.direction == ScrollDirection.RIGHT) {
                if (notebook.get_current_page() != notebook.get_n_pages ()) {
                    notebook.set_current_page (notebook.get_current_page() + 1);
                }
            }
            return false;
        }

        private void new_tab (bool first) {
            /* Set up terminal */
            var t = new TerminalWidget (main_actions, ui, this);
            t.scrollback_lines = settings.scrollback_lines;
            current_terminal = t;
            var g = new Grid ();
            var sb = new Scrollbar (Orientation.VERTICAL, t.vadjustment);
            g.attach (t, 0, 0, 1, 1);
            g.attach (sb, 1, 0, 1, 1);

            /* Make the terminal occupy the whole GUI */
            t.vexpand = true;
            t.hexpand = true;

            /* Set up the virtual terminal */
            t.active_shell ();

            /* Set up actions releated to the terminal */
            main_actions.get_action ("Copy").set_sensitive (t.get_has_selection ());

            /* Create a new tab with the terminal */
            var tab = new TerminalTab (_("Terminal"));
            t.tab = tab;
            tab.scroll_event.connect (on_scroll_event);
            tab.terminal = current_terminal;
            tab.width_request = 64;
            int new_page = notebook.get_current_page () + 1;
            tab.index = new_page;
            notebook.insert_page (g, tab, new_page);
            notebook.set_tab_reorderable (notebook.get_nth_page (new_page), true);
            notebook.set_tab_detachable (notebook.get_nth_page (new_page), true);

            /* Bind signals to the new tab */
            tab.clicked.connect (() => {
                /* It was doing something */
                if (t.has_foreground_process ()) {
                    var d = new ForegroundProcessDialog ();
                    if (d.run () == 1) {
                        notebook.remove (g);
                        t.kill_ps_and_fg ();
                        terminals.remove (t);
                    }
                    d.destroy ();
                }
                else {
                    notebook.remove (g);
                    t.kill_ps ();
                    terminals.remove (t);
                }
            });

            t.window_title_changed.connect (() => {
                string new_text = t.get_window_title ();

                /* Strips the location */
                /*
                for (int i = 0; i < new_text.length; i++) {
                    if (new_text[i] == ':') {
                        new_text = new_text[i + 2:new_text.length];
                        break;
                    }
                }

                if (new_text.length > 50) {
                    new_text = new_text[new_text.length - 50:new_text.length];
                }
                */

                tab.set_text (new_text);
            });

            t.child_exited.connect (() => {
                notebook.remove (g);
                terminals.remove (t);
            });

            t.selection_changed.connect (() => {
                main_actions.get_action("Copy").set_sensitive (t.get_has_selection ());
            });

            t.set_font (system_font);
            set_size_request (t.calculate_width (30), t.calculate_height (8));
            tab.grab_focus ();
            g.show_all ();
            notebook.page = new_page;
            terminals.append (t);
        }

        static string get_system_font () {
            string font_name;

            var settings = new GLib.Settings ("org.gnome.desktop.interface");
            font_name = settings.get_string ("monospace-font-name");

            return font_name;
        }

        protected override bool delete_event (Gdk.EventAny event) {
            update_saved_state ();
            action_quit ();

            foreach (var t in terminals) {
                if (((TerminalWidget)t).has_foreground_process ()) {
                    var d = new ForegroundProcessDialog.before_close ();
                    if (d.run () == 1) {
                        return false;
                    } else {
                        d.destroy ();
                        return true;
                    }
                }
            }

            return false;
        }

        void action_quit () {

        }

        void action_copy () {
            current_terminal.copy_clipboard ();
        }

        void action_paste () {
            current_terminal.paste_clipboard ();
        }

        void action_select_all () {
            current_terminal.select_all ();
        }

        void action_close_tab () {
            current_tab_label.clicked ();
        }

        void action_new_window () {
            app.new_window ();
        }

        void action_new_tab () {
            new_tab (false);
        }

        void action_about () {
            app.show_about (this);
        }

        void action_fullscreen () {
          if (is_fullscreen) {
            unfullscreen();
            is_fullscreen = false;
            notebook.show_border = true;
          } else {
            fullscreen();
            is_fullscreen = true;
            notebook.show_border = false;
          }
        }

        static const Gtk.ActionEntry[] main_entries = {
           { "Quit", Gtk.Stock.QUIT, N_("Quit"), "<Control>q", N_("Quit"), action_quit },
           { "CloseTab", Gtk.Stock.CLOSE, N_("Close"), "<Control><Shift>w", N_("Close"), action_close_tab },
           { "New window", "window-new", N_("New Window"), "<Control><Shift>n", N_("Open a new window"),
             action_new_window },
           { "New tab", Gtk.Stock.NEW, N_("New Tab"), "<Control><Shift>t", N_("Create a new tab"), action_new_tab },
           { "Copy", "gtk-copy", N_("Copy"), "<Control><Shift>c", N_("Copy the selected text"), action_copy },
           { "Paste", "gtk-paste", N_("Paste"), "<Control><Shift>v", N_("Paste some text"), action_paste },
           { "Select All", Gtk.Stock.SELECT_ALL, N_("Select All"), "<Control><Shift>a",
             N_("Select all the text in the terminal"), action_select_all },
           { "About", Gtk.Stock.ABOUT, N_("About"), null, N_("Show about window"), action_about },

           { "Fullscreen", Gtk.Stock.FULLSCREEN, N_("Fullscreen"), "F11", N_("Toggle/Untoggle fullscreen"), action_fullscreen}
        };

    }

} // Namespace
