# Elementor MCP — Lessons Learned

The traps we hit on the first build, what they look like, and how the skill + setup script handle them now. Useful when something the automation doesn't cover comes up.

---

## Setup-time gotchas

### 1. The Application Password's *label* is not the username

When you create a WordPress Application Password, you give it a memorable name like "ClaudeMCP". This is a **label**, not a username. The actual username for HTTP Basic auth is your WP login (`admin`, `test`, your email-derived slug, etc.).

**Symptom:** `curl -u "ClaudeMCP:..."` returns `401 Unauthorized`.
**Fix:** `curl -u "<actual-wp-username>:..."` — find via `GET /wp-json/wp/v2/users`.
**The setup script handles this** by listing public users when auth fails so you can pick the right slug.

### 2. Neither MCP plugin is on wordpress.org

Both `mcp-adapter` (WordPress org) and `elementor-mcp` (msrbuilds) ship only via GitHub. The WP REST API's `/wp-json/wp/v2/plugins` endpoint can install plugins by *slug* (from wp.org) but cannot install from arbitrary zip URLs.

**Workaround:** Download zips from GitHub Releases and install via WP-CLI (Local) or upload via WP Admin (live).

### 3. The elementor-mcp source zipball has a hash-suffixed folder

GitHub's auto-generated source zipballs (used when a release has no asset zip) wrap the code in a directory like `msrbuilds-elementor-mcp-b466a1a/`. WordPress uses this folder as the plugin slug — leading to a confused activation and broken paths.

**Fix:** Unzip, rename the folder to `elementor-mcp/`, re-zip. The setup script does this automatically.

### 4. Local-by-Flywheel `wp-config.php` says `DB_HOST=localhost` but uses a per-site Unix socket

The site is fully functional via HTTP, but WP-CLI invoked from a regular shell fails:
```
Error establishing a database connection.
```

**Fix:** Find the socket via:
```bash
find ~/Library/Application\ Support/Local/run -name 'mysqld.sock'
```

Then call PHP with both socket overrides:
```bash
php -d mysqli.default_socket=$SOCK -d pdo_mysql.default_socket=$SOCK <wp-cli> <command>
```

The setup script auto-discovers the right socket by trying each one until `wp core version` succeeds.

### 5. Local has its own bundled PHP and WP-CLI binaries

System-installed PHP/WP-CLI may not have the MySQL extensions Local's stack uses. The setup script uses Local's bundled binaries:

- PHP: `~/Library/Application Support/Local/lightning-services/php-*/bin/darwin-arm64/bin/php`
- WP-CLI: `/Applications/Local.app/Contents/Resources/extraResources/bin/wp-cli/posix/wp`

### 6. Claude Code only reads `.mcp.json` at startup

Writing the file mid-session does nothing. You must quit and reopen Claude Code in the project directory.

### 7. The `detect-elementor-version` MCP tool errors in v1.5.0

It tries to return `null` for `elementor_pro_version` but the schema declares `string`. Calling it returns a validation error. **Use `list-pages` as the smoke-test** for whether the MCP is wired correctly.

---

## Build-time conventions

### 1. Widget add-tools take flat params, not `settings: {}`

```js
// ✓ Correct
add-heading({
  post_id: 11,
  parent_id: "abc",
  title: "...",
  title_color: "#171615",
  typography_font_family: "Cormorant Garamond"
})

// ✗ Wrong — error: "title is a required property of input"
add-heading({
  post_id: 11,
  parent_id: "abc",
  settings: { title: "...", title_color: "#171615" }
})
```

**The exception** is `add-container`, which takes `settings: {}` because containers have so many properties. Don't generalize from one to the other.

### 2. Always set `typography_typography: "custom"` to enable typography

Without this flag, the other `typography_*` keys are silently ignored. Same for `css_filters_css_filter: "custom"` for image filters. This pattern is how Elementor distinguishes "use defaults" from "I'm explicitly setting this."

### 3. Flex container key names

