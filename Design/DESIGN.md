---
name: Lumina Darkroom
colors:
  surface: '#0c1324'
  surface-dim: '#0c1324'
  surface-bright: '#33394c'
  surface-container-lowest: '#070d1f'
  surface-container-low: '#151b2d'
  surface-container: '#191f31'
  surface-container-high: '#23293c'
  surface-container-highest: '#2e3447'
  on-surface: '#dce1fb'
  on-surface-variant: '#bbcabf'
  inverse-surface: '#dce1fb'
  inverse-on-surface: '#2a3043'
  outline: '#86948a'
  outline-variant: '#3c4a42'
  surface-tint: '#4edea3'
  primary: '#4edea3'
  on-primary: '#003824'
  primary-container: '#10b981'
  on-primary-container: '#00422b'
  inverse-primary: '#006c49'
  secondary: '#bec6e0'
  on-secondary: '#283044'
  secondary-container: '#3f465c'
  on-secondary-container: '#adb4ce'
  tertiary: '#b9c7e0'
  on-tertiary: '#233144'
  tertiary-container: '#95a4bb'
  on-tertiary-container: '#2c3a4e'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ffbbe'
  primary-fixed-dim: '#4edea3'
  on-primary-fixed: '#002113'
  on-primary-fixed-variant: '#005236'
  secondary-fixed: '#dae2fd'
  secondary-fixed-dim: '#bec6e0'
  on-secondary-fixed: '#131b2e'
  on-secondary-fixed-variant: '#3f465c'
  tertiary-fixed: '#d5e3fd'
  tertiary-fixed-dim: '#b9c7e0'
  on-tertiary-fixed: '#0d1c2f'
  on-tertiary-fixed-variant: '#3a485c'
  background: '#0c1324'
  on-background: '#dce1fb'
  surface-variant: '#2e3447'
typography:
  headline-lg:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Manrope
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Hanken Grotesk
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-numeric:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-caps:
    fontFamily: Hanken Grotesk
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.1em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  margin-main: 1rem
  gutter-tool: 0.75rem
  pad-xs: 0.25rem
  pad-sm: 0.5rem
  pad-md: 1rem
  control-height: 3rem
---

## Brand & Style

The brand personality is professional, precise, and utilitarian, designed for power users who require a focused environment for creative output. The aesthetic centers on a **Modern Minimalist** approach with a heavy emphasis on **Dark Mode** to minimize eye strain and maximize color accuracy for photo editing.

By utilizing deep charcoal surfaces and high-contrast emerald accents, the design system establishes a clear visual hierarchy that guides the user through complex adjustment pipelines without distraction. The style is defined by sleek, rounded controls that feel ergonomic on mobile devices, paired with a structured, technical precision in its data readouts.

The emotional response should be one of "Expert Control." Users should feel they are using a high-fidelity tool that is both approachable for quick edits and deep enough for professional RAW processing.

## Colors

The palette is anchored in a true-dark spectrum to provide the maximum "pop" for the image being edited. 

- **Primary (Emerald):** Used exclusively for active states, primary action buttons, and successful completion indicators. It provides a vibrant contrast against the dark background.
- **Secondary (Deep Navy/Charcoal):** Applied to floating panels, sheets, and modal containers to create subtle separation from the canvas.
- **Tertiary (Slate):** Reserved for inactive icons, secondary controls, and structural borders.
- **Neutral (Black/Obsidian):** The foundation of the canvas area, ensuring the interface disappears behind the user's content.

Text colors follow a strict hierarchy: `Pure White` for primary headings, `Slate 200` for body text, and `Slate 500` for disabled or supplementary labels.

## Typography

Typography focuses on legibility and technical clarity. We utilize a three-font approach:

1.  **Manrope (Headlines):** A balanced, modern sans-serif for section titles and primary navigation.
2.  **Hanken Grotesk (UI/Body):** A clean, versatile font used for all interface labels, buttons, and descriptive text.
3.  **JetBrains Mono (Technical):** Used specifically for numerical values (e.g., ISO, shutter speed, coordinate values) to ensure characters remain distinct and vertically aligned in shifting sliders.

All headline-level text is optimized for mobile by keeping sizes under 32px, ensuring that controls remain visible even when tool panels are expanded.

## Layout & Spacing

The layout is a **Fluid Grid** model optimized for the vertical orientation of mobile photography. 

- **The Canvas:** A central, protected safe area for the image preview. 
- **The Bottom Toolbar:** A persistent, horizontally-scrolling icon bar for top-level tool categories.
- **Floating Sheets:** Tool controls (sliders, adjustment layers) appear in bottom-anchored sheets with a maximum height of 40% of the viewport to keep the image visible.
- **Rhythm:** An 8px grid system governs all spacing. Vertical stacks of sliders use a 12px gutter to ensure touch targets are accessible without cluttering the view.

## Elevation & Depth

Visual hierarchy is achieved through **Tonal Layers** rather than heavy shadows, maintaining a sleek, modern feel.

- **Level 0 (Base):** Pure black (#020617). The foundation layer for the image canvas.
- **Level 1 (Panels):** Deep Slate (#0F172A). Applied to the main bottom bar and expanded tool sheets.
- **Level 2 (In-Panel Controls):** Lighter Slate (#1E293B). Used for secondary buttons and segmented controls within sheets.
- **Backdrop Blurs:** When a tool sheet is active, a 20px Gaussian blur is applied to the area behind the sheet handle to suggest depth and focus.

## Shapes

The system uses a **Rounded** language to feel ergonomic and friendly to thumb gestures. 

- **Primary Surface:** Tool sheets and modals utilize `rounded-xl` (1.5rem) on top corners to soften the transition from the canvas.
- **Buttons & Chips:** Standard buttons use `rounded-lg` (1rem) for a pill-like appearance that clearly indicates interactivity.
- **Sliders:** Slider tracks are thin with `rounded-full` caps, while the thumb handle is a larger, tactile circle to ensure precise manipulation.

## Components

### Buttons & Chips
- **Primary Button:** Solid Emerald background with Obsidian text. Used for "Export" or "Apply."
- **Secondary Button:** Ghost style with a Slate border and white text.
- **Filter Chips:** Horizontally scrolling, rounded rectangles. Active chips feature a subtle Emerald glow and an 80% opacity fill.

### Sliders (The Core Component)
- **Track:** A 4px height line in Slate.
- **Active Track:** Filled with Emerald from the center-point (for bipolar adjustments like Contrast) or from the left (for unipolar like Brightness).
- **Thumb:** A 24px white circle for high visibility against dark backgrounds.
- **Numeric Readout:** Placed at the top-right of the slider using the monospaced font.

### Lists & Layers
- **Layer Items:** Flat rows with a leading thumbnail. Selection is indicated by a vertical Emerald bar on the left edge rather than a full-row color change.
- **Checkboxes:** Rounded squares that fill with Emerald and a white checkmark when active.

### Input Fields
- Understated style with a bottom-only border in Slate. When focused, the border transitions to Emerald with a 2px thickness.