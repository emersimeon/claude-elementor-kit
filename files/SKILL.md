---
name: elementor-mcp
description: Build, debug, or extend a WordPress + Elementor site through the elementor-mcp MCP server. Use when the user references the Elementor MCP, wants to programmatically build/edit Elementor pages on a local or live WordPress site, asks to "set up Elementor MCP" against a Local-by-Flywheel site or live host, or invokes elementor-mcp tools (`mcp__elementor__elementor-mcp-*`). Also covers initial install of the MCP Adapter + elementor-mcp plugins, app-password auth wiring, schema-loading discipline, and the widget-vs-HTML decision tree. SKIP for Bricks, Divi, Beaver Builder, or non-Elementor WordPress builds.
---

# Elementor MCP Build Skill

You are operating against a WordPress site with the **elementor-mcp** server (`https://github.com/msrbuilds/elementor-mcp`) connected via the WordPress MCP Adapter. This skill captures everything I learned the hard way the first time through, so subsequent sessions start at expertise level.

## When this skill applies

- The user mentions Elementor MCP, says "build with the Elementor MCP", or asks to set it up
- A `.mcp.json` in the project registers an MCP server pointing at `wp-json/mcp/elementor-mcp-server`
- The user asks to programmatically scaffold an Elementor homepage/page on a local-by-flywheel or live host
- Tools beginning with `mcp__elementor__elementor-mcp-*` are available

## First-session setup (when MCP not yet connected)

If the user has a WordPress site but no `.mcp.json` and no `elementor` MCP loaded:

1. **Check whether they're using Local-by-Flywheel or a live host.** Setup paths differ.
2. **Run the bundled setup script** at `~/.claude/scripts/setup-elementor-mcp.sh` — it handles plugin install, auth wiring, and `.mcp.json` generation interactively for both flavors.
   ```bash
   bash ~/.claude/scripts/setup-elementor-mcp.sh
   ```
3. After the script completes, instruct the user to **quit and reopen Claude Code in the project directory** so the new `.mcp.json` is picked up.
4. On reopen, the deferred MCP tools will be exposed via ToolSearch — load the ones you need with `select:` queries.

If something fails, see "Setup gotchas" below.

## Working session conventions

### Always do this first

```
mcp__elementor__elementor-mcp-list-pages   # confirms auth + lists existing pages
mcp__elementor__elementor-mcp-get-global-settings   # see existing colors/fonts kit
mcp__elementor__elementor-mcp-get-container-schema  # ground truth on flex_* key names
```

The container schema is large (~50KB). Read it once, then write down the keys you'll use in your reply text so you don't need to re-fetch it. Critical keys:

