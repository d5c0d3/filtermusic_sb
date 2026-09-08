# Design Specification

## 1. Purpose

This document defines the visual system extracted from the supplied FilterMusic stylesheet.

The implementation is intentionally **presentation-only**.

It is not intended to recreate a radio player, streaming application, station directory, playback system, or related application functionality.

The implementation provides:

- Dark immersive visual styling
- Full-screen wallpaper background
- Dark translucent content surfaces
- Typography and spacing system
- Generic buttons and controls
- Search/input styling
- Cards and content sections
- Accordion styling
- Responsive behavior
- Disabled-state presentation
- Idle wallpaper presentation
- Accessibility-focused focus states
- Reduced-motion support

The only functional behavior included is the wallpaper background presentation.

---

## 2. Design Direction

The visual language should feel:

- Dark
- Minimal
- Immersive
- Modern
- Content-focused
- Slightly cinematic
- High contrast
- Uncluttered

The background image should provide atmosphere without competing with foreground content.

Foreground content uses highly opaque black surfaces so that text remains readable regardless of wallpaper imagery.

---

## 3. Design Tokens

### Colors

| Token | Value | Purpose |
|---|---|---|
| `--color-blue` | `#0079c0` | Primary accent |
| `--color-purple` | `#8d2ba0` | Secondary/accent state |
| `--color-black` | `#000000` | Base background |
| `--color-white` | `#ffffff` | Primary white |
| `--text-color` | `#e6e6e6` | Default text |
| `--card` | `rgba(0, 0, 0, 0.9)` | Content surface |
| `--radius` | `12px` | Main corner radius |
| `--gap` | `2px` | Compact section gap |
| `--max-width` | `520px` | Primary content width |

### Typography

Primary font:

```text
ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
```

Display/headline font:

```text
Montserrat
```

The supplied Montserrat Medium font is expected at:

```text
/assets/fonts/montserrat-v24-latin-500.woff2
```

Fallback formats may also be provided.

---

## 4. Layout

The page uses a full viewport application shell.

```text
body
└── .app
    ├── .wallpaper
    │   ├── .wallpaper-container
    │   └── .wallpaper-cover
    │
    └── .wrapper
        └── main
            └── content
```

The content column has a maximum width of:

```text
520px
```

Desktop content is centered horizontally.

On smaller screens the content uses the available viewport width with reduced padding.

---

## 5. Wallpaper

The wallpaper is fixed to the viewport.

Requirements:

- Full viewport coverage
- Centered background positioning
- Cover sizing
- Initial scale of `1.1`
- Loaded state scales to `1`
- Slow transition after loading
- Dark gradient overlay
- Overlay opacity can be reduced during idle mode

Wallpaper structure:

```html
<div class="wallpaper">
    <div class="wallpaper-container"></div>
    <div class="wallpaper-cover"></div>
</div>
```

The image is supplied through the element's `background-image`.

Example:

```html
<div
    class="wallpaper-container loaded"
    style="background-image: url('/assets/wallpaper.jpg')">
</div>
```

No JavaScript player or application functionality is required.

---

## 6. Content Surfaces

Generic content surfaces use:

```text
background: rgba(0, 0, 0, 0.9)
padding: 16px
margin-bottom: 2px
```

The primary corner radius is:

```text
12px
```

When multiple cards form a continuous vertical group, the spacing remains intentionally small.

This produces the compact stacked-panel appearance of the original design.

---

## 7. Typography

Headings use Montserrat Medium.

### H1

Desktop:

```text
24px
```

Mobile:

```text
20px
```

### H2

Desktop:

```text
20px
```

Mobile:

```text
18px
```

Body copy:

```text
16px
line-height: 1.5
```

Secondary text:

```text
font-weight: 300
opacity: 0.6
```

Headings should use balanced text wrapping where supported.

---

## 8. Buttons

Buttons are circular.

Default:

```text
32 × 32px
```

Small:

```text
24 × 24px
```

Large:

```text
64 × 64px
```

Icons are centered using background images.

Default icon size:

```text
24px
```

Small icon size:

```text
16px
```

Large icon size:

```text
32px
```

Default opacity:

```text
0.8
```

Hover opacity:

```text
1
```

The original player-specific icon files may remain available in the project, but they are not required by this generic implementation.

---

## 9. Generic Inputs

Inputs should retain the dark, understated appearance of the original interface.

Default:

- Transparent background
- Semi-transparent white border
- White text
- Rounded corners
- Compact padding

On focus:

- White border
- Black background
- Visible focus outline

Placeholder text uses reduced opacity.

---

## 10. Accordion

Accordion sections use native HTML `<details>` and `<summary>` elements.

The native disclosure marker is hidden.

A chevron icon is displayed on the right.

When the accordion opens, the chevron rotates 180 degrees.

This preserves the original visual behavior without requiring JavaScript.

---

## 11. Disabled State

Generic disabled content may use:

```text
filter: blur(4px)
pointer-events: none
```

This is a visual presentation state only.

No application-specific redirect or unavailable-radio behavior is implemented.

---

## 12. Idle State

When the page receives:

```text
.user-idle
```

the foreground wrapper may be visually hidden while the wallpaper overlay becomes transparent.

This allows the wallpaper to become the primary visual element.

No inactivity timer is included.

The class can simply be added by an external application if desired.

---

## 13. Responsive Behavior

### Below 768px

- Reduce outer page padding
- Reduce card padding
- H1 becomes 20px
- H2 becomes 18px
- Preserve the 520px maximum width
- Allow content to use the available viewport width

### Below 640px

- Reduce input/card spacing
- Long descriptions may be limited to three lines

---

## 14. Accessibility

Interactive elements should:

- Have accessible labels
- Have visible keyboard focus
- Maintain sufficient contrast
- Use native controls where possible
- Avoid relying solely on hover
- Respect reduced-motion preferences

The wallpaper itself is decorative and should use:

```html
aria-hidden="true"
```

---

## 15. Reduced Motion

When:

```text
prefers-reduced-motion: reduce
```

animations and transitions should be substantially reduced or disabled.

This applies to:

- Wallpaper scaling
- Opacity transitions
- Button transitions
- Accordion transitions
- Loading animations

---

## 16. Suggested Project Structure

```text
/
├── index.html
├── styles.css
├── DESIGN_SPEC.md
│
└── assets/
    ├── fonts/
    │   └── montserrat-v24-latin-500.woff2
    │
    ├── icons/
    │   ├── chevron-down.svg
    │   └── ...
    │
    └── wallpaper.jpg
```

---

## 17. Non-Goals

This implementation does **not** implement:

- Audio playback
- Streaming
- Radio stations
- Station metadata
- Play/pause functionality
- Volume controls
- Favorites
- Sharing
- Sleep timers
- Station filtering logic
- API integration
- Authentication
- User accounts
- Database functionality
- Player state
- Offline radio handling
- Automatic station redirection

The purpose is strictly the **visual design system and presentation layer** extracted from the supplied CSS.
