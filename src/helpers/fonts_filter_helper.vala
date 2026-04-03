/* font_filter.vala
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

public class Sitra.Helpers.FontsFilterHelper : Object {
    public Gtk.CustomFilter filter { get; private set; }

    private Gtk.SearchEntry search_entry;
    private Gee.HashMap<string, Gtk.ToggleButton> category_toggles;

    public FontsFilterHelper (Gtk.SearchEntry search_entry,
        Gee.HashMap<string, Gtk.ToggleButton> category_toggles) {

        this.search_entry = search_entry;
        this.category_toggles = category_toggles;

        this.filter = new Gtk.CustomFilter ((item) => {
            return match_item (item);
        });
    }

    private bool match_item (Object? item) {
        string query = search_entry ? .text ? .strip () ? .ascii_down () ?? "";
        var font = item as Libsitra.Font;
        if (font == null) {
            warning ("Font '%s' not found in map", font.family);
            return false;
        }
        bool variable_only = category_toggles.has_key ("variable") &&
            category_toggles.get ("variable").active;

        var active_categories = new Gee.ArrayList<string> ();
        foreach (var key in category_toggles.keys) {
            if (key != "variable" && category_toggles.get (key).active)
                active_categories.add (key);
        }

        if (variable_only && !font.variable)
            return false;

        if (active_categories.size > 0 && !active_categories.contains (font.category))
            return false;

        if (query == "")
            return true;

        string[] terms = query.split (" ");
        foreach (string term in terms) {
            if (term == "")
                continue;

            bool found = false;

            if (font.family.ascii_down ().contains (term)) {
                found = true;
            } else {
                foreach (var subset in font.subsets) {
                    if (subset.ascii_down ().contains (term)) {
                        found = true;
                        break;
                    }
                }
            }

            if (!found)
                return false;
        }

        return true;
    }
}
