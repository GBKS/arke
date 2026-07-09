# Scratch Card Implementation for Recovery Phrase

## Overview
Implemented an iOS-specific scratch-off interaction for revealing recovery phrase words. Users must scratch off a textured overlay to reveal their mnemonic words, similar to a lottery scratch card.

## Implementation Details

### Architecture
- **Option 1** (Components within same file) was chosen
- Platform-specific code using `#if os(iOS)` directives
- macOS continues to use the standard grid display
- Shared `MnemonicGrid` component used by both platforms

### Components Created

#### 1. `MnemonicGrid` (Shared)
- Extracted the original `LazyVGrid` implementation
- Displays mnemonic words in a 2-column grid
- Reusable across both iOS and macOS

#### 2. `ScratchableMnemonicGrid` (iOS only)
- Wraps `MnemonicGrid` with a scratchable overlay
- Manages scratch state and haptic feedback
- Resets on view disappearance

#### 3. `ScratchOverlayView` (iOS only)
- Canvas-based scratch surface
- Uses `destinationOut` blend mode to "erase" the texture
- Displays a texture image that can be scratched away

### Performance Optimizations

1. **Distance-based throttling**: Only adds scratch points when they're at least 3pt apart
   - Reduces point array from 1000+ to ~100-200 points per session

2. **Time-based haptic throttling**: Haptics fire at most once per 0.08 seconds
   - Provides consistent feedback without overwhelming the haptic engine
   - You can adjust `hapticThrottleInterval` constant to fine-tune

### Key Features

- ✅ **One large scratchable surface** covering all words
- ✅ **Haptic feedback** with time-based throttling
- ✅ **"Reveal All" button** for accessibility and convenience
- ✅ **Automatic reset** when navigating away from the view
- ✅ **40pt brush size** (finger-sized)
- ✅ **Platform-specific**: iOS gets scratch card, macOS gets standard grid

### Configuration Constants

Located in `ScratchableMnemonicGrid`:
```swift
private let minPointDistance: CGFloat = 3.0              // Min distance between points (performance)
private let brushSize: CGFloat = 40.0                    // Scratch brush diameter
private let hapticThrottleInterval: TimeInterval = 0.08  // Min time between haptics
```

### State Management

- `revealAllWords`: Controls whether overlay is shown
- `scratchedPoints`: Array of scratched locations (resets on disappear)
- `lastHapticTime`: Tracks last haptic for throttling

### User Flow

1. User taps "Show Recovery Phrase" → mnemonic loads
2. **iOS**: Grid appears with scratch texture overlay
3. User drags finger to scratch → reveals words underneath + haptic feedback
4. User can tap "Reveal All Words" button to skip scratching
5. User navigates away → scratch resets
6. User returns → overlay is back, needs to scratch again

### Next Steps

#### Required: Add Scratch Texture Image
1. Add an image asset named `scratchCardTexture` to your asset catalog
2. Recommended texture ideas:
   - Metallic/foil texture (fits "Arke" gold aesthetic)
   - Noise pattern with gradient
   - Semi-transparent overlay with grain
3. The image will automatically tile/fill the entire grid area

#### Optional Tweaks to Try
- **Haptic intensity**: Currently set to `0.5`, can range from `0.0` to `1.0`
- **Haptic style**: Try `.medium` or `.rigid` instead of `.light`
- **Haptic interval**: Adjust `hapticThrottleInterval` (current: 0.08 seconds)
- **Brush size**: Increase for easier/faster reveal, decrease for more precision
- **Min point distance**: Adjust for smoother/choppier scratch lines

#### Potential Enhancements
- Progress indicator showing % of surface scratched
- Animation when "Reveal All" is tapped
- Particle effects when scratching
- Different brush shapes (not just circles)
- Scratch sound effects
- Tutorial/hint on first use

## Testing Recommendations

1. Test on different screen sizes (iPhone SE, Pro, Pro Max, iPad)
2. Test scratching speed (slow vs fast)
3. Test with accessibility features enabled
4. Verify haptics work on supported devices
5. Confirm reset behavior when navigating away/back
6. Test "Reveal All" button functionality

## Notes

- Haptic feedback only works on devices with Taptic Engine (iPhone 7+)
- The `UIImpactFeedbackGenerator` is prepared on view appear for better performance
- Canvas redraw is efficient due to distance-based point throttling
- Image texture should have good visual contrast with the word grid
