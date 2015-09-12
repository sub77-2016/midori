/*
   Copyright (C) 2013 André Stösel <andre@stoesel.de>

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   See the file COPYING for the full license text.
*/

Gtk.IconTheme theme;

namespace DevPet {
    enum TreeCells {
        MESSAGE,
        BACKTRACE,
        STOCK,
        COUNT
    }

    private class DataWindow : Gtk.Window {
        public string message {get; construct; }
        public string backtrace {get; construct; }

        private void create_content () {
            this.title = this.message;
            this.set_default_size (500, 500);

            Gtk.VBox vbox = new Gtk.VBox (false, 1);
            this.add (vbox);

            Gtk.TextBuffer message_buffer = new Gtk.TextBuffer (null);
            message_buffer.set_text (this.message);

            Gtk.TextView message_text_view = new Gtk.TextView.with_buffer (message_buffer);
            message_text_view.editable = false;

            Gtk.TextBuffer backtrace_buffer = new Gtk.TextBuffer (null);
            backtrace_buffer.set_text (this.backtrace);

            Gtk.TextView backtrace_text_view = new Gtk.TextView.with_buffer (backtrace_buffer);
            backtrace_text_view.editable = false;

            Gtk.ScrolledWindow message_scroll = new Gtk.ScrolledWindow (null, null);
            message_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            message_scroll.add (message_text_view);

            Gtk.ScrolledWindow backtrace_scroll = new Gtk.ScrolledWindow (null, null);
            backtrace_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            backtrace_scroll.add (backtrace_text_view);

            vbox.pack_start (message_scroll, false, false, 0);
            vbox.pack_end (backtrace_scroll, true, true, 0);

            this.show_all ();
        }

        internal DataWindow (string message, string backtrace) {
            GLib.Object (type: Gtk.WindowType.TOPLEVEL,
                window_position: Gtk.WindowPosition.CENTER,
                message: message,
                backtrace: backtrace);

            this.create_content ();
        }
    }

    private class LogWindow : Gtk.Window {
        private Manager manager;

        private void clear_list () {
            this.manager.clear_list ();
            this.destroy ();
        }

        #if HAVE_EXECINFO_H
        private void row_activated (Gtk.TreePath path, Gtk.TreeViewColumn column) {
            Gtk.TreeIter iter;
            if (this.manager.list_store.get_iter (out iter, path)) {
                string message;
                string backtrace;
                this.manager.list_store.get(iter,
                    TreeCells.MESSAGE, out message,
                    TreeCells.BACKTRACE, out backtrace, -1);

                DataWindow data_window = new DataWindow (message, backtrace);
                data_window.show ();
            }
        }
        #endif

        private void create_content () {
            this.title = "Midori - DevPet";
            this.set_default_size (500, 250);
            this.destroy.connect (this.manager.log_window_closed);

            Gtk.VBox vbox = new Gtk.VBox (false, 1);
            this.add (vbox);

            #if HAVE_EXECINFO_H
            Gtk.Label label = new Gtk.Label (_("Double click for more information"));
            vbox.pack_start (label, false, false, 0);
            #endif

            Gtk.ScrolledWindow scroll_windows = new Gtk.ScrolledWindow (null, null);
            scroll_windows.set_policy (Gtk.PolicyType.NEVER , Gtk.PolicyType.AUTOMATIC);
            scroll_windows.set_shadow_type (Gtk.ShadowType.ETCHED_IN);


            Gtk.Button clear = new Gtk.Button.from_stock ("gtk-clear");
            clear.clicked.connect (this.clear_list);

            vbox.pack_start (scroll_windows, true, true, 0);
            vbox.pack_start (clear, false, false, 0);


            Gtk.TreeView treeview = new Gtk.TreeView.with_model (this.manager.list_store);
            scroll_windows.add (treeview);

            treeview.insert_column_with_attributes (
                -1, "Type",
                new Gtk.CellRendererPixbuf (), "stock-id", TreeCells.STOCK);
            treeview.insert_column_with_attributes (
                -1, "Message",
                new Gtk.CellRendererText (), "text", TreeCells.MESSAGE);

            #if HAVE_EXECINFO_H
            treeview.row_activated.connect (this.row_activated);
            #endif

            this.show_all ();
        }

