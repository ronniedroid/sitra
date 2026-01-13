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

[GtkTemplate (ui = "/io/github/ronniedroid/sitra/window.ui")]
public class Sitra.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Gtk.ListView fonts_list;
    [GtkChild] private unowned Adw.NavigationSplitView split_view;
    [GtkChild] private unowned Adw.NavigationPage preview_page;
    [GtkChild] private unowned Adw.ViewStack content_stack;
    [GtkChild] private unowned Adw.ViewSwitcher view_switcher;
    [GtkChild] private unowned Adw.WrapBox categories;
    [GtkChild] private unowned Gtk.ToggleButton search_button;
    [GtkChild] private unowned Gtk.SearchBar search_bar;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.Entry preview_entry;
    [GtkChild] private unowned Gtk.Box web_container;
    [GtkChild] private unowned Gtk.ActionBar bottom_action_bar;
    [GtkChild] private unowned Gtk.DropDown font_size_dropdown;
    [GtkChild] private unowned Gtk.DropDown line_height_dropdown;
    [GtkChild] private unowned Gtk.DropDown letter_spacing_dropdown;
    [GtkChild] private unowned Gtk.ToggleButton italic_toggle;
    [GtkChild] private unowned Adw.Banner banner;
    [GtkChild] private unowned Gtk.Popover license_popover;

    // Details Page Widgets
    [GtkChild] private unowned Adw.ActionRow details_family_row;
    [GtkChild] private unowned Adw.ActionRow details_category_row;
    [GtkChild] private unowned Gtk.MenuButton license_button;
    [GtkChild] private unowned Adw.ActionRow details_variable_row;
    [GtkChild] private unowned Gtk.Image details_variable_icon;
    [GtkChild] private unowned Adw.ExpanderRow details_subsets_row;
    [GtkChild] private unowned Adw.ExpanderRow details_styles_row;
    [GtkChild] private unowned Gtk.Button details_integrate_button;
    [GtkChild] private unowned Gtk.Button details_install_button;

    private WebView web_view;
    private Gee.HashMap<string, Gtk.ToggleButton> category_toggles;
    private Gtk.CustomFilter filter;
    private Sitra.Managers.FontsManager fonts_manager;
    private Sitra.Managers.PreviewManager preview_manager;
    private Sitra.Managers.LicensesManager licenses_manager;
    private Sitra.IntegrationDialog integration_dialog;
    private Sitra.Helpers.NetworkHelper network_helper;

    private Gtk.FilterListModel filtered_model;
    private Gtk.SingleSelection fonts_model;

    // Tracking lists for dynamic rows to clear them properly
    private Gee.ArrayList<Gtk.Widget> subset_rows;
    private Gee.ArrayList<Gtk.Widget> style_rows;

    public Window (Adw.Application app) {
        Object (application: app);

        preview_manager = new Sitra.Managers.PreviewManager ();
        licenses_manager = new Sitra.Managers.LicensesManager ();
        integration_dialog = new Sitra.IntegrationDialog ();
        network_helper = Sitra.Helpers.NetworkHelper.get_instance ();

        subset_rows = new Gee.ArrayList<Gtk.Widget> ();
        style_rows = new Gee.ArrayList<Gtk.Widget> ();

        banner.set_revealed (false);
        view_switcher.visible = false;

        // --- Load JSON font data ---
        string json_data = "";
        try {
            var bytes = resources_lookup_data ("/io/github/ronniedroid/sitra/fonts.json", 0);
            json_data = (string) bytes.get_data ();
        } catch (Error e) {
            warning ("Failed to load fonts.json: %s", e.message);
            json_data = "[]";
        }

        // --- WebView ---
        web_view = new WebView ();
        web_view.vexpand = true;
        web_view.hexpand = true;
        web_container.append (web_view);

        var color = Gdk.RGBA ();
        color.parse ("rgba(0,0,0,0)");
        web_view.set_background_color (color);

        // --- Categories ---
        category_toggles = new Gee.HashMap<string, Gtk.ToggleButton> ();

        string[] categories_list = {
            "sans-serif", "display", "serif", "handwriting",
            "monospace", "icons", "variable", "other"
        };

        foreach (string category in categories_list) {
            var label = category == "sans-serif" ? "sans serif" : category;
            var toggle = new Gtk.ToggleButton.with_label (label);
            toggle.set_css_classes ({ "category", category });
            categories.append (toggle);
            category_toggles[category] = toggle;

            toggle.toggled.connect (() => {
                filter.changed (Gtk.FilterChange.DIFFERENT);
            });
        }

        // --- Fonts data ---
        fonts_manager = new Sitra.Managers.FontsManager ();

        try {
            fonts_manager.load_from_json (json_data);
        } catch (Error e) {
            warning ("Failed to load fonts: %s", e.message);
        }

        var font_names = new Gtk.StringList (
                                             fonts_manager.get_font_names_array ()
        );

        var fonts_filter = new Sitra.Helpers.FontsFilterHelper (
                                                                fonts_manager.get_all_fonts (),
                                                                search_entry,
                                                                category_toggles
        );

        filter = fonts_filter.filter;

        filtered_model = new Gtk.FilterListModel (font_names, filter);

        fonts_model = new Gtk.SingleSelection (filtered_model);
        fonts_model.autoselect = false;
        fonts_model.can_unselect = true;

        Idle.add (() => {
            fonts_model.unselect_all ();
            content_stack.set_visible_child_name ("welcome");
            view_switcher.visible = false;
            return false;
        });

        fonts_list.model = fonts_model;
        fonts_list.set_single_click_activate (false);

        // Setup factory for rendering list items
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.spacing = 6;
            box.margin_top = 6;
            box.margin_bottom = 6;

            // Horizontal box for category and variable badge
            var category_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            var category_label = new Gtk.Label ("");
            category_label.set_halign (Gtk.Align.START);
            category_label.add_css_class ("dimmed");
            category_label.add_css_class ("caption-heading");
            category_box.append (category_label);

            var variable_badge = new Gtk.Label ("Variable");
            variable_badge.add_css_class ("caption");
            variable_badge.add_css_class ("variable-badge");
            category_box.append (variable_badge);

            box.append (category_box);

            var family_label = new Gtk.Label ("");
            family_label.set_halign (Gtk.Align.START);
            box.append (family_label);

            list_item.child = box;
        });

        factory.bind.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var box = (Gtk.Box) list_item.child;
            var category_box = (Gtk.Box) box.get_first_child ();
            var category_label = (Gtk.Label) category_box.get_first_child ();
            var variable_badge = (Gtk.Label) category_box.get_last_child ();
            var family_label = (Gtk.Label) box.get_last_child ();

            var string_object = (Gtk.StringObject) list_item.item;
            var font = fonts_manager.get_font (string_object.string);

            category_label.set_label (font.category);
            family_label.set_label (font.family);

            // Show badge only for variable fonts
            variable_badge.visible = font.variable;
        });
        fonts_list.factory = factory;

        fonts_model.selection_changed.connect (() => {
            if (!split_view.get_collapsed () && fonts_model.selected_item != null) {
                var string_object = (Gtk.StringObject) fonts_model.selected_item;
                var family = string_object.string;
                update_italic_toggle_state (family);
                update_preview (family);
                update_license_popover (family);
                update_details_page (family);
            }
        });

        fonts_list.activate.connect ((position) => {
            var item = filtered_model.get_item (position);
            if (item == null)
                return;

            var string_object = (Gtk.StringObject) item;
            var family = string_object.string;

            update_italic_toggle_state (family);
            update_preview (family);
            update_license_popover (family);
            update_details_page (family);

            if (split_view.get_collapsed ())
                split_view.set_show_content (true);
        });

        network_helper.connectivity_changed.connect ((is_online) => {
            if (!is_online) {
                banner.set_revealed (true);
            } else if (is_online && banner.get_revealed () && fonts_model.selected_item != null) {
                banner.set_revealed (false);
                var string_object = (Gtk.StringObject) fonts_model.selected_item;
                update_preview (string_object.string);
            }
        });

        banner.button_clicked.connect (() => {
            banner.set_revealed (false);
            var string_object = (Gtk.StringObject) fonts_model.selected_item;
            update_preview (string_object.string);
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
                var string_object = (Gtk.StringObject) fonts_model.selected_item;
                update_preview (string_object.string);
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

        details_integrate_button.clicked.connect (() => {
            if (fonts_model.selected_item != null) {
                var string_object = (Gtk.StringObject) fonts_model.selected_item;
                var font = fonts_manager.get_font (string_object.string);
                if (font != null) {
                    integration_dialog.populate (font);
                    integration_dialog.present (this);
                }
            }
        });

        details_install_button.clicked.connect (() => {
            // Placeholder for install logic
            // For now just print to stdout
            if (fonts_model.selected_item != null) {
                var string_object = (Gtk.StringObject) fonts_model.selected_item;
                print ("Download requested for: %s\n", string_object.string);
            }
        });

        content_stack.notify["visible-child"].connect (() => {
            if (view_switcher.visible) {
                var current_page = content_stack.get_visible_child_name ();
                bottom_action_bar.visible = (current_page == "preview");
            }
        });
    }

    // --- Helpers ---

    private void update_italic_toggle_state (string family) {
        var font = fonts_manager.get_font (family);
        if (font == null)
            return;

        bool has_italic = font.styles.contains ("italic");
        italic_toggle.set_sensitive (has_italic);

        if (!has_italic) {
            italic_toggle.set_active (false);
            preview_manager.italic = false;
        }
    }

    private void update_preview (string family_name) {
        if (!network_helper.has_connectivity ()) {
            banner.set_revealed (true);
            content_stack.set_visible_child_name ("status");
            set_visibility (false);
            return;
        }

        var current_page = content_stack.get_visible_child_name ();
        if (current_page == "welcome" || current_page == "status") {
            content_stack.set_visible_child_name ("preview");
        }

        banner.set_revealed (false);
        set_visibility (true);

        var preview_font = fonts_manager.get_font (family_name);
        if (preview_font == null) {
            stderr.printf ("ERROR: Font not found: %s\n", family_name);
            return;
        }

        if (preview_font.weights == null || preview_font.weights.size == 0) {
            preview_font.weights = new Gee.ArrayList<int> ();
            preview_font.weights.add (400);
        }

        preview_page.set_title (family_name);

        var html = preview_manager.build_html (preview_font);
        if (html == null || html.strip ().length == 0)
            html = "<html><body><p>No preview available</p></body></html>";

        web_view.load_html (html, null);
    }

    private void set_visibility (bool val) {
        view_switcher.visible = val;

        if (val) {
            var current_page = content_stack.get_visible_child_name ();
            bottom_action_bar.visible = (current_page == "preview");
        } else {
            bottom_action_bar.visible = false;
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

    private void update_license_popover (string family_name) {
        var font = fonts_manager.get_font (family_name);
        if (font == null)
            return;

        licenses_manager.populate_popover (license_popover, font);
        license_button.set_label (font.license);
    }

    private void update_details_page (string family_name) {
        var font = fonts_manager.get_font (family_name);
        if (font == null)return;

        details_family_row.subtitle = font.family;
        details_category_row.subtitle = font.category;

        if (font.variable) {
            details_variable_row.subtitle = "Yes";
            details_variable_icon.set_from_icon_name ("emblem-ok-symbolic");
        } else {
            details_variable_row.subtitle = "No";
            details_variable_icon.set_from_icon_name ("emblem-remove-symbolic");
        }

        // Clear previous rows
        foreach (var child in subset_rows) {
            details_subsets_row.remove (child);
        }
        subset_rows.clear ();

        foreach (var child in style_rows) {
            details_styles_row.remove (child);
        }
        style_rows.clear ();

        if (font.subsets != null) {
            foreach (var subset in font.subsets) {
                var row = new Adw.ActionRow ();
                row.title = subset;
                details_subsets_row.add_row (row);
                subset_rows.add (row);
            }
        }

        if (font.styles != null) {
            foreach (var style in font.styles) {
                var row = new Adw.ActionRow ();
                row.title = style;
                details_styles_row.add_row (row);
                style_rows.add (row);
            }
        }
    }
}
