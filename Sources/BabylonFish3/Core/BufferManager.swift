import Foundation

/// Менеджер буфера ввода для отслеживания набираемого текста
class BufferManager {
    
    // Конфигурация
    private var maxBufferSize: Int = 1000
    private var maxWordLength: Int = 50
    private var wordBoundaryCharacters: Set<Character> = [" ", "\t", "\n", "\r", ".", ",", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'"]
    
    // Состояние буфера
    private var characterBuffer: [Character] = []
    private var wordBuffer: String = ""
    private var previousWords: [String] = []
    private var bufferHistory: [String] = []
    
    // Статистика
    private var totalCharactersProcessed: Int = 0
    private var totalWordsProcessed: Int = 0
    private var bufferOverflows: Int = 0
    private var startTime: Date?
    
    /// Инициализирует менеджер буфера
    init(maxBufferSize: Int = 1000, maxWordLength: Int = 50) {
        self.maxBufferSize = maxBufferSize
        self.maxWordLength = maxWordLength
        self.startTime = Date()
        
        logDebug("BufferManager initialized with maxBufferSize=\(maxBufferSize), maxWordLength=\(maxWordLength)")
    }
    
    // MARK: - Public API
    
    /// Добавляет символ в буфер
    func addCharacter(_ character: String) {
        guard !character.isEmpty else { return }
        
        totalCharactersProcessed += 1
        
        // Обрабатываем каждый символ в строке
        for char in character {
            processCharacter(char)
        }
        
        // Проверяем переполнение буфера
        if characterBuffer.count > maxBufferSize {
            handleBufferOverflow()
        }
    }
    
    /// Проверяет, нужно ли обработать текущее слово
    func shouldProcessWord() -> Bool {
        // Слово готово к обработке если:
        // 1. Буфер слова не пустой
        // 2. Последний символ - граница слова
        // 3. Длина слова превышает лимит
        
        guard !wordBuffer.isEmpty else {
            return false
        }
        
        // Проверяем границу слова
        if let lastChar = characterBuffer.last,
           wordBoundaryCharacters.contains(lastChar) {
            return true
        }
        
        // Проверяем максимальную длину слова
        if wordBuffer.count >= maxWordLength {
            return true
        }
        
        return false
    }
    
    /// Получает текущее слово из буфера
    func getCurrentWord() -> String? {
        guard !wordBuffer.isEmpty else {
            return nil
        }
        
        return wordBuffer
    }
    
    /// Получает предыдущие слова
    func getPreviousWords(count: Int = 10) -> [String] {
        return Array(previousWords.suffix(count))
    }
    
    /// Удаляет последний символ из буфера
    func removeLast() {
        guard !characterBuffer.isEmpty else { return }
        
        let removedChar = characterBuffer.removeLast()
        
        // Если символ был частью текущего слова, удаляем и оттуда
        if !wordBoundaryCharacters.contains(removedChar) {
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }
        }
        // Если удалили разделитель, мы не восстанавливаем предыдущее слово в wordBuffer
        // Это упрощение, но для коррекции опечаток обычно достаточно
        
        logDebug("BufferManager: Removed last char. Word buffer: '\(wordBuffer)'")
    }
    
    /// Очищает текущее слово из буфера
    func clearWord() {
        if !wordBuffer.isEmpty {
            previousWords.append(wordBuffer)
            bufferHistory.append(wordBuffer)
            wordBuffer = ""
        }
    }
    
    /// Очищает весь буфер
    func clear() {
        if !wordBuffer.isEmpty {
            clearWord()
        }
        
        characterBuffer.removeAll()
        logDebug("Buffer cleared")
    }
    
    /// Получает полный буфер символов
    func getCharacterBuffer() -> [Character] {
        return characterBuffer
    }
    
    /// Получает историю буфера
    func getBufferHistory(count: Int = 100) -> [String] {
        return Array(bufferHistory.suffix(count))
    }
    
    /// Получает состояние буфера
    func getState() -> [String: Any] {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return [
            "wordBuffer": wordBuffer,
            "wordBufferLength": wordBuffer.count,
            "characterBufferLength": characterBuffer.count,
            "previousWordsCount": previousWords.count,
            "totalCharactersProcessed": totalCharactersProcessed,
            "totalWordsProcessed": totalWordsProcessed,
            "bufferOverflows": bufferOverflows,
            "uptime": uptime,
            "isWordReady": shouldProcessWord(),
            "lastWords": getPreviousWords(count: 5)
        ]
    }
    
    /// Настраивает менеджер буфера
    func configure(maxBufferSize: Int? = nil, maxWordLength: Int? = nil) {
        if let size = maxBufferSize {
            self.maxBufferSize = size
        }
        
        if let length = maxWordLength {
            self.maxWordLength = length
        }
        
        logDebug("BufferManager configured: maxBufferSize=\(self.maxBufferSize), maxWordLength=\(self.maxWordLength)")
    }
    
    // MARK: - Private Methods
    
