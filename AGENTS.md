# BabylonFish - Agent Guidelines

This document provides guidelines for AI agents working on BabylonFish - a macOS keyboard layout auto-switching application.

## Project Overview

BabylonFish automatically detects and switches keyboard layouts when users type in the wrong language. Features:
- Automatic layout switching (e.g., "ghbdtn" → "привет")
- Double Shift shortcut for manual correction
- Context-aware processing (ignores password fields)
- Typo correction and auto-completion (v3)

## Build Commands

### Development Build
```bash
# Build BabylonFish2 (legacy)
swift build --product BabylonFish2

# Build BabylonFish3 (current)
swift build --product BabylonFish3

# Build for specific architecture
swift build -c debug --product BabylonFish3 --arch arm64
swift build -c debug --product BabylonFish3 --arch x86_64
```

### Release Build
```bash
# Build and install universal binary
./install_app.sh

# Manual build for both architectures
swift build -c release --product BabylonFish3 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish3 --disable-sandbox

# Create universal binary
lipo -create -output "BabylonFish" \
  ".build/arm64-apple-macosx/release/BabylonFish3" \
  ".build/x86_64-apple-macosx/release/BabylonFish3"
```

### Package Management
```bash
# Update dependencies
swift package update

# Clean build
rm -rf .build
```

## Testing Commands

### Manual Testing
```bash
# Run the application
./run_app.sh
# Or directly
open ~/Applications/BabylonFish.app

# Check debug logs
tail -f ~/babylonfish_debug.log
# Clear debug logs
> ~/babylonfish_debug.log
```

### Test Scripts
```bash
# Run BabylonFish3 test suite
./test_babylonfish3.sh

# Test contextual processing
swift test_contextual.swift
```

### Testing Scenarios
1. **Simple word detection**: Type "ghbdtn" (English) → "привет" (Russian)
2. **Short word detection**: Type "rfr" → "как"
3. **Double Shift**: Select text, double-tap Left Shift
4. **Context awareness**: Should ignore password fields
5. **Typo correction**: "havv" → "have" (v3 only)
6. **Auto-completion**: Partial words (v3 only)

### Debug Log Analysis
Check `~/babylonfish_debug.log` for:
- `Event received: type=10` - Events captured
- `Language detected:` - Language detection working
- `Switching layout to...` - Layout switching attempted
- `Found matching source:` - Layout source found
- `Context check:` - Context analysis results

## Code Style Guidelines

### File Organization
```
Sources/BabylonFish2/
├── Core/           # Core engine components
├── Language/       # Language detection and processing
├── Configuration/  # App configuration and state
├── UI/            # User interface components
└── Utils/         # Utility classes and helpers
```

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `EventProcessor`, `LanguageDetector`)
- **Structs**: `PascalCase` (e.g., `AppConfig`, `KeyCombo`)
- **Enums**: `PascalCase` with cases in `camelCase` (e.g., `Language.english`, `Language.russian`)
- **Variables**: `camelCase` (e.g., `currentBuffer`, `isEnabled`)
- **Constants**: `camelCase` or `UPPER_SNAKE_CASE` for global constants
- **Functions**: `camelCase` (e.g., `detectLanguage()`, `switchLayout()`)

### Import Order
```swift
// 1. Foundation and system frameworks
import Foundation
import Cocoa
import Carbon

// 2. Third-party dependencies (none currently)

// 3. Local modules (if any)
```

### Type Annotations
- Always specify return types for functions
- Use explicit type annotations for public API
- Prefer `let` over `var` for immutable values
- Use optionals appropriately with `?` and `!` only when safe

### Error Handling
```swift
// Use do-catch for recoverable errors
do {
    try someOperation()
} catch {
    logDebug("Error: \(error)")
}

// Use optional binding for expected failures
guard let result = try? operation() else {
    return
}

// Log errors to debug log
logDebug("Error description")
```

### Logging
- Use `logDebug()` function for all debug logging
- Logs go to `~/babylonfish_debug.log`
- Include timestamps and context in log messages
- Use descriptive messages that help with debugging

### Swift Conventions
- Use Swift's modern concurrency (`async/await`) when appropriate
- Prefer value types (structs) over reference types (classes) when possible
- Use protocols for abstraction
- Follow Swift API Design Guidelines

### Memory Management
- Use `weak` references for delegates to avoid retain cycles
- Properly handle `Unmanaged` types when working with Core Foundation
- Clean up resources in `deinit` when necessary

## Architecture Notes

### Event Processing Flow
```
CGEvent → EventTapManager → EventProcessor → BufferManager
                                      ↓
                            ContextAnalyzer (context check)
                                      ↓
                            LanguageDetector (language detection)
                                      ↓
                            LayoutSwitcher (switch + retype)
```

### Configuration
- Use `AppConfig` struct for Codable configuration
- Migrate from UserDefaults to structured config
- Support backward compatibility for user settings

### Performance Requirements
- Event processing must be fast (< 1ms)
- Language detection should be efficient
- Memory usage should be minimal
- Avoid blocking the main thread

### Security Requirements
- Never log sensitive information (passwords, etc.)
- Respect privacy - don't send data externally
- Handle permissions appropriately
- Validate all inputs and configurations

## Agent Operations

### Before Making Changes
1. **Always run tests**: Use `./test_babylonfish3.sh` or manual testing
2. **Check logs**: Verify `~/babylonfish_debug.log` for errors
3. **Build verification**: Run `./install_app.sh` to ensure build works

### Code Quality Checks
- **No linting tools**: This project doesn't use SwiftLint or other linters
- **Manual verification**: Check code follows existing patterns
- **Performance**: Event processing must remain under 1ms