The schema confirms (and issue #32 was a bug about this) that the right keys are:

- `flex_direction` — `row` | `column` | `row-reverse` | `column-reverse`
- `flex_justify_content` — `flex-start` | `center` | `flex-end` | `space-between` | `space-around` | `space-evenly`
- `flex_align_items` — `flex-start` | `center` | `flex-end` | `stretch`
- `flex_gap` — `{column, row, isLinked, unit}`
- `flex_wrap` — `nowrap` | `wrap`

Note the `flex_` prefix on `justify_content` and `align_items` — without it, the keys are dropped.

### 4. Background type must be set first

Setting `background_color: "#F4F1EA"` alone does nothing. You must first set:
```
background_background: "classic"
```
Then `background_color`, `background_image`, etc. apply. Same for `background_overlay_background: "classic"` before any `background_overlay_*` keys.

### 5. Background overlay opacity unit is `px` (yes, really)

Schema quirk:
```js
background_overlay_opacity: { unit: "px", size: 0.45 }   // 0–1 range
```
The `px` unit doesn't mean pixels — it's just what the schema declares. The numeric range is 0–1.

### 6. Italic emphasis via inline `<em>` in headings

Elementor's Heading widget renders inline HTML in the title field. So:

```js
title: "where estates <em>are entrusted</em>"
```

Cormorant Garamond's italic auto-loads if the font is set. If italics fail to render, check that **Site Settings → Global Fonts → Primary** has an italic variant available (Cormorant Garamond from Google Fonts ships italic by default).

### 7. Padding shape

```js
padding: {
  unit: "px",
  top: "200",
  right: "56",
  bottom: "200",
  left: "56",
  isLinked: false
}
```

`isLinked: true` means top=right=bottom=left (Elementor's "linked" UI control). Use `false` whenever any side differs.

---

## Layout decision: native widgets vs HTML widget

This is the single biggest productivity lever.

### Use native widgets when

- It's a one-off heading, image, button, text block
- The user will edit copy in Elementor's visual editor
- The widget maps 1:1 to the design (Heading for headings, Image for images, Button for buttons)

### Drop into a single HTML widget when

- **Card grid** (4+ identical cards) — saves dozens of widget calls and keeps spacing consistent
- **Content inside Tabs/Accordion** — `add-tabs` only takes `tab_content` as HTML strings, so any rich card grid inside a tab *must* be HTML
- **Complex hover effects** — image scale on hover inside a parent `<a>`, animated underline expanding on hover, gradient overlay reveal — these aren't exposed by widget controls
- **CSS pseudo-elements** (`::before`, `::after`) for decorative dividers, arrows, frames
- **CSS Grid layouts** with media queries — Elementor's built-in container is flex-only on the free tier
- **Scoped style block** styling many child elements consistently (form fields, listing cards, neighborhood tiles)

### Mixing the two

When you need to style a native widget from an HTML widget elsewhere, scope styles to the parent Elementor element ID:

```html
<style>
.elementor-element-f8d1545 .elementor-tab-title {
  text-transform: uppercase !important;
  letter-spacing: .26em !important;
}
.elementor-element-f8d1545 .elementor-tab-title.elementor-active {
  border-bottom-color: #171615 !important;
}
</style>
```

The `f8d1545` is the `element_id` returned when the widget was created. Always grab and remember these IDs — they're the only stable selector.

---

## Forms (free Elementor)

Elementor's Form widget is **Pro**. The free path:

1. Build the form in **Fluent Forms** (or WPForms / CF7) — these have free plans
2. Get the shortcode (e.g., `[fluentform id="1"]`)
3. Drop it via Elementor's `add-shortcode` widget

If you're at the visual-build stage and forms aren't wired yet, an HTML `<form>` with a JS-alert handler is fine as a placeholder. **Flag it explicitly to the user** as "form is visual only — doesn't capture submissions yet."

---

## Header / Footer (free Elementor)

Theme Builder is **Pro**. The free path uses **Header Footer Elementor (HFE)** by Brainstorm Force or UAE:

1. Install + activate HFE
2. **WP Admin → Header Footer Builder → Add New** → set Type: Header (or Footer), Display On: Entire Website
3. Edit with Elementor — the MCP can edit this template the same way it edits any page (find its post_id via `list-pages({post_type: "elementor-hf"})`)

For a transparent header that swaps to solid on scroll: **Pro Sticky / Motion Effects only.** Free workaround is either keep it solid throughout, or hand-write a small CSS snippet via Customizer → Additional CSS.

---

## What the MCP cannot do (set expectations early)

- Install plugins or themes (use WP-CLI or WP Admin)
- Set the static front page (use `wp option update show_on_front page; wp option update page_on_front <id>`)
- Pixel-perfect HTML→Elementor translation — Elementor's flexbox container model is the ceiling
- Drive Pro features (Theme Builder, Loop Grid, Form widget, Sticky/Motion Effects, Popup, Display Conditions, Custom CSS per element)
- Auto-fix broken layouts — you read the rendered output and emit corrective `update-element` calls

---

## When something looks wrong on the rendered page

1. `get-page-structure({post_id})` — confirms what's nested in what
2. `get-element-settings({element_id})` — shows the actual settings written to the DB
3. `curl <site-url>` and grep for your custom classes — confirms the page is actually rendering your widgets
4. View source in browser — Elementor wraps every widget in `.elementor-element.elementor-element-<id>` so you can find any element by its ID

---

## Reading list (what helped me get this right)

- [elementor-mcp source](https://github.com/msrbuilds/elementor-mcp) — `includes/abilities/class-*-abilities.php` files are the ground truth on each tool's behavior
- [WordPress MCP Adapter](https://github.com/WordPress/mcp-adapter) — explains the JSON-RPC plumbing and auth options
- [Elementor's `_elementor_data` post meta format](https://developers.elementor.com/docs/getting-started/elementor-data/) — every page is one giant nested JSON tree in this meta key. The MCP reads/writes this directly.
- The [container schema dump](#) — `get-container-schema()` returns ~50KB of JSON Schema. Read once at session start; bookmark the keys.
