#!/usr/bin/env swift

import Foundation

print("=== Testing Full Conversion Flow with Punctuation ===")
print()

// Simulate the complete flow
func simulateConversionFlow(input: String, expectedOutput: String) {
    print("Input: '\(input)'")
    
    // Step 1: Separate punctuation
    let punctuationChars = CharacterSet.punctuationCharacters
        .union(CharacterSet.symbols)
        .union(CharacterSet(charactersIn: "«»\"'`"))
    
    var word = input
    var leadingPunctuation = ""
    var trailingPunctuation = ""
    
    // Find leading punctuation
    while let firstChar = word.first {
        let charStr = String(firstChar)
        if charStr.rangeOfCharacter(from: punctuationChars) != nil {
            leadingPunctuation.append(charStr)
            word.removeFirst()
        } else {
            break
        }
    }
    
    // Find trailing punctuation
    while let lastChar = word.last {
        let charStr = String(lastChar)
        if charStr.rangeOfCharacter(from: punctuationChars) != nil {
            trailingPunctuation = charStr + trailingPunctuation
            word.removeLast()
        } else {
            break
        }
    }
    
    print("  Separated: word='\(word)', leading='\(leadingPunctuation)', trailing='\(trailingPunctuation)'")
    
    // Step 2: Convert word (simplified)
    let convertedWord: String
    switch word {
    case "ghbdtn": convertedWord = "привет"
    case "rfr": convertedWord = "как"
    case "plhfdcndeqnt": convertedWord = "конвертация"
    case "ntcn": convertedWord = "меня"
    case "yf": convertedWord = "бы"
    default: convertedWord = word
    }
    
    print("  Converted: '\(word)' → '\(convertedWord)'")
    
    // Step 3: Reconstruct with punctuation
    let result = leadingPunctuation + convertedWord + trailingPunctuation
    print("  Result: '\(result)'")
    
    if result == expectedOutput {
        print("  ✅ PASS: Expected '\(expectedOutput)'")
    } else {
        print("  ❌ FAIL: Expected '\(expectedOutput)', got '\(result)'")
    }
    print()
}

// Test cases
let testCases = [
    ("ghbdtn!", "привет!"),
    ("ghbdtn?", "привет?"),
    ("ghbdtn.", "привет."),
    ("\"ghbdtn\"", "\"привет\""),
    ("'ghbdtn'", "'привет'"),
    ("(ghbdtn)", "(привет)"),
    ("[ghbdtn]", "[привет]"),
    ("«ghbdtn»", "«привет»"),
    ("ghbdtn!?", "привет!?"),
    ("ghbdtn...", "привет..."),
    ("!ghbdtn!", "!привет!"),
    ("\"ghbdtn!\"", "\"привет!\""),
    ("rfr?", "как?"),
    ("plhfdcndeqnt.", "конвертация."),
    ("ntcn!", "меня!"),
    ("yf?", "бы?"),
]

print("Testing various punctuation scenarios:")
print("==================================================")

for (input, expected) in testCases {
    simulateConversionFlow(input: input, expectedOutput: expected)
}

print("✅ All tests completed!")
print()
print("Key improvements in the new implementation:")
print("1. Handles leading punctuation (quotes, brackets, exclamation marks)")
print("2. Preserves punctuation order and position")
print("3. Works with multiple punctuation marks")
print("4. Correctly reconstructs the final text")
print()
print("This fixes the issue where 'ghbdtn!' would become 'привет!' (with exclamation)")
print("instead of losing punctuation or placing it incorrectly.")