- `flex_direction`, `flex_justify_content`, `flex_align_items`, `flex_gap`, `flex_wrap` — note the **`flex_` prefix** on justify/align (issue #32 was about these being written under wrong keys in older versions)
- `content_width: "boxed"|"full"` + `boxed_width: {unit, size, sizes}`
- `min_height: {unit, size, sizes}` — use unit `vh` for full-screen heroes
- `padding`/`margin: {unit, top, right, bottom, left, isLinked}` — `isLinked: false` when sides differ
- `background_background: "classic"|"gradient"|"video"` — must be set first or other background_* keys are ignored
- `background_overlay_*` — separate parallel set for overlays. `background_overlay_opacity: {unit:"px", size: 0.5}` (yes, the unit is `px` even for opacity — quirk of the schema)

### Widget call convention — flat params, NOT nested in `settings`

This bit me hard the first time. The `add-*` shortcut tools take their settings as **top-level parameters**, not inside a `settings: {}` object:

```js
// ✓ CORRECT
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11,
  parent_id: "abc123",
  title: "where estates <em>are entrusted</em>",
  header_size: "h1",
  title_color: "#FFFFFF",
  typography_typography: "custom",       // ← required to enable typography
  typography_font_family: "Cormorant Garamond",
  typography_font_size: {size: 110, unit: "px"},
  typography_font_weight: "300",
  typography_line_height: {size: 0.98, unit: "em"},
})

// ✗ WRONG — silently fails or returns "title is required"
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11,
  parent_id: "abc123",
  settings: {title: "...", typography_font_family: "..."}
})
```

`add-container` is the **exception** — it takes a `settings: {}` object. Don't generalize from one to the other.

### Always set `typography_typography: "custom"`

Without this, the other typography_* keys are ignored. Same applies to `css_filters_css_filter: "custom"` for image filters, etc. — these "enable" flags are how Elementor knows you want to override defaults.

### Italic emphasis pattern

Display headings often need a single italic-emphasized word. Don't use a separate widget — just inline `<em>` in the title:

```js
title: "A <em>quiet</em> practice for an <em>uncommon</em> clientele."
```

Cormorant Garamond and most luxury serifs have italic variants that auto-load when `<em>` appears. Confirm via the rendered page; if italics fail, the global typography needs the italic variant explicitly enabled.

## The widget-vs-HTML decision tree

The MCP exposes ~30 free-Elementor widgets, but some patterns are **much cleaner as a single styled HTML widget** than as 50+ nested containers:

**Use native Elementor widgets when:**
- It's a one-off heading, image, button, or text block
- The user will want to edit copy in the Elementor visual editor later
- The widget maps 1:1 to a design element (Heading widget for headings, Image for images)

**Drop into a single HTML widget when:**
- You're building a **card grid** (4+ identical cards) — saves dozens of widget calls
- Content lives **inside Tabs/Accordion** — `add-tabs` only accepts `tab_content` as HTML strings, so any rich card grid inside a tab *must* be HTML
- You need **CSS pseudo-elements** (`::before`, `::after`), **CSS Grid**, **gradient overlays on a child**, or **hover scale on an image inside an `<a>`** — these aren't exposed by Elementor widget controls
- You need a **scoped style block** that styles multiple elements consistently (form fields, listing cards)

**Scope HTML widget styles to avoid leaking** by either:
- Wrapping in a unique class: `.mv-listings .mv-card { ... }`
- Targeting the parent Elementor element ID: `.elementor-element-<id> .mv-card { ... }`

### When mixing native widgets and HTML

If you need to style a native widget from an HTML block elsewhere on the page (e.g., styling the Tabs widget tab strip), use the parent Elementor element ID selector pattern:

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

The `f8d1545` is the `element_id` returned when you created the tabs widget. Always grab and remember these IDs.

## Building order

For a new page, build top-down section by section, in small commits, verifying after each:

1. `update-global-colors` + `update-global-typography` — establish design tokens
2. `create-page({title, status: "publish", template: "elementor_canvas"})` — Canvas template removes theme header/footer chrome so your design is the only thing on the page
3. (Via WP-CLI) Set as static front page: `wp option update show_on_front page; wp option update page_on_front <id>`
4. Build sections — outer container → inner content container (boxed, max-width 1360px-ish) → content
5. After each section: `get-page-structure(post_id)` to verify nesting, or just curl the front page
6. **Pause for human review** before building header/footer (which use Header Footer Elementor templates, a different flow)

## Header/Footer notes

The MCP plugin's `create-theme-template` tool requires **Elementor Pro**. With Elementor Free, headers and footers are built using **Ultimate Addons for Elementor (UAE)** by Brainstorm Force (the kit's setup wizard auto-installs this; alternatively the lighter **Header Footer Elementor (HFE)** plugin from the same company also works — both share the same `elementor-hf` post type).

### Building a site-wide header

1. **Create the WordPress menu first.** Tell the user to go to WP Admin → Appearance → Menus, name it (e.g. "Main"), add the pages they want, and save. The MCP cannot create WP nav menus directly — this step is a one-minute manual action.

2. **Create the header template post.** Use `create-page` with `post_type: "elementor-hf"` and a title like "Site Header". Then set the following post meta via WP-CLI or the `update-element` flow:
   - `ehf_template_type` = `"type_header"` (or `"type_footer"` for footers)
   - `display-on-canvas` = `"yes"` (displays site-wide; alternative meta keys like `ehf_target_include_locations` may apply for narrower scopes)

3. **Build the layout.** A row container with three children:
   - **Left:** logo (Heading widget with brand name in display serif, OR `Site Logo` widget if UAE is installed)
   - **Center:** **UAE Nav Menu widget** (`uael-nav-menu`) pointed at the WordPress menu by name. UAE's nav menu widget is **free** and handles mobile hamburger, dropdowns, hover states, active-page highlighting automatically — much cleaner than rendering nav as raw HTML.
   - **Right:** Button widget with "Contact" or "Get In Touch" CTA

4. **Verify display.** After building, instruct the user to check WP Admin → Appearance → Header Footer Builder → confirm the Display On rule is set to "Entire Website."

### When UAE Nav Menu isn't available

If only HFE (the lighter plugin) is installed without UAE: render the menu via Shortcode widget calling `[wp_nav_menu menu="Main"]`, OR fall back to a styled HTML widget that lists the links manually. The UAE Nav Menu widget is strongly preferred because it handles responsive behavior automatically.

### Footer pattern

Identical post type (`elementor-hf`) but `ehf_template_type = "type_footer"`. Layout is typically a 4-column container (brand block + 3 link columns) on a dark background, with a bottom row containing copyright + social icons.