### Testing Requirements
- **Unit tests**: Not currently implemented; focus on manual testing
- **Integration tests**: Use `test_contextual.swift` for contextual processing
- **Manual testing**: Always test typing scenarios before committing

### Common Pitfalls
1. **Permissions**: App needs Accessibility + Input Monitoring permissions
2. **Event capture**: Verify events are received in debug logs
3. **Layout switching**: Ensure Russian/English layouts are installed
4. **Memory leaks**: Check for retain cycles in delegates

### Quick Reference
```bash
# Build and test
./install_app.sh
./test_babylonfish3.sh
tail -f ~/babylonfish_debug.log

# Reset if needed
tccutil reset Accessibility com.babylonfish.app
> ~/babylonfish_debug.log
```

## Recent Development Progress

### Current Version: 3.0.40
**Date**: 12.02.2026  
**Status**: Stable build with post-switch context tracking

### Problem Solved: Post-Correction Gibberish Issue
**Scenario**: User types "ghbdtn!" → BabylonFish correctly converts to "привет!" and switches to Russian layout → User continues typing Russian words on physical English layout → BabylonFish incorrectly tries to convert them back, creating gibberish like "rjycthdfwbz" instead of "конвертация"

**Root Cause**: After auto-switching layout, BabylonFish didn't track that it was the one who switched, and didn't maintain context about expected user behavior.

### Solution Implemented

#### 1. Enhanced Context Tracking (`EventProcessor.swift`)
```swift
struct ProcessingContext {
    // ... existing fields ...
    var lastLayoutSwitchByApp: Bool = false  // true if BabylonFish switched
    var expectedLayoutLanguage: Language?    // What language we expect after switch
    var postSwitchWordCount: Int = 0         // Words typed after BabylonFish switch
    var postSwitchBuffer: [String] = []      // Buffer for post-switch words
}
```

#### 2. Smart Post-Switch Logic
- After BabylonFish switches layout, assumes user will type on new layout for 5 seconds
- If user types language different from expected, assumes it's correct behavior
- Prevents unnecessary re-switching that caused gibberish

#### 3. Manual Switch Detection
- Detects Cmd+Space / Ctrl+Space shortcuts
- Monitors layout changes: if user manually switches, resets BabylonFish tracking
- Prevents BabylonFish from fighting user's manual choices

#### 4. Stability Fixes
- **Recursion protection**: Added `maxRecursionDepth = 3` to prevent infinite loops
- **Tap re-enable limits**: Limited attempts to re-enable disabled event taps (max 3 attempts)
- **Fallback mode**: Automatic switch to fallback if tap fails repeatedly

### Current Issues & Next Steps

#### ✅ Working:
- Language detection (bi/trigrams + neural network)
- Basic layout switching ("ghbdtn" → "привет")
- Post-switch context tracking
- Manual switch detection
- System stability (no hangs)

#### ✅ Fixed:
1. **Word conversion with punctuation**: Enhanced `separateWordAndPunctuation()` to handle all cases
   - Problem: "ghbdtn!" → should delete "ghbdtn!" and type "привет!" (with exclamation)
   - Solution: Now correctly preserves leading and trailing punctuation
   - Handles: quotes, brackets, multiple punctuation marks, etc.

#### ✅ Fixed:
1. **Space handling**: Improved word boundary detection in BufferManager
   - Problem: Multi-word sentences didn't process correctly
   - Solution: Strict boundaries (space, tab, newline) trigger word completion
   - Punctuation stays with word (e.g., 'ghbdtn!' keeps '!')
   - Multiple words processed sequentially

2. **Complete conversion flow**: 
   - Detect wrong-language word ✓
   - Delete it completely (including punctuation) ✓  
   - Type corrected version (with original punctuation) ✓
   - Switch layout if needed ✓

### Testing Commands Added
```bash
# Test post-switch logic
swift test_post_switch.swift

# Test stability fixes  
swift test_stability.swift

# Test complete scenario
swift test_scenario_final.swift
```

### Key Code Locations
- `Sources/BabylonFish3/Core/EventProcessor.swift:886-910` - Enhanced ProcessingContext
- `Sources/BabylonFish3/Core/EventProcessor.swift:408-418` - Post-switch logic in shouldSwitchLayout
- `Sources/BabylonFish3/Core/EventProcessor.swift:195-225` - Manual switch detection
- `Sources/BabylonFish3/Core/EventTapManager.swift:227-248` - Tap re-enable limits

### Remaining Tasks
1. **Test edge cases**: mixed punctuation, numbers, special characters
2. **Enable advanced features** (typo correction, auto-complete) once core is stable
3. **Performance optimization** for long texts
4. **UI improvements**: Visual indicators for layout switching

### Recently Fixed
1. **Punctuation handling**: Enhanced `separateWordAndPunctuation()` function
   - Now handles leading and trailing punctuation separately
   - Preserves punctuation order and position
   - Works with quotes, brackets, multiple punctuation marks
   - Test with: `swift test_full_flow.swift`

2. **Word boundary detection**: Improved BufferManager logic
   - Strict boundaries (space, tab, newline) trigger word completion
   - Punctuation stays with word (e.g., 'ghbdtn!' keeps '!')
   - Multiple words processed sequentially
   - Test with: `swift test_buffer_fixed.swift`

3. **System stability**: Added recursion protection and tap re-enable limits
   - Prevents infinite loops when event tap is disabled
   - Maximum 3 re-enable attempts with 5-second cooldown
   - Automatic fallback mode after failures
   - Test with: `swift test_stability.swift`

### Build Status
- **Current**: Stable (3.0.40) - no system hangs
- **Configuration**: Minimal (advanced features disabled for testing)
- **Permissions**: Works in fallback mode without Accessibility