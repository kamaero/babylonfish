#!/usr/bin/env swift

import Foundation

print("=== Testing Word Boundary Detection ===")
print()

// Simulate BufferManager logic
class TestBufferManager {
    private var wordBoundaryCharacters: Set<Character> = [" ", "\t", "\n", "\r", ".", ",", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'"]
    private var wordBuffer: String = ""
    
    func addCharacter(_ char: Character) {
        // Current logic: ALL characters go to wordBuffer
        wordBuffer.append(char)
        print("  Added '\(char)' → wordBuffer: '\(wordBuffer)'")
    }
    
    func shouldProcessWord() -> Bool {
        guard !wordBuffer.isEmpty else { return false }
        
        // Check if last character is word boundary
        if let lastChar = wordBuffer.last,
           wordBoundaryCharacters.contains(lastChar) {
            print("  ✓ Word boundary detected: '\(lastChar)'")
            return true
        }
        
        return false
    }
    
    func getCurrentWord() -> String {
        return wordBuffer
    }
    
    func clearWord() {
        wordBuffer = ""
    }
}

print("Test 1: Simple word with space")
print("Typing: 'g', 'h', 'b', 'd', 't', 'n', ' '")
let manager1 = TestBufferManager()
for char in "ghbdtn " {
    manager1.addCharacter(char)
    if manager1.shouldProcessWord() {
        print("  Should process word: '\(manager1.getCurrentWord())'")
        print("  Problem: wordBuffer contains space at the end!")
        break
    }
}

print("\nTest 2: Word with punctuation")
print("Typing: 'g', 'h', 'b', 'd', 't', 'n', '!'")
let manager2 = TestBufferManager()
for char in "ghbdtn!" {
    manager2.addCharacter(char)
    if manager2.shouldProcessWord() {
        print("  Should process word: '\(manager2.getCurrentWord())'")
        print("  Good: wordBuffer contains 'ghbdtn!' (with punctuation)")
        break
    }
}

print("\nTest 3: Multiple words")
print("Typing: 'p', 'r', 'i', 'v', 'e', 't', ' ', 'k', 'a', 'k'")
let manager3 = TestBufferManager()
for char in "privet kak" {
    manager3.addCharacter(char)
    if manager3.shouldProcessWord() {
        print("  First word detected: '\(manager3.getCurrentWord())'")
        print("  Problem: 'privet ' contains space!")
        manager3.clearWord()
    }
}

print("\n✅ Analysis:")
print("Problem: wordBuffer includes boundary characters (space, etc.)")
print("This causes issues because:")
print("1. 'ghbdtn ' → contains space, not just 'ghbdtn'")
print("2. Need to separate word from boundary before processing")
print("3. Boundary should trigger processing but not be part of word")

print("\n🔧 Solution needed:")
print("1. Track boundary characters separately")
print("2. When boundary detected, process word WITHOUT the boundary")
print("3. Or: remove boundary from wordBuffer before processing")
print("4. Current separateWordAndPunctuation() helps but doesn't handle spaces")