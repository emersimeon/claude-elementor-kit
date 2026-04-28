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

## The widget-vs-HTML decision — DEFAULT TO NATIVE WIDGETS

> 🚨 **CRITICAL ANTI-PATTERN — read this first.**
>
> **Do NOT paste an entire HTML page into one HTML widget.** Do NOT build a homepage that is "1 container with 3 HTML widgets inside." That is not building with Elementor — that is using Elementor as a wrapper around a static webpage. The user **cannot edit it** in the Elementor visual editor, **cannot reuse the design tokens**, and **cannot iterate** on it without going back to source code.
>
> If you find yourself thinking *"I'll just dump this section as HTML, it's faster,"* **STOP.** Break it into native widgets.

### Always default to native widgets

For every section the user wants, build it from native Elementor widgets:

- **Headings** → `add-heading` widget *(supports inline `<em>` for italic emphasis)*
- **Body copy** → `add-text-editor` widget
- **Images** → `add-image` widget *(NOT an `<img>` tag inside an HTML widget)*
- **Buttons / CTAs** → `add-button` widget *(NOT an `<a>` styled as a button)*
- **Layout / spacing** → `add-container` with proper `flex_*` settings *(NOT `<div>`s with CSS flex)*
- **Lists** → `add-icon-list` widget
- **Tabs** → `add-tabs` widget
- **Accordions / FAQs** → `add-accordion` widget
- **Forms** → Fluent Forms shortcode via `add-shortcode` widget
- **Nav menu in headers** → UAE Nav Menu widget *(`uael-nav-menu`)*

### When HTML widget IS allowed *(narrow list — exceptions only)*

Only reach for an HTML widget in these specific cases. **Anything not on this list goes through native widgets.**

