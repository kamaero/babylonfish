import Foundation

/// Менеджер буфера ввода для отслеживания набираемого текста
class BufferManager {
    
    // Конфигурация
    private var maxBufferSize: Int = 1000
    private var maxWordLength: Int = 50
    
    // Разделители, которые всегда являются границами слов
    private var strictWordBoundaries: Set<Character> = [" ", "\t", "\n", "\r"]
    
    // Знаки препинания, которые могут быть частью слова или границами
    // (обрабатываются отдельно в shouldProcessWord)
    private var punctuationCharacters: Set<Character> = [".", ",", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'"]
    
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
        // 2. Мы только что завершили слово (wordBuffer пуст, но previousWords обновлен)
        // 3. Длина слова превышает лимит
        
        // Проверяем, есть ли необработанные слова в previousWords
        // (completeCurrentWord() добавляет слова в previousWords)
        if !previousWords.isEmpty {
            let lastProcessed = previousWords.last ?? ""
            logDebug("BufferManager: Word ready for processing: '\(lastProcessed)'")
            return true
        }
        
        // Проверяем максимальную длину текущего слова
        if !wordBuffer.isEmpty && wordBuffer.count >= maxWordLength {
            logDebug("BufferManager: Word length limit reached: '\(wordBuffer)'")
            return true
        }
        
        return false
    }
    
    /// Получает текущее слово из буфера
    func getCurrentWord() -> String? {
        // Возвращаем последнее завершенное слово из previousWords
        // или текущее слово из wordBuffer если оно еще не завершено
        if let lastWord = previousWords.last {
            return lastWord
        } else if !wordBuffer.isEmpty {
            return wordBuffer
        }
        
        return nil
    }
    
    /// Получает предыдущие слова
    func getPreviousWords(count: Int = 10) -> [String] {
        return Array(previousWords.suffix(count))
    }
    
    /// Удаляет последний символ из буфера
    func removeLast() {
        guard !characterBuffer.isEmpty else { return }
        
        let removedChar = characterBuffer.removeLast()
        
        // Перестраиваем wordBuffer из оставшихся символов, исключая строгие границы
        reconstructWordBuffer()
        
        logDebug("BufferManager: Removed last char '\(removedChar)'. Word buffer: '\(wordBuffer)'")
    }
    
    /// Очищает текущее слово из буфера
    func clearWord() {
        // Удаляем последнее обработанное слово из previousWords и bufferHistory
        if !previousWords.isEmpty {
            previousWords.removeLast()
        }
        if !bufferHistory.isEmpty {
            bufferHistory.removeLast()
        }
        // Также очищаем wordBuffer на всякий случай
        wordBuffer = ""
        logDebug("BufferManager: Word cleared")
    }
    
    /// Очищает весь буфер
    func clear() {
        let charCount = characterBuffer.count
        let wordBuf = wordBuffer
        
        if !wordBuffer.isEmpty {
            clearWord()
        }
        
        characterBuffer.removeAll()
        logDebug("Buffer cleared: had \(charCount) characters, wordBuffer='\(wordBuf)'")
    }
    
    /// Принудительно очищает буфер при начале нового ввода
    func clearForNewInput() {
        let charCount = characterBuffer.count
        let wordBuf = wordBuffer
        
        // Полностью очищаем все буферы
        characterBuffer.removeAll()
        wordBuffer = ""
        previousWords.removeAll()
        bufferHistory.removeAll()
        
        logDebug("Buffer cleared for new input: had \(charCount) characters, wordBuffer='\(wordBuf)'")
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
        
        // Проверяем, является ли символ строгой границей (пробел, табуляция и т.д.)
        if strictWordBoundaries.contains(character) {
            // Если это строгая граница, завершаем текущее слово
            if !wordBuffer.isEmpty {
                completeCurrentWord()
            }
            // Не добавляем границу в wordBuffer
            logDebug("BufferManager: Strict boundary '\(character)' detected, word completed")
        } else if isPunctuation(character) {
            // Если это знак препинания, завершаем текущее слово
            if !wordBuffer.isEmpty {
                completeCurrentWord()
            }
            // Не добавляем знак препинания в wordBuffer
            logDebug("BufferManager: Punctuation '\(character)' detected, word completed")
        } else {
            // Проверяем максимальную длину слова
            if wordBuffer.count >= maxWordLength {
                logDebug("BufferManager: Word length limit reached (\(maxWordLength) chars), forcing word completion")
                completeCurrentWord()
            }
            
            // Добавляем только буквы и цифры в wordBuffer
            wordBuffer.append(character)
            logDebug("BufferManager: Added char '\(character)' to wordBuffer: '\(wordBuffer)' (total chars: \(characterBuffer.count), word length: \(wordBuffer.count))")
        }
    }
    
    private func isPunctuation(_ character: Character) -> Bool {
        let punctuationSet: Set<Character> = [
            "!", "?", ".", ",", ";", ":", "'", "\"", "(", ")", "[", "]", "{", "}",
            "-", "_", "=", "+", "@", "#", "$", "%", "^", "&", "*", "~", "`", "|", "\\",
            "/", "<", ">"
        ]
        return punctuationSet.contains(character)
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
    
    /// Перестраивает wordBuffer из characterBuffer, исключая строгие границы и знаки препинания
    private func reconstructWordBuffer() {
        wordBuffer = ""
        for char in characterBuffer {
            if !strictWordBoundaries.contains(char) && !isPunctuation(char) {
                wordBuffer.append(char)
            }
        }
        logDebug("BufferManager: Reconstructed wordBuffer: '\(wordBuffer)'")
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
        
        // Комбинируем строгие границы и знаки препинания
        let allBoundaries = strictWordBoundaries.union(punctuationCharacters)
        
        // Находим начало слова
        var start = position
        while start > 0 && !allBoundaries.contains(characterBuffer[start - 1]) {
            start -= 1
        }
        
        // Находим конец слова
        var end = position
        while end < characterBuffer.count - 1 && !allBoundaries.contains(characterBuffer[end]) {
            end += 1
        }
        
        // Если end указывает на символ-разделитель, включаем его
        if end < characterBuffer.count && allBoundaries.contains(characterBuffer[end]) {
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
        let allBoundaries = strictWordBoundaries.union(punctuationCharacters)
        return String(wordChars).trimmingCharacters(in: CharacterSet(charactersIn: String(allBoundaries)))
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
