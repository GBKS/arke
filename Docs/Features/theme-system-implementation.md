# Theme System Implementation Plan

## Overview
Implement a comprehensive theme system for Arké that allows users to switch between different color themes, each supporting both light and dark appearance modes.

## Requirements
- Multiple theme options (Gold, Blue, Purple, Green, Orange, etc.)
- Each theme supports both light and dark appearance modes
- Themes can include custom color palettes AND image assets
- Respects system appearance preference or allows manual override
- Persistent theme selection across app launches
- Minimal changes to existing codebase

## Architecture

### 1. Theme Definition

**AppTheme Enum**
```swift
public enum AppTheme: String, CaseIterable, Codable {
    case gold
    case blue
    case purple
    case green
    case orange

    var displayName: String {
        rawValue.capitalized
    }
}
```

### 2. Theme Manager

**ThemeManager Class**
- Observable object that manages current theme state
- Persists theme selection using AppStorage
- Provides theme-aware color and image resolution
- Injected into environment at app root

**Key Properties:**
- `@AppStorage("selectedTheme") var currentTheme: AppTheme`
- `@Published var currentTheme: AppTheme`

**Key Methods:**
- `func colorName(for semanticColor: String) -> String` - Returns asset name based on current theme
- `func imageName(for semanticImage: String) -> String` - Returns image asset name based on current theme

### 3. Color System

**Asset Naming Convention**
Each color will have variants for each theme:
- `ArkeGreen_Gold` (with Light/Dark appearances in asset catalog)
- `ArkeGreen_Blue` (with Light/Dark appearances in asset catalog)
- `ArkeGreen_Purple` (with Light/Dark appearances in asset catalog)
- etc.

**Existing Colors to Support:**
- gold, gold2, gold3
- green, blue, orange
- red, yellow, purple
- teal, pink, indigo

**Color Extension Updates**
Modify `ColorExtensions.swift` to be theme-aware:
```swift
extension Color {
    public static var arke: ArkeColors.Type { ArkeColors.self }

    @MainActor
    public struct ArkeColors {
        @Environment(\.themeManager) private static var themeManager

        public static var gold: Color {
            Color(themeManager.colorName(for: "ArkeGold"))
        }
        // ... repeat for all colors
    }
}
```

**Alternative Simpler Approach:**
If environment access in static context proves difficult, use a naming function:
```swift
public static func gold(theme: AppTheme) -> Color {
    Color("ArkeGold_\(theme.rawValue.capitalized)")
}
```

### 4. Image System

**Asset Naming Convention**
Images that vary by theme follow similar pattern:
- `logo_Gold` (with Light/Dark variants if needed)
- `logo_Blue`
- `background_Gold`
- `background_Blue`
- etc.

**Image Extension**
Create new `Image` extension for theme-aware images:
```swift
extension Image {
    public static func themed(_ name: String, themeManager: ThemeManager) -> Image {
        Image(themeManager.imageName(for: name))
    }
}
```

### 5. Environment Integration

**Custom Environment Key**
```swift
private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}
```

**App Injection Point**
In main app file (`Ark.swift` or similar):
```swift
@StateObject private var themeManager = ThemeManager.shared

var body: some Scene {
    WindowGroup {
        ContentView()
            .environment(\.themeManager, themeManager)
    }
}
```

## Implementation Phases

### Phase 1: Core Infrastructure
1. Create `ThemeManager.swift` in appropriate location
2. Define `AppTheme` enum with initial theme options
3. Implement basic theme storage with AppStorage
4. Create environment key and value extension

**Files to Create:**
- `ArkeUI/Sources/ArkéUI/Theme/ThemeManager.swift`
- `ArkeUI/Sources/ArkéUI/Theme/AppTheme.swift`

### Phase 2: Color System Update
1. Create theme variants for all existing colors in asset catalog
2. Update `ColorExtensions.swift` to be theme-aware
3. Test color resolution with different themes

**Files to Modify:**
- `ArkeUI/Sources/ArkéUI/Helpers/ColorExtensions.swift`

**Asset Catalogs to Update:**
- Create theme variants for each color (12 colors × N themes = many assets)
- Each asset needs Light/Dark appearance variants

### Phase 3: Image System (Optional)
1. Identify which images should be theme-specific
2. Create theme variants in asset catalog
3. Implement `Image` extension for theme-aware images
4. Update views using themed images

**Files to Create:**
- `ArkeUI/Sources/ArkéUI/Helpers/ImageExtensions.swift` (if needed)

### Phase 4: Settings UI
1. Create theme picker UI component
2. Add to Settings view
3. Implement theme preview functionality
4. Add theme selection to onboarding (optional)

**Files to Create/Modify:**
- `Arké mobile/Views/Settings/ThemeSettingsView_iOS.swift`
- `Arké/Views/Settings/ThemeSettingsView.swift` (macOS)
- Update `SettingsView.swift` to include theme settings

### Phase 5: Migration & Testing
1. Ensure default theme is selected on first launch
2. Test theme persistence across app restarts
3. Test light/dark mode transitions within each theme
4. Test all color references throughout app
5. Performance testing (theme switching should be instant)

## Technical Considerations

### Color Resolution Flow
1. View requests `Color.arke.green`
2. Extension reads `themeManager` from environment
3. ThemeManager returns color name: `"ArkeGreen_Blue"`
4. SwiftUI loads color from asset catalog
5. Asset catalog provides light/dark variant based on `colorScheme`

### Performance
- Color resolution should be cached where possible
- Theme switching triggers view refresh automatically via `@Published`
- Asset catalog handles appearance switching efficiently

### Fallback Strategy
- If themed color asset is missing, fallback to base color name
- Log warning for missing assets during development
- Provide default theme that always works

### Backwards Compatibility
- Existing code using `Color("ArkeGold")` continues to work
- Gradually migrate to `Color.arke.gold` in new code
- Can support both approaches during transition

## File Structure

```
ArkeUI/Sources/ArkéUI/
├── Theme/
│   ├── ThemeManager.swift
│   ├── AppTheme.swift
│   └── ThemeEnvironment.swift
├── Helpers/
│   ├── ColorExtensions.swift (updated)
│   └── ImageExtensions.swift (new)
└── Assets/
    └── (theme-specific color sets)

Arké mobile/Views/Settings/
└── ThemeSettingsView_iOS.swift

Arké/Views/Settings/
└── ThemeSettingsView.swift
```

## Open Questions

1. **Number of Themes**: How many initial themes should we support? Start with 3-5?
2. **Image Scope**: Which images need theme variants? Just logos/backgrounds, or UI icons too?
3. **Default Theme**: Should default be Gold (matching current brand), or user-selected during onboarding?
4. **macOS Support**: Should theme switching work on macOS as well, or iOS-only initially?
5. **Appearance Override**: Should users be able to force light/dark mode, or always follow system?

## Success Criteria

- [ ] User can select theme from Settings
- [ ] Theme persists across app launches
- [ ] All colors update immediately when theme changes
- [ ] Light/Dark mode works correctly for each theme
- [ ] No performance degradation from theme system
- [ ] Existing code continues to work without modification
- [ ] Easy to add new themes in the future

## Future Enhancements

- Custom user-created themes
- Theme preview in settings (live preview of UI)
- Per-wallet theme settings
- Automatic theme based on time of day
- Theme marketplace/sharing
- Gradient/animated themes
- Accessibility themes (high contrast, colorblind-friendly)