1. **Tab/accordion content with rich layout.** `add-tabs` only accepts `tab_content` as a string of HTML, so a multi-card grid inside a tab MUST be HTML. *(But the wrapping Tabs widget itself is still native.)*
2. **Decorative-only flourishes** with no native equivalent — a thin gold rule with a CSS-pseudo-element flourish, an animated underline that grows on hover, a gradient overlay on a child element. **Even then, prefer to pair it with a native widget rather than replacing one.**
3. **Form HTML as a flagged placeholder** when no real form plugin is wired up yet — and you must explicitly tell the user "form is visual only, doesn't capture submissions."
4. **Site-wide CSS overrides** scoped to a specific Elementor element ID *(e.g., styling the tab strip of an `add-tabs` widget that the widget controls don't expose)*. These should be small style blocks, not whole sections of markup.

### What about card grids of 4+ items?

Earlier versions of this skill said "use one HTML widget for card grids — it's faster than 50 widget calls." That advice was wrong because it led to non-editable pages.

**The correct path for card grids:**

- Build the first card with native widgets *(Container → Image → Heading → Text Editor → Button)*
- Use `duplicate-element` to copy it 3+ more times
- Use `update-element` to change the copy/image on each duplicate
- Wrap them in a parent Container with `flex_direction: row` and `flex_wrap: wrap`

This is more widget calls, yes, but the result is a **real Elementor card grid** the user can edit, restyle globally, or reuse as a template.

### Cross-widget styling — `<style>`-only HTML widgets

When you need to style a native widget from outside (e.g., overriding the Tabs widget tab strip styles that the widget controls don't expose), use a **`<style>`-only HTML widget**: it contains ONLY a `<style>` block — no markup, no rendered content. Scope every selector to the parent Elementor element ID:

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

The `f8d1545` is the `element_id` returned when you created the tabs widget. Always grab and remember these IDs — they're the only stable selector across page reloads.

> ⚠️ **An HTML widget used for cross-widget styling MUST contain only `<style>`.** If you find yourself adding HTML markup *(divs, anchors, spans with text content)* alongside the style block, you're falling back into the anti-pattern at the top of this section. Stop. That markup belongs in native widgets.

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

If only HFE (the lighter plugin) is installed without UAE: use the Shortcode widget calling `[wp_nav_menu menu="Main" container=""]` — WordPress's built-in shortcode renders the menu as a real `<ul>` with all the right classes for active-page highlighting and responsive styling.

**Do not** fall back to manually listing the menu items inside an HTML widget — that hard-codes the navigation in two places (the WP menu AND the Elementor template) which means future menu edits won't reflect in the header. Always render the menu through `[wp_nav_menu]` or the UAE widget.

### Footer pattern

Identical post type (`elementor-hf`) but `ehf_template_type = "type_footer"`. Layout is typically a 4-column container (brand block + 3 link columns) on a dark background, with a bottom row containing copyright + social icons.

### Forms — Fluent Forms (the recommended path)

Elementor's native Form widget is Pro. The kit's wizard auto-installs **Fluent Forms** as the free workaround. The flow is split: the user builds the form, then Claude wires it into the page and styles it.

#### The split — what Claude does vs. what the user does

**The user does (manual, ~2-3 min in WP Admin):**

1. **Fluent Forms → New Form** → pick the *Contact Form* template *(pre-built with Name / Email / Subject / Message)* OR start from blank
2. *(optional)* Drag in extra fields — Phone, dropdown, etc.
3. **Save Form** — note the form ID at the top of the page (usually `1` for the first form)
4. **Settings → Email Notifications** → confirm the To address (default: `{admin_email}`)

**Claude does:**

1. Replace any placeholder form (HTML widget) in the contact section with `add-shortcode` widget containing `[fluentform id="<ID>"]`
2. Add a small `<style>` block (in an HTML widget alongside, NOT replacing the shortcode widget) that scopes Fluent Forms styling to match the site's design

#### Wiring the form

```js
// Drop the shortcode widget where the form should appear
mcp__elementor__elementor-mcp-add-shortcode({
  post_id: <page_id>,
  parent_id: <contact_section_container_id>,
  shortcode: '[fluentform id="1"]'
})
```

#### Styling — verified Fluent Forms class structure (Fluent 6.x)

```
.fluentform                            ← outer wrapper
.fluentform_wrapper_<formId>           ← per-form wrapper (e.g. .fluentform_wrapper_1)
  .ff-default                          ← default skin marker
    form.frm-fluent-form
      .ff-el-group                     ← each field block
        .ff-el-input--label            ← label
          label                        ← actual <label> tag
        .ff-el-input--content
          input.ff-el-form-control     ← text inputs
          textarea.ff-el-form-control  ← textareas
      .ff-t-container                  ← two-column row (e.g. first/last name)
        .ff-t-cell                       ← each cell
      .ff_submit_btn_wrapper
        button.ff-btn.ff-btn-submit    ← submit button
      .ff-el-is-required               ← required field marker
```

#### CSS variables (the easiest override path)

Fluent Forms exposes these custom properties on `:root`. **Redefine them on the per-form wrapper to restyle the whole form without specificity battles:**

```css
.fluentform_wrapper_1 {
  --fluentform-primary: #5C1A1B;          /* submit button bg + focus accent */
  --fluentform-secondary: #171615;        /* body text in inputs */
  --fluentform-border-color: #C9C2B3;     /* input borders */
  --fluentform-border-radius: 0px;        /* hairline-square inputs */
}
```

That alone gets you ~80% of the way to a custom design.

#### Full styling pattern (when CSS vars aren't enough)

For the remaining 20% (typography overrides, hairline-only borders, custom button feel), use scoped selectors with the per-form wrapper class. Specificity (0,2,0) matches Fluent's defaults; load order wins because your styles come after.

```css
/* Scope EVERYTHING to .fluentform_wrapper_<id> so you don't bleed into other pages. */

.fluentform_wrapper_1 .ff-el-form-control {
  font-family: 'Inter Tight', sans-serif;
  font-size: 14px;
  border: none;
  border-bottom: 1px solid var(--fluentform-border-color);
  border-radius: 0;
  padding: 14px 0;
  background: transparent;
  color: #171615;
}

.fluentform_wrapper_1 .ff-el-form-control:focus {
  border-bottom-color: #171615;
  box-shadow: none;
}

.fluentform_wrapper_1 textarea.ff-el-form-control {
  font-family: 'Cormorant Garamond', serif;
  font-size: 17px;
  min-height: 100px;
}

.fluentform_wrapper_1 .ff-el-input--label label {
  font-family: 'Inter Tight', sans-serif;
  font-size: 11px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #8A857E;
}

.fluentform_wrapper_1 .ff-btn-submit {
  background: #5C1A1B;
  color: #fff;
  border: 1px solid #5C1A1B;
  border-radius: 0;
  padding: 16px 26px;
  font-family: 'Inter Tight', sans-serif;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.28em;
  text-transform: uppercase;
}

.fluentform_wrapper_1 .ff-btn-submit:hover {
  background: #3F1011;
  border-color: #3F1011;
}

/* Two-column rows — turn into a CSS grid with consistent gap */
.fluentform_wrapper_1 .ff-t-container {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 22px;
}
@media (max-width: 640px) {
  .fluentform_wrapper_1 .ff-t-container {
    grid-template-columns: 1fr;
  }
}

/* Asterisk marker on required fields */
.fluentform_wrapper_1 .ff-el-is-required label::after {
  color: #5C1A1B;
}
```

#### Where to inject the styles

Two options:

1. **Drop an HTML widget right above (or below) the Shortcode widget** with the `<style>` block inside. Wrap selectors in `.fluentform_wrapper_<id>` to keep them scoped. *(Recommended — keeps styles co-located with the form.)*
2. **Add to Customizer → Additional CSS** *(Appearance → Customize)* — site-wide, persists across page rebuilds. *(Better for production sites where the form appears on multiple pages.)*

#### Common gotchas

- **Find the form ID by looking at the form's URL in WP Admin** — `/wp-admin/admin.php?page=fluent_forms&route=editor&form_id=1` → ID is `1`. Or query the DB: `SELECT id, title FROM wp_fluentform_forms`.
- **Do NOT remove the `.ff-default` class** by overriding `class` attributes — Fluent's submit button styling cascades from it.
- **Fluent's CSS loads after page render via `enqueue_scripts`.** If your overrides aren't applying, check that your `<style>` block lives in a widget that renders inside the page body (not the head).
- **Asterisks for required fields** are pseudo-elements (`::after`) — color them via `.ff-el-is-required label::after { color: ... }`, not `color: ...` on the label itself.

### Other form options (when Fluent Forms isn't available)

1. **Contact Form 7** — same shortcode pattern: `[contact-form-7 id="..."]`. Less polished default look, but free and works.
2. **Styled HTML `<form>` with a JS-alert handler** — only as a flagged visual placeholder for early builds. **Tell the user explicitly: "form is visual only — submissions don't go anywhere yet. Wire to Fluent Forms before going live."**

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

When working from a designed HTML mockup, map the source design to Elementor like this:

- **Brand colors** → `update-global-colors`
- **Brand fonts** → `update-global-typography`
- **Section copy** → `add-heading` + `add-text-editor` widgets
- **Card grids (4+ identical items)** → build one card with native widgets, then `duplicate-element` and `update-element` per copy
- **Tabs/accordions** → native `add-tabs`/`add-accordion` widgets *(HTML allowed inside `tab_content` strings only — see anti-pattern section)*
- **Forms** → real Fluent Forms shortcode via `add-shortcode` widget *(see Fluent Forms section)*
- **Headers/footers** → `elementor-hf` post type with UAE Nav Menu widget for nav

> 🚨 **Final reminder:** Default to native widgets. The HTML widget is only for the four narrow cases listed in the anti-pattern section. Never paste a complete page section as raw HTML — the user must be able to edit the result inside Elementor.
