#!/usr/bin/env swift

import Foundation

print("=== Testing Punctuation Handling ===")

// Current implementation
func separateWordAndPunctuationOld(_ text: String) -> (word: String, punctuation: String) {
    let punctuationChars = CharacterSet.punctuationCharacters.union(CharacterSet.symbols)
    var word = text
    var punctuation = ""
    
    // Ищем знаки препинания в конце строки
    while let lastChar = word.last {
        let charStr = String(lastChar)
        if charStr.rangeOfCharacter(from: punctuationChars) != nil {
            punctuation = charStr + punctuation
            word.removeLast()
        } else {
            break
        }
    }
    
    return (word, punctuation)
}

// New improved implementation
func separateWordAndPunctuationNew(_ text: String) -> (word: String, leadingPunctuation: String, trailingPunctuation: String) {
    let punctuationChars = CharacterSet.punctuationCharacters
        .union(CharacterSet.symbols)
        .union(CharacterSet(charactersIn: "«»\"'`"))
    
    var word = text
    var leadingPunctuation = ""
    var trailingPunctuation = ""
    
    // 1. Find leading punctuation
    while let firstChar = word.first {
        let charStr = String(firstChar)
        if charStr.rangeOfCharacter(from: punctuationChars) != nil {
            leadingPunctuation.append(charStr)
            word.removeFirst()
        } else {
            break
        }
    }
    
    // 2. Find trailing punctuation
    while let lastChar = word.last {
        let charStr = String(lastChar)
        if charStr.rangeOfCharacter(from: punctuationChars) != nil {
            trailingPunctuation = charStr + trailingPunctuation
            word.removeLast()
        } else {
            break
        }
    }
    
    return (word, leadingPunctuation, trailingPunctuation)
}

// Test cases
let testCases = [
    "ghbdtn!",
    "ghbdtn!!",
    "ghbdtn?",
    "ghbdtn.",
    "ghbdtn,",
    "\"ghbdtn\"",
    "'ghbdtn'",
    "(ghbdtn)",
    "[ghbdtn]",
    "«ghbdtn»",
    "ghbdtn!?",
    "ghbdtn...",
    "!ghbdtn!",
    "\"ghbdtn!\"",
    "ghbdtn-test",
    "ghbdtn's",
]

print("\nCurrent implementation:")
for test in testCases {
    let (word, punctuation) = separateWordAndPunctuationOld(test)
    print("  '\(test)' → word='\(word)', punctuation='\(punctuation)'")
}

print("\nNew implementation:")
for test in testCases {
    let (word, leading, trailing) = separateWordAndPunctuationNew(test)
    print("  '\(test)' → word='\(word)', leading='\(leading)', trailing='\(trailing)'")
}

print("\n✅ Key improvements:")
print("1. Handles leading punctuation (quotes, brackets)")
print("2. Preserves punctuation order")
print("3. Better for multi-punctuation like '...' or '!?'")
print("4. Works with different quote types")