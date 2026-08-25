// What can be said, and what it reaches. Kept apart from the recogniser so the
// grammar can be driven by a test without a microphone, a permission or a
// person, and so the recogniser stays the thin part.
import Foundation

enum VoiceCommand: String, CaseIterable {
  case draw
  case done
  case clear
  case undo
  case toolPen = "tool-pen"
  case toolArrow = "tool-arrow"
  case toolRect = "tool-rectangle"
  case toolHighlighter = "tool-highlighter"
  case toolText = "tool-text"
  case colorRed = "colour-red"
  case colorOrange = "colour-orange"
  case colorYellow = "colour-yellow"
  case colorGreen = "colour-green"
  case colorBlue = "colour-blue"
  case colorWhite = "colour-white"
  case bigger
  case smaller
  case screenshot
  case region
  case hide
  case show
  case stop

  // What the user says to reach it. Several per command, because one phrasing
  // is the author's and a person mid sentence uses their own. The settings
  // window edits this list, and a phrase added there is a phrase that works.
  //
  // Region comes before screenshot in the matching, not here: the phrases are
  // ranked by length when they are matched, so "take a screenshot of this area"
  // wins over "take a screenshot" no matter which order they are declared in.
  var defaultPhrases: [String] {
    switch self {
    case .draw: return ["draw", "start drawing", "annotate"]
    case .done: return ["done", "finish", "stop drawing", "put the pen down"]
    case .clear: return ["clear", "clear the marks", "wipe that", "erase that"]
    case .undo: return ["undo", "undo that", "take that back"]
    case .toolPen: return ["pick the pen", "pick pen", "use the pen", "pen"]
    case .toolArrow: return ["pick arrow", "pick the arrow", "use an arrow", "arrow"]
    case .toolRect: return ["pick rectangle", "pick the rectangle", "use a rectangle",
                            "rectangle", "box"]
    case .toolHighlighter: return ["pick highlight", "pick the highlighter",
                                   "pick highlighter", "highlight", "highlighter"]
    case .toolText: return ["pick text", "pick the text tool", "type", "text"]
    case .colorRed: return ["pick red", "go red", "red"]
    case .colorOrange: return ["pick orange", "go orange", "orange"]
    case .colorYellow: return ["pick yellow", "go yellow", "yellow"]
    case .colorGreen: return ["pick green", "go green", "green"]
    case .colorBlue: return ["pick blue", "go blue", "blue"]
    case .colorWhite: return ["pick white", "go white", "white"]
    case .bigger: return ["make it bigger", "make bigger", "bigger", "thicker"]
    case .smaller: return ["make it smaller", "make smaller", "smaller", "thinner"]
    case .screenshot: return ["take a screenshot", "take a shot", "screenshot",
                              "grab the screen"]
    case .region: return ["take a screenshot of this area",
                          "take a screenshot of an area",
                          "take a screenshot of the area",
                          "screenshot this area", "screenshot an area",
                          "grab this area", "capture this area", "region"]
    case .hide: return ["hide the marks", "hide that", "hide"]
    case .show: return ["show the marks", "show that", "show"]
    case .stop: return ["stop the session", "stop recording", "end the session",
                        "that is everything", "finish the session"]
    }
  }

  // What the log and the settings window call it, in the words a person would
  // use rather than the case name.
  var title: String {
    switch self {
    case .draw: return "start drawing"
    case .done: return "stop drawing"
    case .clear: return "clear the marks"
    case .undo: return "undo the last mark"
    case .toolPen: return "the pen"
    case .toolArrow: return "the arrow"
    case .toolRect: return "the rectangle"
    case .toolHighlighter: return "the highlighter"
    case .toolText: return "the text tool"
    case .colorRed: return "red"
    case .colorOrange: return "orange"
    case .colorYellow: return "yellow"
    case .colorGreen: return "green"
    case .colorBlue: return "blue"
    case .colorWhite: return "white"
    case .bigger: return "thicker"
    case .smaller: return "thinner"
    case .screenshot: return "screenshot"
    case .region: return "screenshot a region"
    case .hide: return "hide the marks"
    case .show: return "show the marks"
    case .stop: return "end the session"
    }
  }