    private func processCharacter(_ character: Character) {
        // Добавляем символ в общий буфер
        characterBuffer.append(character)
        
        // Проверяем, является ли символ границей слова
        if wordBoundaryCharacters.contains(character) {
            // Если буфер слова не пустой, слово завершено
            if !wordBuffer.isEmpty {
                completeCurrentWord()
            }
            
            // Добавляем символ-разделитель в общий буфер
            // (уже добавлен выше)
        } else {
            // Добавляем символ в буфер слова
            wordBuffer.append(character)
        }
    }
    
    private func completeCurrentWord() {
        guard !wordBuffer.isEmpty else { return }
        
        totalWordsProcessed += 1
        
        // Сохраняем слово в историю
        previousWords.append(wordBuffer)
        bufferHistory.append(wordBuffer)
        
        logDebug("Word completed: '\(wordBuffer)' (length: \(wordBuffer.count))")
        
        // Очищаем буфер слова
        wordBuffer = ""
    }
    
    private func handleBufferOverflow() {
        bufferOverflows += 1
        
        logDebug("Buffer overflow detected: \(characterBuffer.count) characters")
        
        // Удаляем старые символы из буфера
        let overflowCount = characterBuffer.count - maxBufferSize
        characterBuffer.removeFirst(overflowCount)
        
        // Также очищаем wordBuffer если он стал невалидным
        if !wordBuffer.isEmpty {
            // Проверяем, осталось ли слово в буфере
            let remainingChars = characterBuffer.suffix(wordBuffer.count)
            let remainingString = String(remainingChars)
            
            if remainingString != wordBuffer {
                // Слово было частично удалено, очищаем его
                wordBuffer = ""
                logDebug("Word buffer cleared due to overflow")
            }
        }
        
        logDebug("Buffer trimmed to \(characterBuffer.count) characters")
    }
    
    // MARK: - Вспомогательные методы
    
    /// Проверяет, является ли символ буквой
    private func isLetter(_ character: Character) -> Bool {
        return character.isLetter
    }
    
    /// Проверяет, является ли символ цифрой
    private func isDigit(_ character: Character) -> Bool {
        return character.isNumber
    }
    
    /// Проверяет, является ли символ пробельным
    private func isWhitespace(_ character: Character) -> Bool {
        return character.isWhitespace
    }
    
    /// Получает последние N символов из буфера
    func getLastCharacters(_ count: Int) -> String {
        let chars = characterBuffer.suffix(count)
        return String(chars)
    }
    
    /// Получает контекст вокруг текущей позиции
    func getContext(aroundPosition position: Int, radius: Int = 20) -> String {
        guard !characterBuffer.isEmpty else { return "" }
        
        let start = max(0, position - radius)
        let end = min(characterBuffer.count, position + radius)
        
        if start >= end {
            return ""
        }
        
        let contextChars = Array(characterBuffer[start..<end])
        return String(contextChars)
    }
    
    /// Находит границы слова вокруг позиции
    func findWordBoundaries(aroundPosition position: Int) -> (start: Int, end: Int)? {
        guard position >= 0 && position < characterBuffer.count else {
            return nil
        }
        
        // Находим начало слова
        var start = position
        while start > 0 && !wordBoundaryCharacters.contains(characterBuffer[start - 1]) {
            start -= 1
        }
        
        // Находим конец слова
        var end = position
        while end < characterBuffer.count - 1 && !wordBoundaryCharacters.contains(characterBuffer[end]) {
            end += 1
        }
        
        // Если end указывает на символ-разделитель, включаем его
        if end < characterBuffer.count && wordBoundaryCharacters.contains(characterBuffer[end]) {
            end += 1
        }
        
        return (start, end)
    }
    
    /// Извлекает слово вокруг позиции
    func extractWord(aroundPosition position: Int) -> String? {
        guard let boundaries = findWordBoundaries(aroundPosition: position) else {
            return nil
        }
        
        let wordChars = Array(characterBuffer[boundaries.start..<boundaries.end])
        return String(wordChars).trimmingCharacters(in: CharacterSet(charactersIn: String(wordBoundaryCharacters)))
    }
    
    /// Заменяет слово в буфере
    func replaceWord(atPosition position: Int, with newWord: String) -> Bool {
        guard let boundaries = findWordBoundaries(aroundPosition: position) else {
            return false
        }
        
        // Удаляем старое слово
        characterBuffer.removeSubrange(boundaries.start..<boundaries.end)
        
        // Вставляем новое слово
        let newWordChars = Array(newWord)
        characterBuffer.insert(contentsOf: newWordChars, at: boundaries.start)
        
        // Обновляем wordBuffer если он затрагивается
        if position >= characterBuffer.count - wordBuffer.count && position < characterBuffer.count {
            // Текущее слово было заменено
            wordBuffer = newWord
        }
        
        logDebug("Word replaced at position \(position): new word '\(newWord)'")
        return true
    }
    
    deinit {
        logDebug("BufferManager deinitialized")
    }
}

// MARK: - Расширения для отладки

extension BufferManager: CustomStringConvertible {
    var description: String {
        return """
        BufferManager(
          wordBuffer: "\(wordBuffer)",
          wordLength: \(wordBuffer.count),
          totalChars: \(characterBuffer.count),
          totalWords: \(previousWords.count),
          readyForProcessing: \(shouldProcessWord())
        )
        """
    }
}
