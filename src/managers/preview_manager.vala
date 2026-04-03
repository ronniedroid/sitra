/* preview_manager.vala
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

public class Sitra.Managers.PreviewManager : Object {
    public string DEFAULT_PREVIEW_TEXT {get; default = "Sphinx of black quartz, judge my vow.";}
    public string DEFAULT_ICON_PREVIEW {get; default = "★ ✓ ✕ ☰ ⚙ ♥ ☆ ⬆ ⬇ ⬅ ➡ ● ○ ◆ ■ □";}
    public string preview_text { get; set; default = "Sphinx of black quartz, judge my vow."; }
    public string font_size {get; set; default = "24px"; }
    public string line_height {get; set; default = "1"; }
    public string letter_spacing {get; set; default = "0"; }
    public bool italic { get; set; default = false; }

    private bool is_icon_font(Libsitra.Font font) {
        return font.category == "icons";
    }

    private string get_dir () {
        var dir = "ltr";
        if (Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL) {
         dir = "rtl";
        }

        return dir;
    }

    private string determine_preview_text(Libsitra.Font font) {
        // If user has custom preview text, always use that
        if (this.preview_text != DEFAULT_PREVIEW_TEXT) {
            return this.preview_text;
        }

        if (is_icon_font(font)) {
            return DEFAULT_ICON_PREVIEW;
        }

        return DEFAULT_PREVIEW_TEXT;
    }

    private Gee.List<string> detect_needed_subsets(string text, Gee.List<string> available_subsets) {
        var needed = new Gee.HashSet<string>();

        // Scan the text for character ranges
        for (int i = 0; i < text.length; i++) {
            unichar c = text.get_char(i);

            // Icons and Symbols (Private Use Area + common icon ranges)
            if ((c >= 0xE000 && c <= 0xF8FF) ||   // Private Use Area
                (c >= 0xF0000 && c <= 0xFFFFD) ||  // Supplementary Private Use Area-A
                (c >= 0x100000 && c <= 0x10FFFD) || // Supplementary Private Use Area-B
                (c >= 0x2190 && c <= 0x21FF) ||    // Arrows
                (c >= 0x2300 && c <= 0x23FF) ||    // Miscellaneous Technical
                (c >= 0x2600 && c <= 0x26FF) ||    // Miscellaneous Symbols
                (c >= 0x2700 && c <= 0x27BF) ||    // Dingbats
                (c >= 0x1F300 && c <= 0x1F9FF)) {  // Emoji & Pictographs
                // Check for icon/symbol-specific subsets
                if (available_subsets.contains("symbols")) needed.add("symbols");
                if (available_subsets.contains("icons")) needed.add("icons");
                // Also load latin as fallback for icon fonts
                if (available_subsets.contains("latin")) needed.add("latin");
            }
            // Arabic
            if ((c >= 0x0600 && c <= 0x06FF) || (c >= 0x0750 && c <= 0x077F) ||
                (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF)) {
                if (available_subsets.contains("arabic")) needed.add("arabic");
            }
            // Cyrillic
            else if (c >= 0x0400 && c <= 0x04FF) {
                if (available_subsets.contains("cyrillic")) needed.add("cyrillic");
                if (available_subsets.contains("cyrillic-ext")) needed.add("cyrillic-ext");
            }
            // Greek
            else if ((c >= 0x0370 && c <= 0x03FF) || (c >= 0x1F00 && c <= 0x1FFF)) {
                if (available_subsets.contains("greek")) needed.add("greek");
                if (available_subsets.contains("greek-ext")) needed.add("greek-ext");
            }
            // Hebrew
            else if ((c >= 0x0590 && c <= 0x05FF) || (c >= 0xFB1D && c <= 0xFB4F)) {
                if (available_subsets.contains("hebrew")) needed.add("hebrew");
            }
            // Chinese
            else if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
                if (available_subsets.contains("chinese-simplified")) needed.add("chinese-simplified");
                if (available_subsets.contains("chinese-traditional")) needed.add("chinese-traditional");
                if (available_subsets.contains("chinese-hongkong")) needed.add("chinese-hongkong");
            }
            // Japanese (Hiragana, Katakana, Kanji)
            else if ((c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF) ||
                     (c >= 0x4E00 && c <= 0x9FFF)) {
                if (available_subsets.contains("japanese")) needed.add("japanese");
            }
            // Korean (Hangul)
            else if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) ||
                     (c >= 0x3130 && c <= 0x318F)) {
                if (available_subsets.contains("korean")) needed.add("korean");
            }
            // Devanagari (Hindi, Sanskrit, etc.)
            else if (c >= 0x0900 && c <= 0x097F) {
                if (available_subsets.contains("devanagari")) needed.add("devanagari");
            }
            // Vietnamese
            else if ((c >= 0x1EA0 && c <= 0x1EF9) || c == 0x0102 || c == 0x0103 ||
                     c == 0x0110 || c == 0x0111 || c == 0x01A0 || c == 0x01A1 ||
                     c == 0x01AF || c == 0x01B0) {
                if (available_subsets.contains("vietnamese")) needed.add("vietnamese");
            }
            // Thai
            else if (c >= 0x0E00 && c <= 0x0E7F) {
                if (available_subsets.contains("thai")) needed.add("thai");
            }
            // Latin Extended
            else if (c >= 0x0100 && c <= 0x024F) {
                if (available_subsets.contains("latin-ext")) needed.add("latin-ext");
            }
            // Basic Latin
            else if ((c >= 0x0020 && c <= 0x007E) || (c >= 0x00A0 && c <= 0x00FF)) {
                if (available_subsets.contains("latin")) needed.add("latin");
            }
        }

        // if (available_subsets.contains("latin")) {
        //     needed.add("latin");
        // }

        if (needed.is_empty && !available_subsets.is_empty) {
            needed.add(available_subsets[0]);
        }

        var result = new Gee.ArrayList<string>();
        foreach (var subset in needed) {
            result.add(subset);
        }

        return result;
    }

    private string get_font_url (Libsitra.Font font, string subset, int? weight = null, bool italic = false) {
        string font_slug = font.family.ascii_down().replace(" ", "-");
        if (font.variable) {
            return "https://cdn.jsdelivr.net/fontsource/fonts/%s:vf@latest/%s-wght-normal.woff2".printf(font_slug, subset);
        } else {
            int w = weight != null ? weight : 400;
            string style = italic ? "italic" : "normal";
            return "https://cdn.jsdelivr.net/fontsource/fonts/%s@latest/%s-%d-%s.woff2".printf(font_slug, subset, w, style);
        }
    }

    /**git
     * Builds the HTML preview for a font.
     * Only loads subsets needed for the preview text.
     *
     * @param font The FontInfo object.
     */
    public string build_html (Libsitra.Font font) {
        var html = new StringBuilder();

        string display_text = determine_preview_text(font);
        string direction = get_dir();
        html.append (@"<!DOCTYPE html><html dir='$direction'><head><meta charset='UTF-8'>\n");
        html.append ("<link rel=\"preconnect\" href=\"https://cdn.jsdelivr.net\" crossorigin>\n");
        html.append ("<style>\n");

        var needed_subsets = detect_needed_subsets(display_text, font.subsets);

        if (font.variable) {
            foreach (var subset in needed_subsets) {
                string font_url = get_font_url(font, subset);
                html.append_printf ("""
                @font-face {
                    font-family: '%s';
                    src: url('%s') format('woff2');
                    font-display: swap;
                }
                """, font.family, font_url);
            }
        } else {
            foreach (var subset in needed_subsets) {
                foreach (var w in font.weights) {
                    string font_url = get_font_url(font, subset, w, this.italic);
                    html.append_printf ("""
                @font-face {
                    font-family: '%s';
                    font-weight: %d;
                    src: url('%s') format('woff2');
                    font-display: swap;
                }
                """, font.family, w, font_url);
                }
            }
        }

        html.append_printf("""
            :root { color-scheme: light dark; }
            html, body {
                background-color: transparent;
                color: black;
                margin: 0;
                overflow: hidden;
            }
            @media (prefers-color-scheme: dark) {
                html, body {
                    color: white;
                }
            }
            p.sample-text {
                font-family: '%s', sans-serif;
                font-style: %s;
                font-size: %s;
                line-height: %s;
                letter-spacing: %spx;
                margin: 8px 0;
            }
            .weight-label {
                font-size: 12px;
                opacity: 0.6;
                margin: 8px 0 4px 0;
            }
        """, font.family, this.italic ? "italic" : "normal", this.font_size, this.line_height, this.letter_spacing);

        html.append ("</style></head><body>\n");

        foreach (var w in font.weights) {
            html.append_printf("""
                <div>
                    <h2 class='weight-label'>Weight %d</h2>
                    <p class='sample-text' style='font-weight: %d;'>%s</p>
                </div>
            """, w, w, display_text);
        }

        html.append ("</body></html>\n");
        return html.str;
    }
}
