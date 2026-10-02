# Scrcpy Desk interface

Native macOS control panel for configuring and starting a scrcpy session. Apply Impeccable's Operate, layout, distill, and clarify guidance to the SwiftUI surface. Keep standard macOS controls and keyboard behavior.

## Task and layout

Select a device, configure the session, and start mirroring. The 184-point sidebar holds Mirror, Audio, Control, and Advanced; Activity and Updates are separated below. A persistent device bar holds selection, refresh, and Wi-Fi connection. The footer keeps session state and Start/Stop visible while settings scroll.

Use aligned settings sections with an 88-point label column and a 24-point gap. Group by purpose with proximity and dividers rather than boxed cards. Quality presets use a native segmented picker. Desktop resolution/density and recording destinations appear only when their option is enabled. Manual Wi-Fi connection and diagnostics use disclosure controls.

The default window is 980 × 760 points; the minimum is 840 × 640. Content has a maximum width of 840 points with 28-point outer padding. Keep the navigation, device bar, and footer fixed. Scroll the settings vertically; logs scroll in both directions.

## Visual rules

- Canvas: RGB 0.065, 0.078, 0.095. Supporting surface: RGB 0.105, 0.122, 0.145.
- Accent: RGB 0.40, 0.88, 0.73, used for active controls and session state. Use orange for warnings and Stop.
- Use the native system font: 22-point page titles, 15-point app name, 13-point labels and actions, 12-point field labels and guidance. Use monospace only for commands, addresses, and logs.
- Use 4-point spacing increments. Section rows have 20-point vertical padding and 12-point gaps within each group.
- Use 6-point corners on navigation selection and code/log surfaces. Standard buttons, switches, menus, segmented controls, focus rings, and disabled states remain native.
- Navigation selection has both a visible background and the accessibility selected trait. Icon-only refresh controls have an accessible label. Form fields have persistent labels.

## Copy

Use literal names: Mirror, Video, Display, Recording, Pair device. Remove slogans, decorative subtitles, preset sales copy, and duplicated descriptions. Keep text only when it explains compatibility, a consequence, a required format, a recovery action, or where to find a setting on the phone.

Retain the generic name **Desktop mode / virtual display**. The phone determines the desktop interface. Never imply a particular vendor interface is guaranteed. Pairing and connection ports differ; make that distinction explicit next to manual connection fields.

## Verification

Inspect every panel and the Wi-Fi sheet in the native app. Check regular and narrow widths, text wrapping, scroll reachability, keyboard focus, accessible labels, option disclosure, and preserved saved settings. Compile both launcher architectures and run the existing core and process integration checks. Impeccable's HTML/CSS detector does not evaluate this native SwiftUI interface.
