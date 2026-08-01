/* integration_dialog.vala
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

using Gee;

[GtkTemplate (ui = "/io/github/sitraorg/sitra/integration_dialog.ui")]
public class Sitra.IntegrationDialog : Adw.Dialog {

    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Adw.ActionRow npm_row;
    [GtkChild] private unowned Adw.ActionRow yarn_row;
    [GtkChild] private unowned Adw.ActionRow pnpm_row;
    [GtkChild] private unowned Adw.ActionRow bun_row;
    [GtkChild] private unowned Adw.ActionRow css_import_row;
    [GtkChild] private unowned Adw.ActionRow css_usage_row;
    [GtkChild] private unowned Gtk.Label cdn_css_code_label;
    [GtkChild] private unowned Adw.ActionRow cdn_usage_row;
    [GtkChild] private unowned Adw.ComboRow cdn_subset_row;
    [GtkChild] private unowned Adw.ComboRow cdn_weight_row;
    [GtkChild] private unowned Adw.ComboRow cdn_style_row;
    [GtkChild] private unowned Adw.ComboRow cdn_display_row;
    [GtkChild] private unowned Adw.ComboRow cdn_format_row;
    [GtkChild] private unowned Gtk.Button copy_npm_button;
    [GtkChild] private unowned Gtk.Button copy_yarn_button;
    [GtkChild] private unowned Gtk.Button copy_pnpm_button;
    [GtkChild] private unowned Gtk.Button copy_bun_button;
    [GtkChild] private unowned Gtk.Button copy_css_import_button;
    [GtkChild] private unowned Gtk.Button copy_css_usage_button;
    [GtkChild] private unowned Gtk.Button copy_cdn_usage_button;
    [GtkChild] private unowned Gtk.Button copy_cdn_css_code_button;
    [GtkChild] private unowned Adw.SwitchRow install_static_switch_row;
    [GtkChild] private unowned Adw.SwitchRow cdn_static_switch_row;

    private Libsitra.Font? current_font = null;
    private string current_package_name = "";

    public IntegrationDialog () {
        // Connect signals to regenerate CSS when options change
        cdn_subset_row.notify["selected"].connect (() => update_cdn_css_code ());
        cdn_weight_row.notify["selected"].connect (() => update_cdn_css_code ());
        cdn_style_row.notify["selected"].connect (() => update_cdn_css_code ());
        cdn_display_row.notify["selected"].connect (() => update_cdn_css_code ());
        cdn_format_row.notify["selected"].connect (() => update_cdn_css_code ());

        // Sync switches
        install_static_switch_row.bind_property ("active", cdn_static_switch_row, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

        install_static_switch_row.notify["active"].connect (update_instructions);
        cdn_static_switch_row.notify["active"].connect (update_instructions);

        setup_copy_buttons ();
    }

    public void populate (Libsitra.Font font) {
        current_font = font;
        current_package_name = font.family.ascii_down ().replace (" ", "-");

        install_static_switch_row.visible = font.variable;
        cdn_static_switch_row.visible = font.variable;

        // Reset static switch to false (always default to variable if available)
        install_static_switch_row.active = false;

        update_instructions ();
    }

    private bool is_variable_mode () {
        return current_font != null && current_font.variable && !install_static_switch_row.active;
    }

    private void update_instructions () {
        if (current_font == null)return;


        var font = current_font;
        bool variable_mode = is_variable_mode ();
        string scope = variable_mode ? "@fontsource-variable" : "@fontsource";

        // NPM instruction
        npm_row.subtitle = @"npm install $(scope)/$(current_package_name)";

        // Yarn instruction
        yarn_row.subtitle = @"yarn add $(scope)/$(current_package_name)";

        // PNPM instruction
        pnpm_row.subtitle = @"pnpm add $(scope)/$(current_package_name)";

        // Bun instruction
        bun_row.subtitle = @"bun add $(scope)/$(current_package_name)";

        // CSS import instruction
        css_import_row.title = @"import '$(scope)/$(current_package_name)';";

        var family_name = font.family;
        if (variable_mode) {
            family_name += " Variable";
        }

        // CSS usage instruction
        css_usage_row.subtitle = @"font-family: '$(family_name)', sans-serif;";

        // Populate subset dropdown
        populate_subset_dropdown (font);

        // Populate weight dropdown
        populate_weight_dropdown (font);

        // Disable italic style if not available
        update_style_availability (font);

        // Disable format selection for variable fonts (always woff2)
        if (variable_mode) {
            cdn_format_row.sensitive = false;
            cdn_weight_row.sensitive = false;
        } else {
            cdn_format_row.sensitive = true;
            cdn_weight_row.sensitive = true;
        }

        // CDN CSS usage
        cdn_usage_row.title = @"font-family: '$(family_name)', sans-serif;";

        // Generate initial CSS code
        update_cdn_css_code ();
    }

    private void populate_subset_dropdown (Libsitra.Font font) {
        var subsets = font.subsets;
        if (subsets == null || subsets.size == 0) {
            subsets = new ArrayList<string> ();
            subsets.add ("latin");
        }

        var subset_strings = new Gtk.StringList (null);
        foreach (var subset in subsets) {
            subset_strings.append (subset);
        }

        cdn_subset_row.model = subset_strings;

        // Try to select 'latin' by default, otherwise first one
        int latin_index = -1;
        for (int i = 0; i < subsets.size; i++) {
            if (subsets[i] == "latin") {
                latin_index = i;
                break;
            }
        }

        if (latin_index != -1) {
            cdn_subset_row.selected = latin_index;
        } else {
            cdn_subset_row.selected = 0;
        }
    }

    private void populate_weight_dropdown (Libsitra.Font font) {
        var weights = font.weights;
        if (weights == null || weights.size == 0) {
            weights = new ArrayList<int> ();
            weights.add (400);
        }

        var weight_strings = new Gtk.StringList (null);
        foreach (var weight in weights) {
            weight_strings.append (@"$(weight)");
        }

        cdn_weight_row.model = weight_strings;
        cdn_weight_row.selected = 0; // Select first weight by default
    }

    private void update_style_availability (Libsitra.Font font) {
        bool has_italic = font.styles != null && font.styles.contains ("italic");

        // If no italic, force selection to normal and disable the row
        if (!has_italic) {
            cdn_style_row.selected = 0; // normal
            cdn_style_row.sensitive = false;
        } else {
            cdn_style_row.sensitive = true;
        }
    }

    private void update_cdn_css_code () {
        if (current_font == null)return;

        var subset_obj = cdn_subset_row.selected_item as Gtk.StringObject;
        var weight_obj = cdn_weight_row.selected_item as Gtk.StringObject;
        var style_obj = cdn_style_row.selected_item as Gtk.StringObject;
        var display_obj = cdn_display_row.selected_item as Gtk.StringObject;
        var format_obj = cdn_format_row.selected_item as Gtk.StringObject;

        if (subset_obj == null || weight_obj == null || style_obj == null || display_obj == null || format_obj == null) {
            return;
        }

        var subset = subset_obj.string;
        var weight = weight_obj.string;
        var style = style_obj.string;
        var display = display_obj.string;
        var format = format_obj.string;

        var css = generate_font_face_css (
                                          current_font,
                                          current_package_name,
                                          subset,
                                          weight,
                                          style,
                                          display,
                                          format
        );

        cdn_css_code_label.label = css;
    }

    private string generate_font_face_css (Libsitra.Font font,
                                           string package_name,
                                           string subset,
                                           string weight,
                                           string style,
                                           string display,
                                           string format) {
        var css_builder = new StringBuilder ();
        bool variable_mode = is_variable_mode ();

        // Comment header
        if (variable_mode) {
            css_builder.append (@"/* $(package_name)-$(subset)-wght-normal */\n");
        } else {
            css_builder.append (@"/* $(package_name)-$(subset)-$(weight)-$(style) */\n");
        }

        css_builder.append ("@font-face {\n");

        if (variable_mode) {
            css_builder.append (@"  font-family: '$(font.family) Variable';\n");

            // Calculate weight range
            int min_weight = 100;
            int max_weight = 900;
            if (font.weights != null && font.weights.size > 0) {
                // Create a copy to avoid mutating the original data
                var weights_copy = new ArrayList<int> ();
                weights_copy.add_all (font.weights);
                weights_copy.sort ();

                min_weight = weights_copy.get (0);
                max_weight = weights_copy.get (weights_copy.size - 1);
            }
            css_builder.append (@"  font-weight: $(min_weight) $(max_weight);\n");
        } else {
            css_builder.append (@"  font-family: '$(font.family)';\n");
            css_builder.append (@"  font-weight: $(weight);\n");
        }

        css_builder.append (@"  font-style: $(style);\n");
        css_builder.append (@"  font-display: $(display);\n");

        // Build src based on format selection
        css_builder.append ("  src: ");

        if (variable_mode) {
            // Variable Fonts URL format:
            // https://cdn.jsdelivr.net/fontsource/fonts/{id}:vf@{version}/{subset}-{axes}-{style}.woff2
            // Example: https://cdn.jsdelivr.net/fontsource/fonts/inter:vf@latest/latin-wght-normal.woff2
            css_builder.append (@"url(https://cdn.jsdelivr.net/fontsource/fonts/$(package_name):vf@latest/$(subset)-wght-$(style).woff2) format('woff2-variations');\n");
        } else {
            if (format == "woff2 + woff") {
                css_builder.append (@"url(https://cdn.jsdelivr.net/fontsource/fonts/$(package_name)@latest/$(subset)-$(weight)-$(style).woff2) format('woff2'), ");
                css_builder.append (@"url(https://cdn.jsdelivr.net/fontsource/fonts/$(package_name)@latest/$(subset)-$(weight)-$(style).woff) format('woff');\n");
            } else if (format == "woff2") {
                css_builder.append (@"url(https://cdn.jsdelivr.net/fontsource/fonts/$(package_name)@latest/$(subset)-$(weight)-$(style).woff2) format('woff2');\n");
            } else { // woff
                css_builder.append (@"url(https://cdn.jsdelivr.net/fontsource/fonts/$(package_name)@latest/$(subset)-$(weight)-$(style).woff) format('woff');\n");
            }
        }

        css_builder.append ("}");

        return css_builder.str;
    }

    private void setup_copy_buttons () {
        copy_npm_button.clicked.connect (() => {
            copy_to_clipboard (npm_row.subtitle);
        });

        copy_yarn_button.clicked.connect (() => {
            copy_to_clipboard (yarn_row.subtitle);
        });

        copy_pnpm_button.clicked.connect (() => {
            copy_to_clipboard (pnpm_row.subtitle);
        });

        copy_bun_button.clicked.connect (() => {
            copy_to_clipboard (bun_row.subtitle);
        });

        copy_css_import_button.clicked.connect (() => {
            copy_to_clipboard (css_import_row.title);
        });

        copy_css_usage_button.clicked.connect (() => {
            copy_to_clipboard (css_usage_row.subtitle);
        });

        copy_cdn_usage_button.clicked.connect (() => {
            copy_to_clipboard (cdn_usage_row.title);
        });

        copy_cdn_css_code_button.clicked.connect (() => {
            copy_to_clipboard (cdn_css_code_label.label);
        });
    }

    private void copy_to_clipboard (string text) {
        var clipboard = this.get_clipboard ();
        clipboard.set_text (text);

        var toast = new Adw.Toast (_("Copied to clipboard"));
        toast.timeout = 2;
        toast_overlay.add_toast (toast);
    }
}
