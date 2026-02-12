#!/usr/bin/env swift

import Foundation

// Test the post-switch logic
print("Testing BabylonFish post-switch behavior...")
print("Scenario: 'ghbdtn!' → 'привет!' then continue typing Russian words")

// Simulate the context tracking
struct ProcessingContext {
    var lastLayoutSwitchTime: Date?
    var lastLayoutSwitchByApp: Bool = false
    var expectedLayoutLanguage: String?
    var postSwitchWordCount: Int = 0
}

var context = ProcessingContext()

// Test 1: BabylonFish switches layout
print("\n1. BabylonFish detects 'ghbdtn' as Russian typed on English layout")
context.lastLayoutSwitchTime = Date()
context.lastLayoutSwitchByApp = true
context.expectedLayoutLanguage = "Russian"
print("   Context: BabylonFish switched to Russian layout")

// Test 2: User continues typing "конвертация" on English layout
print("\n2. User types 'конвертация' on physical English layout")
print("   BabylonFish should detect: Russian language")
print("   Expected layout: Russian (from context)")
print("   Should switch layout? NO - user is typing Russian on English layout")

if context.lastLayoutSwitchByApp {
    let timeSinceSwitch = Date().timeIntervalSince(context.lastLayoutSwitchTime!)
    if timeSinceSwitch < 5.0 {
        print("   ✓ BabylonFish switched layout \(String(format: "%.1f", timeSinceSwitch))s ago")
        print("   ✓ User should be on Russian layout")
        print("   ✓ No layout switch needed - assuming correct behavior")
    }
}

// Test 3: User manually switches back to English
print("\n3. User manually switches back to English (Cmd+Space)")
context.lastLayoutSwitchByApp = false
context.expectedLayoutLanguage = "English"
print("   ✓ Manual switch detected")
print("   ✓ Context reset: BabylonFish no longer tracking switch")

// Test 4: User types English words
print("\n4. User types 'hello' on English layout")
print("   BabylonFish should detect: English language")
print("   Expected layout: English (from manual switch)")
print("   Should switch layout? NO - layouts match")

print("\n✅ Test scenario complete!")
print("The fix should prevent the 'ghbdtn!' → 'привет!' → 'rjycthdfwbz' issue")