        internal LogWindow (Manager manager) {
            GLib.Object (type: Gtk.WindowType.TOPLEVEL,
                         window_position: Gtk.WindowPosition.CENTER);

            this.manager = manager;
            this.create_content ();
        }
    }

    private class Manager : Midori.Extension {
        public Gtk.ListStore list_store;
        private Gtk.StatusIcon? trayicon = null;
        private LogWindow? log_window;
        private GLib.LogFunc default_log_func;
        private GLib.LogLevelFlags icon_flag = GLib.LogLevelFlags.LEVEL_DEBUG;

        public void clear_list() {
            this.icon_flag = GLib.LogLevelFlags.LEVEL_DEBUG;
            if(this.trayicon != null)
                this.trayicon.set_visible (false);
            this.list_store.clear ();
        }

        public void log_window_closed () {
            this.log_window = null;
        }

        private unowned string get_stock_from_log_level (GLib.LogLevelFlags flags) {
            if ((flags & LogLevelFlags.LEVEL_CRITICAL) == flags || (flags & LogLevelFlags.LEVEL_ERROR) == flags) {
                return Gtk.Stock.DIALOG_ERROR;
            } else if ((flags & LogLevelFlags.LEVEL_WARNING) == flags) {
                return Gtk.Stock.DIALOG_WARNING;
            }
            return Gtk.Stock.DIALOG_INFO;
        }

        private void ensure_trayicon() {
            if(this.trayicon != null)
                return;

            this.trayicon = new Gtk.StatusIcon ();
            this.trayicon.set_tooltip_text ("Midori - DevPet");
            this.trayicon.activate.connect(this.show_error_log);
        }

        private void log_handler(string? domain, GLib.LogLevelFlags flags, string message) {
            Gtk.TreeIter iter;
            unowned string stock = this.get_stock_from_log_level (flags);

            this.ensure_trayicon();

            if (flags < this.icon_flag) {
                this.icon_flag = flags;
                this.trayicon.set_from_stock (stock);
            }

            #if HAVE_EXECINFO_H
                string bt = "";
                void* buffer[100];
                int num = Linux.backtrace (buffer, 100);
                /* Upstream bug: https://git.gnome.org/browse/vala/commit/?id=f402af94e8471c8314ee7a312260a776e4d6fbe2 */
                unowned string[] symbols = Midori.Linux.backtrace_symbols (buffer, num);
                if (symbols != null) {
                    /* we don't need the first three lines */
                    for (int i = 3; i < num; i++) {
                        bt += "\r\n%s".printf(symbols[i]);
                    }
                }
            #endif

            this.list_store.append (out iter);
            this.list_store.set (iter,
                TreeCells.MESSAGE, message,
                #if HAVE_EXECINFO_H
                TreeCells.BACKTRACE, bt,
                #endif
                TreeCells.STOCK, stock);

            this.trayicon.set_visible (true);
        }

        private void show_error_log () {
            if (this.log_window == null) {
                this.log_window = new LogWindow (this);
                this.log_window.show ();
            } else {
                if (this.log_window.is_active) {
                    this.log_window.hide ();
                } else {
                    this.log_window.present ();
                }
            }
        }

        private void activated (Midori.App app) {
            this.default_log_func = GLib.Log.default_handler;
            GLib.Log.set_default_handler (this.log_handler);
            if (this.trayicon != null) {
                int length = 0;
                this.list_store.foreach((model, path, iter) => {
                    length++;
                    return false;
                });

                if (length > 0) {
                    this.trayicon.set_visible (true);
                }
            }
        }

        private void deactivated () {
            if (this.trayicon != null)
                this.trayicon.set_visible (false);

            GLib.Log.set_default_handler (this.default_log_func);
        }

        internal Manager () {
            GLib.Object (name: _("DevPet"),
                         description: _("This extension shows glib error messages in systray."),
                         version: "0.1",
                         authors: "André Stösel <andre@stoesel.de>");

            this.list_store = new Gtk.ListStore (TreeCells.COUNT, typeof(string), typeof(string), typeof (string));

            this.activate.connect (this.activated);
            this.deactivate.connect (this.deactivated);
        }
    }
}

public Midori.Extension extension_init () {
    theme = Gtk.IconTheme.get_default ();
    return new DevPet.Manager ();
}