  // Which group the settings window files it under. A flat list of twenty three
  // rows is a list nobody reads to the end of.
  var group: String {
    switch self {
    case .draw, .done, .clear, .undo, .hide, .show: return "Drawing"
    case .toolPen, .toolArrow, .toolRect, .toolHighlighter, .toolText: return "Tools"
    case .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorBlue, .colorWhite:
      return "Colours"
    case .bigger, .smaller: return "Width"
    case .screenshot, .region, .stop: return "Session"
    }
  }
}

// What a heard sentence turned out to be.
struct VoiceMatch {
  var command: VoiceCommand
  // The words that reached it, so the log says what the user actually said and
  // the transcript knows what to take out.
  var phrase: String
  // The whole utterance the recogniser produced, spoken punctuation and all.
  var heard: String
  // Where in the utterance it started. A recogniser revises what it has heard
  // as it goes, handing over the whole sentence again each time, so this is
  // what tells a command already acted on from a new one.
  var wordIndex: Int = 0
  // True when this match sits at the end of what has been heard so far and a
  // longer phrase begins with the same words. "take a screenshot" is the whole
  // of "take a screenshot of this area" until the rest of it arrives, and
  // acting on the short one takes the wrong picture.
  var couldGrow: Bool = false
}

// The grammar. Given what the recogniser heard, it answers with the command the
// user asked for, or with nothing, and nothing is the usual answer: a session is
// mostly a person describing a bug and not issuing orders.
struct VoiceGrammar {
  // The word that separates an instruction from the rest of the talking. A
  // session is spent saying things like "the rectangle is the wrong colour",
  // and without a prefix that sentence changes the tool twice.
  var trigger: String
  // The way to say one of these sentences and mean it literally. Without it
  // there is no way to tell this tool what to write down, and a user explaining
  // the tool to itself has no escape.
  var escape: String
  var phrases: [VoiceCommand: [String]]

  init(trigger: String = "let's",
       escape: String = "not a command",
       phrases: [VoiceCommand: [String]]? = nil) {
    self.trigger = trigger
    self.escape = escape
    self.phrases = phrases ?? Dictionary(uniqueKeysWithValues:
      VoiceCommand.allCases.map { ($0, $0.defaultPhrases) })
  }

  // Recognisers punctuate, capitalise and write "let us" for "let's", and none
  // of that is the user saying anything different.
  static func normalise(_ text: String) -> String {
    var out = ""
    for character in text.lowercased() {
      if character.isLetter || character.isNumber {
        out.append(character)
      } else if character == "'" || character == "\u{2019}" {
        // Kept, because the trigger itself has one in it.
        out.append("'")
      } else {
        out.append(" ")
      }
    }
    let words = out.split(separator: " ").map(String.init)
    return words.joined(separator: " ")
  }

  // The forms of the trigger a recogniser produces for the same spoken word.
  private func triggerForms() -> [String] {
    let base = Self.normalise(trigger)
    guard !base.isEmpty else { return [] }
    var forms = [base]
    if base.contains("'") { forms.append(base.replacingOccurrences(of: "'", with: "")) }
    if base == "let's" { forms.append("let us") }
    return forms
  }

  // Every phrase, longest first, so "take a screenshot of this area" is never
  // decided by the shorter "take a screenshot" that is also a match for its
  // first three words.
  private func ranked() -> [(VoiceCommand, String, String)] {
    var all: [(VoiceCommand, String, String)] = []
    for command in VoiceCommand.allCases {
      for phrase in phrases[command] ?? [] {
        let normalised = Self.normalise(phrase)
        guard !normalised.isEmpty else { continue }
        all.append((command, phrase, normalised))
      }
    }
    // Ranked by the words that carry meaning, since those are the ones matched.
    func weight(_ phrase: String) -> Int {
      Self.meaningful(phrase.split(separator: " ").map(String.init)).count
    }
    return all.sorted { weight($0.2) > weight($1.2) }
  }

  // Words a recogniser drops without changing what was meant. This machine's own
  // recogniser heard "let's take screenshot of this area" for audio that said
  // "take a screenshot of this area", and an exact match on the words let the
  // command through untouched. An article is never what a command turns on, so
  // both sides are matched without them.
  static let fillers: Set<String> = ["a", "an", "the"]