### Forms

Elementor's Form widget is Pro. Free workarounds, in order of preference:

1. **Fluent Forms** (recommended; the kit's wizard offers to auto-install it) — build form in Fluent Forms → grab its shortcode like `[fluentform id="1"]` → drop in via Elementor's `add-shortcode` widget
2. **Contact Form 7** — same shortcode pattern
3. **Styled HTML `<form>` with a JS-alert handler** — only as a visual placeholder for early builds. **Flag it explicitly** to the user as "form is visual only — submissions don't go anywhere yet."

## Setup gotchas (what bit me last time)

- **The application password's *label* is not the username.** A user creates an Application Password and gives it a name like "Claude MCP", but the actual WP username remains `admin` or `test` or whatever they set up. If `curl -u "ClaudeMCP:..."` returns 401, try `curl -u "admin:..."` or check `GET /wp-json/wp/v2/users` to find the real slug.
- **Local-by-Flywheel `wp-config.php` says `DB_HOST=localhost`** but the real MySQL is on a per-site Unix socket. WP-CLI fails with "Error establishing a database connection" until you pass `-d mysqli.default_socket=/path/to/mysqld.sock`. The setup script handles this; if doing it manually, find the socket via `find ~/Library/Application\ Support/Local/run -name mysqld.sock`.
- **Neither MCP plugin is on wordpress.org.** Cannot install via REST API by slug — must download zips from GitHub Releases.
- **The elementor-mcp release zipball has an ugly auto-generated folder name** (`msrbuilds-elementor-mcp-<sha>/`). WordPress uses the folder name as the plugin slug. Repack with a clean `elementor-mcp/` folder before installing.
- **Claude Code only loads `.mcp.json` at startup** — after writing one, the user must quit and reopen.
- **The `detect-elementor-version` tool errors with a schema validation bug** in v1.5.0 (`elementor_pro_version` is null but schema says string). Don't rely on it; use `list-pages` for the auth-works check instead.

## Live-host vs Local differences

**Local-by-Flywheel:** Plugin install via the bundled WP-CLI binary at `/Applications/Local.app/Contents/Resources/extraResources/bin/wp-cli/posix/wp` with PHP at `~/Library/Application Support/Local/lightning-services/php-*/bin/darwin-arm64/bin/php` and the per-site MySQL socket. The setup script automates all of this.

**Live host (cPanel/Cloudways/Kinsta/etc.):** Plugin install via WP Admin → Plugins → Add New → Upload Plugin (manual upload of the two zips). Auth is the same — REST API + Application Password. **MCP URL** changes to `https://<live-domain>/wp-json/mcp/elementor-mcp-server`. **Important:** if the live site is HTTPS (it should be), make sure curl/Claude Code can reach it from your local machine — some hosts block non-browser User-Agents on `/wp-json/`. The setup script's "live" path tests this with a single curl before writing `.mcp.json`.

## Tool-loading discipline

The MCP exposes ~75 deferred tools. Don't load them all at once — fetch schemas lazily as you build:

- **First call:** `list-pages` (no schema needed — pre-loaded by ToolSearch when triggered)
- **Before building containers:** load `get-container-schema`, `add-container`, `update-container`
- **Before placing widgets:** load `add-heading`, `add-text-editor`, `add-button`, `add-image`, `add-html` in one batch
- **Before specific widgets:** load `add-tabs`, `add-icon-list`, `add-divider`, `add-spacer` as needed

Use `ToolSearch` query format `select:tool1,tool2,tool3` to load multiple in one call.

## What the MCP **cannot** do (set expectations)

- Install plugins or themes (use WP-CLI or WP Admin instead)
- Set the static front page (use `wp option update`)
- Build a custom header/footer on Elementor Free without the HFE plugin
- Auto-translate arbitrary HTML/CSS into Elementor widgets — you read the source design and emit widget calls
- Pixel-perfect parity with hand-coded HTML — Elementor's flexbox container model is the ceiling

## Quick reference — the build flow that works

```
1. setup-elementor-mcp.sh          # one-time, ~3 minutes
2. Quit + reopen Claude Code       # picks up .mcp.json
3. list-pages                      # confirm auth
4. get-global-settings             # see current kit
5. update-global-colors + typography
6. create-page (Elementor Canvas template)
7. Set as front page via WP-CLI
8. Build sections top-down, one at a time
9. After each: get-page-structure or curl the front page
10. Pause for human review before header/footer
```

When working from a designed HTML mockup, keep `config.js`-style design tokens in mind: brand colors → global colors; brand fonts → global typography; section copy → heading/text-editor widgets; card grids → HTML widgets; tabs/accordions → native widgets with HTML in their content slots.
