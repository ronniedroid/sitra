/* window.vala
 *
 * Copyright 2025 Ronnie Nissan Yousif
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
using WebKit;
using Gee;
using Libsitra;

[GtkTemplate (ui = "/io/github/sitraorg/sitra/window.ui")]
public class Sitra.Window : Adw.ApplicationWindow {
    [GtkChild] private unowned Gtk.ListView fonts_list;
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Adw.NavigationSplitView split_view;
    [GtkChild] private unowned Adw.NavigationPage preview_page;
    [GtkChild] private unowned Gtk.Stack preview_stack;
    [GtkChild] private unowned Adw.WrapBox categories;
    [GtkChild] private unowned Gtk.ToggleButton search_button;
    [GtkChild] private unowned Gtk.SearchBar search_bar;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.Entry preview_entry;
    [GtkChild] private unowned Gtk.Box web_container;
    [GtkChild] private unowned Gtk.DropDown font_size_dropdown;
    [GtkChild] private unowned Gtk.DropDown line_height_dropdown;
    [GtkChild] private unowned Gtk.DropDown letter_spacing_dropdown;
    [GtkChild] private unowned Gtk.ToggleButton italic_toggle;
    [GtkChild] private unowned Adw.Banner banner;
    [GtkChild] private unowned Gtk.Label license_title;
    [GtkChild] private unowned Gtk.Label license_description;
    [GtkChild] private unowned Gtk.Label category_title;
    [GtkChild] private unowned Gtk.Label category_description;
    [GtkChild] private unowned Gtk.Label header_font_title;
    [GtkChild] private unowned Adw.ButtonContent header_font_category_button_content;
    [GtkChild] private unowned Adw.ButtonContent header_font_license_button_content;
    [GtkChild] private unowned Gtk.Button integrate_button;
    [GtkChild] private unowned Gtk.Button install_button;
    [GtkChild] private unowned Gtk.Button cancel_button;
    [GtkChild] private unowned Gtk.Button uninstall_button;
    [GtkChild] private unowned Gtk.ProgressBar install_progress_bar;
    [GtkChild] private unowned Adw.WrapBox subsets_box;

    private WebView web_view;
    private Gee.HashMap<string, Gtk.ToggleButton> category_toggles;
    private Gtk.CustomFilter filter;
    private Gtk.CustomSorter sorter;

    // Libsitra managers
    private Libsitra.Fonts fonts_manager;
    private Libsitra.Library library;

    // Sitra-specific managers
    private Sitra.Managers.PreviewManager preview_manager;
    private Sitra.Managers.Licenses licenses_manager;
    private Sitra.Managers.Categories categories_manager;
    private Sitra.IntegrationDialog integration_dialog;
    private Sitra.Helpers.NetworkHelper network_helper;

    private string? installing_font_family = null;
    private KeyFile preview_texts;
    private Gtk.FilterListModel filtered_model;
    private Gtk.SingleSelection fonts_model;

    public Window (Adw.Application app) {
        Object (application: app);

        // Initialize managers
        preview_manager = new Sitra.Managers.PreviewManager ();
        licenses_manager = new Sitra.Managers.Licenses ();
        categories_manager = new Sitra.Managers.Categories ();
        fonts_manager = new Libsitra.Fonts ();
        library = new Libsitra.Library ();
        integration_dialog = new Sitra.IntegrationDialog ();
        network_helper = Sitra.Helpers.NetworkHelper.get_instance ();

        // actions
        var searchAction = new SimpleAction ("search", null);
        searchAction.activate.connect (() => {
            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;
        });

        this.add_action (searchAction);

        // house keeping
        banner.set_revealed (false);

        // --- Load Preview Texts ---
        preview_texts = new KeyFile ();
        try {
            var preview_text_bytes = resources_lookup_data ("/io/github/sitraorg/sitra/preview_text", 0);
            preview_texts.load_from_data ((string) preview_text_bytes.get_data (), -1, KeyFileFlags.NONE);
        } catch (Error e) {
            warning ("Failed to load preview texts: %s", e.message);
        }

        // --- WebView ---
        web_view = new WebView ();
        web_view.valign = Gtk.Align.START;
        web_view.hexpand = true;
        web_view.set_size_request (-1, 100);
        web_container.append (web_view);

        var color = Gdk.RGBA ();
        color.parse ("rgba(0,0,0,0)");
        web_view.set_background_color (color);

        web_view.load_changed.connect ((load_event) => {
            if (load_event == LoadEvent.FINISHED) {
                resize_webview ();
            }
        });

        web_view.notify["allocated-width"].connect (() => {
            resize_webview ();
        });

        // --- Categories ---
        category_toggles = new Gee.HashMap<string, Gtk.ToggleButton> ();
        string[] categories_list = categories_manager.titles ();
        categories_list += "variable";

        foreach (string category in categories_list) {
            string label = format_category_labels (category);
            var toggle = new Gtk.ToggleButton.with_label (label);
            toggle.set_css_classes ({ "category", category });
            categories.append (toggle);
            category_toggles[category] = toggle;

            toggle.toggled.connect (() => {
                filter.changed (Gtk.FilterChange.DIFFERENT);
            });
        }

        // --- Fonts data ---
        var store = new ListStore (typeof (Libsitra.Font));
        foreach (var font in fonts_manager.collection ()) {
            store.append (font);
        }

        sorter = new Gtk.CustomSorter ((a, b) => {
            var fa = (Libsitra.Font) a;
            var fb = (Libsitra.Font) b;

            bool installed_a = library.is_installed (fa);
            bool installed_b = library.is_installed (fb);

            if (installed_a != installed_b)
                return installed_a ? -1 : 1;

            int score_a = fa.subsets.size + fa.weights.size;
            int score_b = fb.subsets.size + fb.weights.size;
            if (score_a != score_b)
                return score_b - score_a;
            return fa.family.collate (fb.family);
        });

        var sorted_model = new Gtk.SortListModel (store, sorter);

        var fonts_filter = new Sitra.Helpers.FontsFilterHelper (
                                                                search_entry,
                                                                category_toggles
        );
        filter = fonts_filter.filter;

        filtered_model = new Gtk.FilterListModel (sorted_model, filter);
        fonts_model = new Gtk.SingleSelection (filtered_model);
        fonts_model.autoselect = false;
        fonts_model.can_unselect = true;

        Idle.add (() => {
            fonts_model.unselect_all ();
            return false;
        });

        fonts_list.model = fonts_model;
        fonts_list.set_single_click_activate (false);

        // Setup factory for rendering list items
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.spacing = 0;
            box.margin_top = 6;
            box.margin_bottom = 6;

            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            var family_label = new Gtk.Label ("");
            family_label.set_halign (Gtk.Align.START);
            title_box.append (family_label);

            var installed_badge = new Gtk.Label ("✔");
            installed_badge.set_css_classes ({ "installed_check" });
            installed_badge.set_tooltip_text (_("Installed"));
            title_box.append (installed_badge);

            box.append (title_box);

            var info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

            var category_badge = new Gtk.Label ("");
            category_badge.set_halign (Gtk.Align.START);
            category_badge.set_css_classes ({ "caption", "info-badge" });
            info_box.append (category_badge);

            var separator = new Gtk.Label ("🞄");
            separator.set_halign (Gtk.Align.CENTER);
            separator.add_css_class ("caption");
            info_box.append (separator);

            var variable_badge = new Gtk.Label (_("Variable"));
            variable_badge.set_css_classes ({ "caption", "info-badge" });
            info_box.append (variable_badge);

            box.append (info_box);
            list_item.child = box;
        });

        factory.bind.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var box = (Gtk.Box) list_item.child;
            var title_box = (Gtk.Box) box.get_first_child ();
            var info_box = (Gtk.Box) box.get_last_child ();

            var family_label = (Gtk.Label) title_box.get_first_child ();
            var installed_badge = (Gtk.Label) title_box.get_last_child ();

            var category_badge = (Gtk.Label) info_box.get_first_child ();
            var separator = (Gtk.Label) category_badge.get_next_sibling ();
            var variable_badge = (Gtk.Label) info_box.get_last_child ();

            var font = (Libsitra.Font) list_item.item;
            bool is_installed = library.is_installed (font);

            family_label.set_label (font.family);
            installed_badge.visible = is_installed;

            category_badge.set_label (format_category_labels (font.category));
            separator.visible = font.variable;
            variable_badge.visible = font.variable;
        });

        fonts_list.factory = factory;

        fonts_model.selection_changed.connect (() => {
            if (!split_view.get_collapsed () && fonts_model.selected_item != null) {
                var font = (Libsitra.Font) fonts_model.selected_item;
                update_italic_toggle_state (font);
                update_preview (font);
                update_license_popover (font);
                update_category_popover (font);
                update_install_button_state ();
                update_subsets (font);
            }
        });

        fonts_list.activate.connect ((position) => {
            var item = filtered_model.get_item (position);
            if (item == null)
                return;

            var font = (Libsitra.Font) item;
            update_italic_toggle_state (font);
            update_preview (font);
            update_license_popover (font);
            update_category_popover (font);
            update_install_button_state ();
            update_subsets (font);

            if (split_view.get_collapsed ())
                split_view.set_show_content (true);
        });

        network_helper.connectivity_changed.connect ((is_online) => {
            if (!is_online) {
                banner.set_revealed (true);
            } else if (is_online && banner.get_revealed () && fonts_model.selected_item != null) {
                banner.set_revealed (false);
                var font = (Libsitra.Font) fonts_model.selected_item;
                update_preview (font);
            }
        });

        banner.button_clicked.connect (() => {
            banner.set_revealed (false);
            var font = (Libsitra.Font) fonts_model.selected_item;
            update_preview (font);
        });

        preview_entry.changed.connect (() => {
            var text = preview_entry.text.strip ();
            if (text.length == 0)
                text = preview_manager.DEFAULT_PREVIEW_TEXT;
            preview_manager.preview_text = text;
        });

        italic_toggle.bind_property (
                                     "active",
                                     preview_manager,
                                     "italic",
                                     BindingFlags.DEFAULT
        );

        bind_dropdown_to_property (font_size_dropdown, preview_manager, "font-size");
        bind_dropdown_to_property (line_height_dropdown, preview_manager, "line-height");
        bind_dropdown_to_property (letter_spacing_dropdown, preview_manager, "letter-spacing");

        preview_manager.notify.connect (() => {
            if (fonts_model.selected_item != null) {
                var font = (Libsitra.Font) fonts_model.selected_item;
                update_preview (font);
            }
        });

        split_view.notify["collapsed"].connect (() => {
            fonts_list.set_single_click_activate (split_view.get_collapsed ());
        });

        search_entry.search_changed.connect (() => {
            filter.changed (Gtk.FilterChange.DIFFERENT);
        });

        search_button.clicked.connect (() => {
            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;
        });

        // Setup library signals (changed from font_manager)
        library.installation_started.connect ((font_family) => {
            installing_font_family = font_family;
            if (is_selected_font (font_family)) {
                install_progress_bar.fraction = 0.0;
                install_progress_bar.visible = true;
                install_button.visible = false;
                cancel_button.visible = true;
            }
        });

        library.installation_progress.connect ((font_family, progress) => {
            if (is_selected_font (font_family)) {
                install_progress_bar.fraction = progress;
            }
        });

        library.installation_completed.connect ((font_family, success, error_message) => {
            installing_font_family = null;
            if (is_selected_font (font_family)) {
                install_progress_bar.visible = false;
                cancel_button.visible = false;
                install_button.visible = true;
            }

            if (success) {
                var toast = new Adw.Toast (_("Font '%s' installed successfully").printf (font_family));
                toast.timeout = 3;
                toast_overlay.add_toast (toast);
                if (is_selected_font (font_family)) {
                    update_install_button_state ();
                }
                sorter.changed (Gtk.SorterChange.DIFFERENT);
            } else {
                var toast = new Adw.Toast (_("Failed to install '%s': %s").printf (font_family, error_message ?? "Unknown error"));
                toast.timeout = 5;
                toast_overlay.add_toast (toast);
            }
        });

        library.uninstallation_completed.connect ((font_family, success, error_message) => {
            if (success) {
                var toast = new Adw.Toast (_("Font '%s' uninstalled successfully").printf (font_family));
                toast.timeout = 3;
                toast_overlay.add_toast (toast);
                update_install_button_state ();
                sorter.changed (Gtk.SorterChange.DIFFERENT);
            } else {
                var toast = new Adw.Toast (_("Failed to uninstall '%s': %s").printf (font_family, error_message ?? "Unknown error"));
                toast.timeout = 5;
                toast_overlay.add_toast (toast);
            }
        });

        integrate_button.clicked.connect (() => {
            if (fonts_model.selected_item != null) {
                var font = (Libsitra.Font) fonts_model.selected_item;
                integration_dialog.populate (font);
                integration_dialog.present (this);
            }
        });

        install_button.clicked.connect (() => {
            if (fonts_model.selected_item != null) {
                var font = (Libsitra.Font) fonts_model.selected_item;
                install_font_async.begin (font);
            }
        });

        cancel_button.clicked.connect (() => {
            library.cancel ();
        });

        uninstall_button.clicked.connect (() => {
            if (fonts_model.selected_item != null) {
                var font = (Libsitra.Font) fonts_model.selected_item;
                uninstall_font_async.begin (font);
            }
        });
    }

    // --- Helpers ---
    private string format_category_labels (string category) {
        string label;
        switch (category) {
        case "sans-serif": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Sans Serif"); break;
        case "serif": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Serif"); break;
        case "display": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Display"); break;
        case "handwriting": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Handwriting"); break;
        case "monospace": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Monospace"); break;
        case "icons": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Icons"); break;
        case "Variable":
        case "variable": label = GLib.dgettext (Config.GETTEXT_PACKAGE, "Variable"); break;
        default: label = category; break;
        }
        return label;
    }

    private bool is_any_default_text (string text) {
        if (text == "" || text == preview_manager.DEFAULT_PREVIEW_TEXT || text == preview_manager.DEFAULT_ICON_PREVIEW) {
            return true;
        }

        try {
            foreach (var key in preview_texts.get_keys ("preview_text")) {
                if (text == preview_texts.get_string ("preview_text", key)) {
                    return true;
                }
            }
        } catch (Error e) {
            // ignore
        }

        return false;
    }

    private void update_italic_toggle_state (Libsitra.Font font) {
        bool has_italic = font.styles.contains ("italic");
        italic_toggle.set_sensitive (has_italic);
        if (!has_italic) {
            italic_toggle.set_active (false);
            preview_manager.italic = false;
        }
    }

    private void update_preview (Libsitra.Font font) {
        if (!network_helper.has_connectivity ()) {
            banner.set_revealed (true);
            preview_stack.set_visible_child_name ("status");
            return;
        }

        preview_stack.set_visible_child_name ("preview");
        banner.set_revealed (false);

        if (font.weights == null || font.weights.size == 0) {
            font.weights = new Gee.ArrayList<int> ();
            font.weights.add (400);
        }

        preview_page.set_title (font.family);
        header_font_title.label = font.family;
        header_font_category_button_content.label = format_category_labels (font.category);
        header_font_license_button_content.label = font.license;

        var html = preview_manager.build_html (font);
        if (html == null || html.strip ().length == 0)
            html = "<html><body><p>" + _("No preview available") + "</p></body></html>";

        web_view.load_html (html, null);
    }

    private void update_subsets (Libsitra.Font font) {
        // Clear previous subsets
        Gtk.Widget? child_widget = subsets_box.get_first_child ();
        while (child_widget != null) {
            Gtk.Widget? next = child_widget.get_next_sibling ();
            subsets_box.remove (child_widget);
            child_widget = next;
        }

        if (font.subsets == null)
            return;

        string[] excluded_subsets = { "math", "symbols", "emoji", "icons", "ornaments", "music" };

        Gtk.ToggleButton? group_button = null;
        foreach (var subset in font.subsets) {
            bool excluded = false;
            foreach (var ex in excluded_subsets) {
                if (subset == ex) {
                    excluded = true;
                    break;
                }
            }
            if (excluded)continue;

            string label;
            if (subset.has_suffix ("-ext")) {
                string base_subset = subset.substring (0, subset.length - 4);
                label = GLib.dgettext (Config.GETTEXT_PACKAGE, base_subset) + _(" Extended");
            } else {
                label = GLib.dgettext (Config.GETTEXT_PACKAGE, subset);
            }
            int next_index = 0;
            unichar first_char;
            if (label.get_next_char (ref next_index, out first_char)) {
                label = first_char.toupper ().to_string () + label.substring (next_index);
            }

            var button = new Gtk.ToggleButton.with_label (label);
            button.add_css_class ("category");

            if (group_button == null) {
                group_button = button;
            } else {
                button.set_group (group_button);
            }

            string current_subset = subset;
            button.toggled.connect (() => {
                if (button.active) {
                    try {
                        string text = preview_texts.get_string ("preview_text", current_subset);
                        if (preview_entry.get_text () != text && is_any_default_text (preview_entry.get_text ())) {
                            preview_entry.set_text (text);
                        }
                    } catch (Error e) {
                        // ignore if not found in preview_texts
                    }
                }
            });

            subsets_box.append (button);
        }

        // Try to activate 'Latin' or the first one
        if (group_button != null) {
            Gtk.ToggleButton? latin_button = null;
            Gtk.Widget? iter = subsets_box.get_first_child ();
            while (iter != null) {
                var tb = iter as Gtk.ToggleButton;
                if (tb != null && tb.get_label ().ascii_down () == "latin") {
                    latin_button = tb;
                    break;
                }
                iter = iter.get_next_sibling ();
            }

            if (latin_button != null) {
                latin_button.set_active (true);
            } else {
                group_button.set_active (true);
            }
        }
    }

    private void bind_dropdown_to_property (Gtk.DropDown dropdown,
                                            Object target,
                                            string property_name) {
        dropdown.bind_property (
                                "selected-item",
                                target,
                                property_name,
                                BindingFlags.DEFAULT,
                                (binding, from_value, ref to_value) => {
            var selected = from_value.get_object () as Gtk.StringObject;
            if (selected != null) {
                to_value.set_string (selected.string);
                return true;
            }
            return false;
        });
    }

    private void update_license_popover (Libsitra.Font font) {
        this.license_title.label = font.license;
        this.license_description.label = GLib.dgettext (Config.GETTEXT_PACKAGE, licenses_manager.describe (font));
    }

    private void update_category_popover (Libsitra.Font font) {
        this.category_title.label = format_category_labels (font.category);
        this.category_description.label = GLib.dgettext (Config.GETTEXT_PACKAGE, categories_manager.describe (font));
    }

    private void resize_webview () {
        string js = "document.body.scrollHeight";
        web_view.evaluate_javascript.begin (js, -1, null, "", null, (obj, res) => {
            try {
                var val = web_view.evaluate_javascript.end (res);
                if (val.is_number ()) {
                    int height = (int) val.to_double ();
                    debug ("Resizing webview to: %d", height);
                    web_view.set_size_request (-1, height);
                }
            } catch (Error e) {
                debug ("Error resizing webview: %s", e.message);
            }
        });
    }

    private async void install_font_async (Libsitra.Font font) {
        try {
            yield library.install (font);
        } catch (Error e) {
            warning ("Font installation error: %s", e.message);
        }
    }

    private async void uninstall_font_async (Libsitra.Font font) {
        try {
            yield library.uninstall (font);
        } catch (Error e) {
            warning ("Font uninstallation error: %s", e.message);
        }
    }

    private bool is_selected_font (string family) {
        if (fonts_model.selected_item == null)
            return false;
        var font = (Libsitra.Font) fonts_model.selected_item;
        return font.family == family;
    }

    private void update_install_button_state () {
        if (fonts_model.selected_item == null) {
            install_button.visible = true;
            install_button.sensitive = true;
            uninstall_button.visible = false;
            return;
        }

        var font = (Libsitra.Font) fonts_model.selected_item;

        if (library.is_installed (font)) {
            install_button.visible = false;
            cancel_button.visible = false;
            uninstall_button.visible = true;
            uninstall_button.sensitive = true;
        } else if (installing_font_family == font.family) {
            install_button.visible = false;
            cancel_button.visible = true;
            uninstall_button.visible = false;
            install_progress_bar.visible = true;
        } else {
            install_button.visible = true;
            install_button.sensitive = (installing_font_family == null);
            cancel_button.visible = false;
            uninstall_button.visible = false;
            install_progress_bar.visible = false;
        }
    }
}