  // The words that carry meaning, each remembering where it sat in the original
  // sentence, so what is reported afterwards is still the words the user said.
  private static func meaningful(_ words: [String]) -> [(word: String, at: Int)] {
    words.enumerated().compactMap { offset, word in
      fillers.contains(word) ? nil : (word, offset)
    }
  }

  // The commands in one heard utterance, in the order they were said. A
  // recogniser hands over a whole sentence at a time and a person says two
  // things in one breath.
  func matches(in heard: String) -> [VoiceMatch] {
    let text = Self.normalise(heard)
    guard !text.isEmpty else { return [] }
    let escapeText = Self.normalise(escape)
    let candidates = ranked()
    var found: [VoiceMatch] = []

    let original = text.split(separator: " ").map(String.init)
    let carried = Self.meaningful(original)
    let words = carried.map { $0.word }
    var index = 0
    while index < words.count {
      // The escape swallows the trigger that follows it, so the sentence is
      // written down and nothing is done about it.
      if !escapeText.isEmpty,
         let length = starts(words, at: index, with: escapeText) {
        index += length
        if let skip = triggerForms().compactMap({ starts(words, at: index, with: $0) }).max() {
          index += skip
        }
        // Whatever followed is words and not an instruction, so the phrase that
        // would have matched is stepped over rather than searched for.
        if let step = candidates.compactMap({ starts(words, at: index, with: $0.2) }).max() {
          index += step
        }
        continue
      }

      guard let triggerLength = triggerForms()
              .compactMap({ starts(words, at: index, with: $0) }).max() else {
        index += 1
        continue
      }

      let after = index + triggerLength
      if let hit = candidates.first(where: { starts(words, at: after, with: $0.2) != nil }) {
        let length = starts(words, at: after, with: hit.2) ?? 0
        let matched = Array(words[after..<(after + length)])
        // What has been heard since this match. A recogniser builds its
        // sentence a word at a time, so "of" on its own is not the sentence
        // moving on, it is the longer phrase still arriving.
        let tail = Array(words[(after + length)...])
        let growable = candidates.contains { other in
          let wanted = Self.meaningful(other.2.split(separator: " ").map(String.init))
            .map { $0.word }
          guard wanted.count > matched.count,
                Array(wanted.prefix(matched.count)) == matched else { return false }
          let rest = Array(wanted.dropFirst(matched.count))
          // Still short of the longer phrase and still agreeing with it, so the
          // rest of it may yet arrive. Once the words stop agreeing the user
          // said the short one and went on to something else.
          return tail.count < rest.count && Array(rest.prefix(tail.count)) == tail
        }
        // Reported from the sentence as it was said, articles and all, because
        // the log is read by a person and the transcript is scrubbed against it.
        let from = carried[index].at
        let to = carried[after + length - 1].at
        let said = original[from...to].joined(separator: " ")
        found.append(VoiceMatch(command: hit.0, phrase: said, heard: heard,
                                wordIndex: index, couldGrow: growable))
        index = after + length
      } else {
        // A trigger with nothing behind it that this tool knows. It is the user
        // talking, so it stays in the transcript.
        index += triggerLength
      }
    }
    return found
  }

  // What the recogniser is told to expect, with the trigger in front of each.
  // Without it "let's draw" comes back as "let's throw": these are short, out
  // of context, and every word in them has a common neighbour that sounds like
  // it.
  //
  // One phrase per command and not all of them. Whisper caps an initial prompt
  // at half its text context, and the whole table is more than twice that, so
  // passing everything gets it cut off mid list and the bias goes with it.
  // Measured on the same 28 recordings: the whole table reaches 14, one phrase
  // each reaches 20.
  func expectedPhrases() -> [String] {
    VoiceCommand.allCases.compactMap { command in
      guard let first = phrases[command]?.first else { return nil }
      return trigger + " " + first
    }
  }

  // How many words of `words` from `at` are `needle`, or nothing. Both sides
  // have already had their articles taken out, so this compares what was meant.
  private func starts(_ words: [String], at: Int, with needle: String) -> Int? {
    let wanted = Self.meaningful(needle.split(separator: " ").map(String.init))
      .map { $0.word }
    guard !wanted.isEmpty, at + wanted.count <= words.count else { return nil }
    for (offset, word) in wanted.enumerated() where words[at + offset] != word {
      return nil
    }
    return wanted.count
  }
}
