#
# Copyright 2016-2021 by Vinay Sajip (vinay_sajip@yahoo.co.uk). All Rights Reserved.
#
import algorithm
import bitops
import complex
import hashes
import math
import nre except toSeq
import os
import parseutils
import sets
import streams
import strformat
import strutils
import tables
import times
import timezones
import typetraits
import unicode

type
  TokenKind = enum
    EOF,
    Word,
    IntegerNumber,
    FloatNumber,
    StringToken,
    Newline,
    LeftCurly,
    RightCurly,
    LeftBracket,
    RightBracket,
    LeftParenthesis,
    RightParenthesis,
    LessThan,
    GreaterThan,
    LessThanOrEqual,
    GreaterThanOrEqual,
    Assign,
    Equal,
    Unequal,
    AltUnequal,
    LeftShift,
    RightShift,
    Dot,
    Comma,
    Colon,
    At,
    Plus,
    Minus,
    Star,
    Power,
    Slash,
    SlashSlash,
    Modulo,
    BackTick,
    Dollar,
    TrueToken,
    FalseToken,
    None,
    Is,
    In,
    Not,
    And,
    Or,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    BitwiseComplement,
    Complex,
    IsNot,
    NotIn,
    Error

  Location* = ref object
    ##
    ## This type represents a location in CFG source.
    ##
    line*: int
    column*: int

  R = Rune

  DecoderError = object of CatchableError

  RecognizerError = object of CatchableError
    location: Location

  TokenizerError = object of RecognizerError

  ParserError = object of RecognizerError

  ConfigError* = object of RecognizerError
    ##
    ## This type represents an error encountered when
    ## working with CFG.
    ##

  TokenValue = object
    case kind: TokenKind
    of IntegerNumber: intValue: int64
    of FloatNumber: floatValue: float64
    of StringToken, BackTick: stringValue: string
    of TrueToken, FalseToken: boolValue: bool
    of Complex: complexValue: Complex[float64]
    else: otherValue: int32

  ASTNode = ref object of RootObj
    kind: TokenKind
    startpos: Location
    endpos: Location

  Token = ref object of ASTNode
    text: string
    value: TokenValue

  UTF8Decoder = ref object
    stream: Stream

# ------------------------------------------------------------------------
#  Location
# ------------------------------------------------------------------------

func newLocation(line: int = 1, column: int = 1): Location = Location(
    line: line, column: column)

func copy(source: Location): Location = newLocation(source.line, source.column)

proc update(self: Location, source: Location) =
  self.line = source.line
  self.column = source.column

proc nextLine(loc: Location) =
  loc.line += 1
  loc.column = 1

proc prevCol(loc: Location) =
  if loc.column > 0:
    loc.column -= 1

func `$`(loc: Location): string = &"({loc.line}, {loc.column})"

func `==`(loc1, loc2: Location): bool =
  assert not loc1.isNil
  assert not loc2.isNil
  loc1.line == loc2.line and loc1.column == loc2.column

# ------------------------------------------------------------------------
#  Token
# ------------------------------------------------------------------------

func newToken(text: string, value: TokenValue): Token = Token(text: text,
    value: value, kind: value.kind)

proc setValue(t: Token, v: TokenValue) =
  t.value = v
  t.kind = t.value.kind

func `$`(tok: Token): string =
  &"_T({tok.text}|{tok.value}|{tok.startpos}|{tok.endpos})"

func `==`(t1, t2: TokenValue): bool =
  if t1.kind != t2.kind: return false
  case t1.kind:
  of IntegerNumber: return t1.intValue == t2.intValue
  of FloatNumber: return t1.floatValue == t2.floatValue
  of StringToken, BackTick: return t1.stringValue == t2.stringValue
  of TrueToken, FalseToken: return t1.boolValue == t2.boolValue
  of Complex: return t1.complexValue == t2.complexValue
  else:
    return t1.otherValue == t2.otherValue

proc `==`(t1, t2: Token): bool =
  if t1.value != t2.value:
    return false
  if t1.text != t2.text:
    return false
  if not (t1.startpos.isNil or t2.startpos.isNil):
    if t1.startpos != t2.startpos:
      return false
  if not (t1.endpos.isNil or t2.endpos.isNil):
    if t1.endpos != t2.endpos:
      return false
  return true

# ------------------------------------------------------------------------
#  UTF8 Decoder
# see http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
# ------------------------------------------------------------------------

const UTF8_ACCEPT = 0
const UTF8_REJECT = 12

const UTF8_LOOKUP = [
  0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
  9, 9, 9, 9, 9, 9,
  7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
  7, 7, 7, 7, 7, 7,
  8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2,
  10, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 3, 3, 11, 6, 6, 6, 5, 8, 8, 8, 8,
  8, 8, 8, 8, 8, 8, 8,

  # The second part is a transition table that maps a combination
    # of a state of the automaton and a character class to a state.
  0, 12, 24, 36, 60, 96, 84, 12, 12, 12, 48, 72, 12, 12, 12, 12, 12, 12, 12, 12,
  12, 12, 12, 12,
  12, 0, 12, 12, 12, 12, 12, 0, 12, 0, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24,
  12, 24, 12, 12,
  12, 12, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12,
  12, 12, 24, 12, 12,
  12, 12, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12, 12, 36, 12, 12, 12, 12, 12,
  36, 12, 36, 12, 12,
  12, 36, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
]

func newUTF8Decoder(s: Stream): UTF8Decoder =
  new(result)
  result.stream = s

proc getRune(self: UTF8Decoder): Rune =
  var state: int = UTF8_ACCEPT
  var code_point: int
  var stream = self.stream
  var b: int

  if stream.atEnd:
    result = R(0)
  else:
    while not stream.atEnd:
      b = int(stream.readChar)
      var kind = int(UTF8_LOOKUP[b])

      if state != UTF8_ACCEPT:
        code_point = (b and 0x3F) or (code_point shl 6)
      else:
        code_point = (0xFF shr kind) and b
      state = int(UTF8_LOOKUP[256 + state + kind])
      if state == UTF8_ACCEPT or state == UTF8_REJECT:
        break
    if state == UTF8_ACCEPT:
      result = Rune(code_point)
    else:
      var msg: string

      if stream.atEnd:
        msg = "Incomplete UTF-8 data"
      else:
        var pos = stream.getPosition()
        msg = &"Invalid UTF-8 data: 0x{b:x} at 0x{pos:x}"
      raise newException(DecoderError, msg)

# ------------------------------------------------------------------------
#  Tokenizer
# ------------------------------------------------------------------------

type
  PushBackData = tuple[c: Rune, loc: Location]

  Tokenizer = ref object of RootObj
    stream: UTF8Decoder
    location: Location
    charLocation: Location
    pushedBack: seq[PushBackData]

proc newTokenizer(stream: Stream): Tokenizer =
  new(result)
  result.stream = newUTF8Decoder(stream)
  result.location = newLocation()
  result.charLocation = newLocation()
  result.pushedBack = @[]

proc pushBack(self: Tokenizer, c: Rune) =
  if c != R(0):
    var loc = self.charLocation.copy
    var t: PushBackData = (c, loc)
    self.pushedBack.add(t)

proc getChar(self: Tokenizer): Rune =
  if self.pushedBack.len() > 0:
    var pb = self.pushedBack.pop()
    result = pb.c
    self.charLocation.update(pb.loc)
    self.location.update(pb.loc) # will be bumped later
  else:
    self.charLocation.update(self.location)
    result = self.stream.getRune
  if result != R(0):
    if result == R('\n'):
      self.location.nextLine
    else:
      self.location.column += 1

func isDigit(c: Rune): bool {.noSideEffect, gcsafe, locks: 0.} =
  char(c).isDigit

func isHexDigit(c: Rune): bool {.noSideEffect, gcsafe, locks: 0.} =
  var ch = char(c).toUpperAscii
  if ch.isDigit:
    result = true
  else:
    result = ch >= 'A' and ch <= 'F'

func isOctalDigit(c: Rune): bool {.noSideEffect, gcsafe, locks: 0.} =
  var ch = char(c)
  if not ch.isDigit:
    result = false
  else:
    result = ch <= '7'

func asComplex(x: float64): Complex[float64] =
  result.re = 0
  result.im = x

const DIGITS = "0123456789ABCDEF"
const QUOTES = "\"'"
const PUNCT = {':': TokenValue(kind: Colon, otherValue: 0),
               '-': TokenValue(kind: Minus, otherValue: 0),
               '+': TokenValue(kind: Plus, otherValue: 0),
               '*': TokenValue(kind: Star, otherValue: 0),
               '/': TokenValue(kind: Slash, otherValue: 0),
               '%': TokenValue(kind: Modulo, otherValue: 0),
               ',': TokenValue(kind: Comma, otherValue: 0),
               '.': TokenValue(kind: Dot, otherValue: 0),
               '{': TokenValue(kind: LeftCurly, otherValue: 0),
               '}': TokenValue(kind: RightCurly, otherValue: 0),
               '[': TokenValue(kind: LeftBracket, otherValue: 0),
               ']': TokenValue(kind: RightBracket, otherValue: 0),
               '(': TokenValue(kind: LeftParenthesis, otherValue: 0),
               ')': TokenValue(kind: RightParenthesis, otherValue: 0),
               '@': TokenValue(kind: At, otherValue: 0),
               '=': TokenValue(kind: Assign, otherValue: 0),
               '$': TokenValue(kind: Dollar, otherValue: 0),
               '<': TokenValue(kind: LessThan, otherValue: 0),
               '>': TokenValue(kind: GreaterThan, otherValue: 0),
               '!': TokenValue(kind: Not, otherValue: 0),
               '~': TokenValue(kind: BitwiseComplement, otherValue: 0),
               '&': TokenValue(kind: BitwiseAnd, otherValue: 0),
               '|': TokenValue(kind: BitwiseOr, otherValue: 0),
               '^': TokenValue(kind: BitwiseXor, otherValue: 0)}.toTable

const KEYWORDS = {"true": TokenValue(kind: TrueToken, boolValue: true),
                  "false": TokenValue(kind: FalseToken, boolValue: false),
                  "null": TokenValue(kind: None, otherValue: 0),
                  "is": TokenValue(kind: Is, otherValue: 0),
                  "in": TokenValue(kind: In, otherValue: 0),
                  "not": TokenValue(kind: Not, otherValue: 0),
                  "and": TokenValue(kind: And, otherValue: 0),
                  "or": TokenValue(kind: Or, otherValue: 0)}.toTable

const ESCAPES = {
  'a': "\a",
  'b': "\b",
  'f': "\f",
  'n': "\n",
  'r': "\r",
  't': "\t",
  'v': "\v",
  '\\': "\\",
  '\'': "'",
  '"': "\""

}.toTable

proc parseInt64(s: string, radix: range[2u..16u]): int64 =
  var str = unicode.toUpper(s)
  var idx = 0
  var sign = 1
  var r: uint64 = 0

  if s[idx] == '-':
    sign = -1
    idx = 1
  for i in idx .. str.high:
    let c = str[i]
    assert c in DIGITS[0 ..< radix.int]
    r = r * radix + uint64(DIGITS.find c)
  result = sign * int64(r)

var HEX_PATTERN = re"^([0-9A-Fa-f]{2}([0-9A-Fa-f]{2})?([0-9A-Fa-f]{4})?)$"

proc parseEscapes(s: string): string =
  result = s
  var i = s.find("\\")
  if i >= 0:
    var e: ref TokenizerError
    var failed = false
    var n = len(s)
    var parts: seq[string] = @[]
    var pos = 0
    while i >= 0:
      if i > pos:
        parts.add(s[pos..i - 1])
      var idx = i + 1
      var c = s[idx]
      if c in ESCAPES:
        parts.add(ESCAPES[c])
        pos = i + 2
        # echo &"{parts}|{pos}"
      elif c in "xXuU":
        var slen = if c in "xX": 4 elif c == 'u': 6 else: 10
        if i + slen > n:
          failed = true
          break
        var hexpart = s[i + 2..i + slen - 1]
        # echo &"hexpart = {hexpart}"
        if not hexpart.match(HEX_PATTERN).isSome:
          failed = true
          break
        var es = parseInt64(hexpart, 16u)
        if ((es >= 0xd800) and (es <= 0xdfff)) or ((es >= 0x110000)):
          # values out of range
          new(e)
          e.msg = &"invalid escape sequence in: {s}"
          raise e
        parts.add($Rune(es))
        pos = i + slen
      else:
        # We could let \\z -> z ... but we choose for now
        # to be stricter. Next two commented lines are the
        # more forgiving approach.
        # parts.add(s[idx..idx])
        # pos = i + 2
        failed = true
        break
      i = s.find("\\", pos)
    # echo &"{parts}|{pos}"
    if failed:
      new(e)
      e.msg = &"invalid escape sequence in: {s}"
      raise e
    if pos < n:
      parts.add(s[pos..n - 1])
    result = parts.join

# func escape(s: string): string =
#   for c in items(s):
#     case c
#     of '\0'..'\31', '\34', '\39', '\92', '\127'..'\255':
#       result.addEscapedChar(c)
#     else: add(result, c)

var OCTAL_PATTERN = re"^[0-7]*$"

proc isOctal(s: string): bool = s.match(OCTAL_PATTERN).isSome

func hasExpMinus(text: seq[Rune]): bool =
  var i = text.find(R('-'))
  i > 0

proc getToken(self: Tokenizer): Token =
  result = newToken("", TokenValue(kind: Error, otherValue: 0))
  var startLocation = self.location.copy
  var endLocation = startLocation.copy
  var text: seq[Rune] = @[]

  proc getNumber(): TokenValue =
    var inExponent = false
    var radix = 0
    var dotSeen = text.find(R('.')) >= 0
    var lastWasDigit = text[^1].isDigit
    var c: Rune
    var ch: char
    var e: ref TokenizerError
    var fv: float

    while true:
      # echo &"GN: {text}|{endLocation}"
      c = self.getChar
      ch = char(int(c) and 0xFF)
      if ch == '.':
        dotSeen = true
      if ch == '_':
        if lastWasDigit:
          text.add(c)
          endLocation.update(self.location)
          lastWasDigit = false
          continue
        new(e)
        e.msg = &"invalid '_' in number: {text}{ch}"
        e.location = self.charLocation
        raise e
      if ch == '\0':
        endLocation.prevCol()
        break
      lastWasDigit = false # unless set below
      if (((radix == 0) and (ch >= '0') and (ch <= '9')) or
          ((radix == 2) and (ch >= '0') and (ch <= '1')) or
          ((radix == 8) and (ch >= '0') and (ch <= '7')) or
          ((radix == 16) and isHexDigit(c))):
        text.add(c)
        endLocation.update(self.location)
        lastWasDigit = true
      elif (radix == 0) and ch.isDigit:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 8) and c.isOctalDigit:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 16) and c.isHexDigit:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 2) and ch in "01":
        text.add(c)
        endLocation.update(self.location)
      elif ch in "OXBoxb" and text[0] == R('0'):
        radix = if ch in "Bb": 2 elif ch in "Oo": 8 else: 16
        text.add(c)
        endLocation.update(self.location)
      elif ch == '.':
        if (radix != 0) or text.find(R('.')) >= 0 or inExponent:
          new(e)
          e.msg = &"invalid character in number: {$text}{ch}"
          e.location = self.charLocation.copy
          raise e
        else:
          text.add(c)
          endLocation.update(self.location)
      elif (radix == 0) and (ch == '-') and not hasExpMinus(text) and inExponent:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 0) and (ch in "eE") and text.find(R('e')) < 0 and
          text.find(R('E')) < 0 and text[^1] != R('_'):
        text.add(c)
        endLocation.update(self.location)
        inExponent = true
      else:
        if (radix == 0) and ch in "jJ":
          text.add(c)
          endLocation.update(self.location)
        else:
          if ch != '.' and not ch.isAlphaNumeric:
            self.pushBack(c)
          else:
            new(e)
            e.msg = &"invalid character in number: {ch}"
            e.location = self.charLocation.copy
            raise e
        break
    if text[^1] == R('_'):
      new(e)
      e.msg = &"invalid '_' at end of number: {text}"
      e.location = startLocation.copy
      raise e
    try:
      var s = ($text).replace("_", "")
      if radix != 0:
        var iv = parseInt64(s[2..^1], radix)
        result = TokenValue(kind: IntegerNumber, intValue: iv)
      elif char(s[^1]) in "jJ":
        discard parseFloat(s, fv)
        result = TokenValue(kind: Complex, complexValue: asComplex(fv))
      elif inExponent or dotSeen:
        discard parseFloat(s, fv)
        result = TokenValue(kind: FloatNumber, floatValue: fv)
      else:
        radix = if char(text[0]) == '0': 8 else: 10
        if radix == 8 and not isOctal(s):
          new(e)
          e.msg = &"badly formed octal constant: {s}"
          e.location = startLocation.copy
          raise e
        result = TokenValue(kind: IntegerNumber, intValue: parseInt64(s, radix))
    except ValueError:
      new(e)
      e.msg = &"badly-formed number: {text}"
      e.location = startLocation.copy
      raise e

  var c: Rune
  var ch: char
  var e: ref TokenizerError

  while true:
    c = self.getChar
    ch = char(c)

    startLocation.update(self.charLocation)
    endLocation.update(self.charLocation)

    if ch == '\0':
      result = newToken("", TokenValue(kind: EOF, otherValue: 0))
      break
    elif ch == '#':
      result.text = &"#{self.stream.stream.readLine}"
      self.location.nextLine()
      endLocation.update(self.charLocation)
      endLocation.nextLine()
      endLocation.prevCol()
      result.setValue TokenValue(kind: Newline, otherValue: 0)
      break
    elif ch == '\n':
      result.setValue TokenValue(kind: NewLine, otherValue: 0)
      result.text.add(ch)
      endLocation.update(self.location)
      endLocation.prevCol()
      break
    elif ch == '\r':
      c = self.getChar
      ch = char(c)
      if ch != '\n':
        self.pushBack(c)
      result.setValue TokenValue(kind: Newline, otherValue: 0)
      endLocation.update(self.location)
      endLocation.prevCol()
      break
    elif c.isWhiteSpace:
      continue
    if ch in QUOTES:
      text.add(c)
      endLocation.update(self.charLocation)
      var quote = ch
      var escaped = false
      var multiline = false
      var c1 = self.getChar
      var c1loc = self.charLocation.copy
      if ord(c1) >= 0x100:
        self.pushBack(c1)
      else:
        var ch1 = char(c1)
        if ch1 != quote:
          self.pushBack(c1)
        else:
          var c2 = self.getChar
          if ord(c2) >= 0x100:
            self.pushBack(c2)
            self.pushBack(c1)
          else:
            var ch2 = char(c2)
            if ch2 != quote:
              self.pushBack(c2)
              self.charLocation.update(c1loc)
              self.pushBack(c1)
            else:
              multiline = true
              text.add(c2)
              text.add(c2)

      var quoter = $text
      # echo &"quoter: {quoter}"
      while true:
        c = self.getChar
        if ord(c) >= 0x0100:
          text.add(c)
          continue
        ch = char(c)
        if ch == '\0':
          break
        text.add(c)
        endLocation.update(self.charLocation)
        if (ch == quote) and not escaped:
          var n = text.len
          if not multiline or (len(text) >= 6 and ($text[^3..^1] == quoter) and
              text[n - 4] != R('\\')):
            break
        if ch == '\\':
          escaped = not escaped
        else:
          escaped = false
      # string loop done
      if ch == '\0':
        new(e)
        e.msg = &"unterminated quoted string: {text}"
        e.location = startLocation.copy
        raise e
      var n = len(quoter)
      var s = $text
      result.setValue TokenValue(kind: StringToken, stringValue: parseEscapes(s[
          n..^(n + 1)]))
      break
    elif ch == '`':
      text.add(c)
      endLocation.update(self.charLocation)
      while true:
        c = self.getChar
        ch = char(c)
        if ch == '\0':
          break
        if ch == '\r' or ch == '\n':
          break
        text.add(c)
        endLocation.update(self.charLocation)
        if ch == '`':
          break
      if ch == '`':
        var s = $text
        result.setValue TokenValue(kind: BackTick, stringValue: parseEscapes(s[1..^2]))
        break
      else:
        new(e)
        e.location = startLocation.copy
        if ch == '\0':
          e.msg = &"Unterminated `-string: {text}"
        elif ch == '\r' or ch == '\n':
          e.msg = &"Newlines not allowed in `-string: {text}"
        raise e
    elif c.isAlpha or (ch == '_'):
      text.add(c)
      endLocation.update(self.charLocation)
      c = self.getChar
      ch = char(c)
      while (ch != '\0') and (c.isAlpha or ch.isDigit or ch == '_'):
        text.add(c)
        endLocation.update(self.charLocation)
        c = self.getChar
        ch = char(c)
      self.pushBack(c)
      var s = $text
      result.text = s
      if s in KEYWORDS:
        result.setValue KEYWORDS[s]
      else:
        result.setValue TokenValue(kind: Word, otherValue: 0)
      break
    elif ch.isDigit:
      text.add(c)
      endLocation.update(self.charLocation)
      result.setValue getNumber()
      break
    elif ch in PUNCT:
      result.setValue PUNCT[ch]
      text.add(c)
      endLocation.update(self.charLocation)
      if ch == '.':
        c = self.getChar
        ch = char(c)
        if ch != '\0':
          self.pushBack(c)
          if ch.isDigit:
            result.setValue getNumber()
            break
      elif ch == '-':
        c = self.getChar
        ch = char(c)
        if ch == '.' or ch.isDigit:
          self.pushBack(c)
          result.setValue getNumber()
          break
      elif ch == '=':
        c = self.getChar
        ch = char(c)
        if ch != '=':
          self.pushBack(c)
        else:
          text.add(c)
          result.setValue TokenValue(kind: Equal, otherValue: 0)
      elif ch == '&':
        c = self.getChar
        ch = char(c)
        if ch != '&':
          self.pushBack(c)
        else:
          text.add(c)
          result.setValue TokenValue(kind: And, otherValue: 0)
      elif ch == '|':
        c = self.getChar
        ch = char(c)
        if ch != '|':
          self.pushBack(c)
        else:
          text.add(c)
          result.setValue TokenValue(kind: Or, otherValue: 0)
      elif ch in "<>!*/":
        var pch = ch
        c = self.getChar
        ch = char(c)
        var pb = true

        if pch == '<':
          if ch in "<>=":
            text.add(c)
            endLocation.update(self.charLocation)
            if ch == '<':
              result.setValue TokenValue(kind: LeftShift, otherValue: 0)
            elif ch == '>':
              result.setValue TokenValue(kind: AltUnequal, otherValue: 0)
            elif ch == '=':
              result.setValue TokenValue(kind: LessThanOrEqual, otherValue: 0)
            pb = false
        elif pch == '>':
          if ch in ">=":
            text.add(c)
            endLocation.update(self.charLocation)
            if ch == '>':
              result.setValue TokenValue(kind: RightShift, otherValue: 0)
            else:
              result.setValue TokenValue(kind: GreaterThanOrEqual, otherValue: 0)
            pb = false
        elif pch in "!=":
          if ch == '=':
            text.add(c)
            endLocation.update(self.charLocation)
            result.setValue TokenValue(kind: Unequal, otherValue: 0)
            pb = false
          else:
            pb = true
        elif pch in "*/=":
          if ch == pch:
            text.add(c)
            endLocation.update(self.charLocation)
            if pch == '*':
              result.setValue TokenValue(kind: Power, otherValue: 0)
            elif pch == '/':
              result.setValue TokenValue(kind: SlashSlash, otherValue: 0)
            else:
              result.setValue TokenValue(kind: Equal, otherValue: 0)
            pb = false
        if pb:
          self.pushBack(c)
      break
    elif ch == '\\':
      var cloc = self.charLocation.copy
      c = self.getChar
      ch = char(c)
      if ch == '\r':
        c = self.getChar
        ch = char(c)
      if ch != '\n':
        new(e)
        e.msg = "unexpected character: \\"
        e.location = cloc
        raise e
      endLocation.update(self.charLocation)
      continue
    else:
      new(e)
      e.msg = &"unexpected character: {ch}"
      e.location = self.charLocation.copy
      raise e
  if result.text == "":
    result.text = $text
  result.startpos = startLocation
  result.endpos = endLocation
  assert result.kind != Error
  # echo &"*** {result.text} ({result.startpos.line}, {result.startpos.column}) -> ({result.endpos.line}, {result.endpos.column})"

proc getAllTokens(self: Tokenizer): seq[Token] =
  result = @[]
  while true:
    var t = self.getToken
    result.add(t)
    if t.kind == EOF:
      break

# ------------------------------------------------------------------------
#  Parser
# ------------------------------------------------------------------------
type
  UnaryNode = ref object of ASTNode
    operand: ASTNode

  BinaryNode = ref object of ASTNode
    lhs, rhs: ASTNode

  SliceNode = ref object of ASTNode
    startIndex, stopIndex, step: ASTNode

  ListNode = ref object of ASTNode
    elements: seq[ASTNode]

  MappingNode = ref object of ASTNode
    elements: seq[(Token, ASTNode)]

  Parser = ref object of RootObj
    lexer: Tokenizer
    next: Token

proc newParser(stream: Stream): Parser =
  new(result)
  result.lexer = newTokenizer(stream)
  result.next = result.lexer.getToken

proc parserFromFile(path: string): Parser =
  var stream = newFileStream(path)
  newParser(stream)

proc parserFromSource(source: string): Parser =
  var stream = newStringStream(source)
  newParser(stream)

proc advance(self: Parser): TokenKind =
  self.next = self.lexer.getToken
  self.next.kind

func atEnd(self: Parser): bool =
  self.next.kind == EOF

proc expect(self: Parser, kind: TokenKind): Token =
  if self.next.kind != kind:
    var e: ref ParserError
    new(e)
    e.location = self.next.startpos
    e.msg = &"expected {kind} but got {self.next.kind}"
    raise e
  result = self.next
  discard self.advance()

proc consumeNewlines(self: Parser): TokenKind =
  result = self.next.kind
  while result == Newline:
    result = self.advance()

var
  expressionStarters = toHashSet([
    LeftCurly, LeftBracket, LeftParenthesis, At, Dollar, BackTick,
    Plus, Minus, BitwiseComplement, IntegerNumber, FloatNumber,
    Complex, TrueToken, FalseToken, None, Not, StringToken, Word
  ])

  valueStarters = toHashSet([
    Word, IntegerNumber, FloatNumber, Complex, StringToken, BackTick,
    None, TrueToken, FalseToken
  ])

proc strings(self: Parser): Token =
  result = self.next

  assert result.kind == StringToken
  if self.advance() == StringToken:

    var allText: seq[string] = @[]
    var allValue: seq[string] = @[]
    var kind: TokenKind
    var endpos: Location
    var t = result.text
    var v = result.value.stringValue
    var startpos = result.startpos

    while true:
      allText.add(t)
      allValue.add(v)
      t = self.next.text
      v = self.next.value.stringValue
      endpos = self.next.endpos
      kind = self.advance()
      if kind != StringToken:
        break
    allText.add(t)
    allValue.add(v)
    result = newToken(allText.join, TokenValue(kind: StringToken,
        stringValue: allValue.join))
    result.startpos = startpos
    result.endpos = endpos

proc value(self: Parser): Token =
  var kind = self.next.kind
  var e: ref ParserError

  if kind notin valueStarters:
    new(e)
    e.msg = &"unexpected when looking for value: {kind}"
    e.location = self.next.startpos
    raise e
  if kind == StringToken:
    result = self.strings
  else:
    result = self.next
    discard self.advance()

# Forward declarations
proc list(self: Parser): ListNode
proc mapping(self: Parser): MappingNode
proc expr(self: Parser): ASTNode
proc primary(self: Parser): ASTNode

proc newUnaryNode(op: TokenKind, operand: ASTNode): UnaryNode =
  new(result)
  result.kind = op
  result.operand = operand

proc atom(self: Parser): ASTNode =
  var kind = self.next.kind
  case kind:
  of LeftCurly:
    result = self.mapping()
  of LeftBracket:
    result = self.list()
  of Word, IntegerNumber, FloatNumber, Complex,
     StringToken, BackTick, TrueToken, FalseToken, None:
    result = self.value()
  of LeftParenthesis:
    discard self.advance()
    result = self.expr()
    discard self.expect(RightParenthesis)
  of Dollar:
    discard self.advance()
    discard self.expect(LeftCurly)
    var spos = self.next.startpos
    result = newUnaryNode(Dollar, self.primary())
    result.startpos = spos
    discard self.expect(RightCurly)
  else:
    var e: ref ParserError
    new(e)
    e.msg = &"unexpected: {kind}"
    e.location = self.next.startpos
    raise e

proc listBody(self: Parser): ListNode

proc trailer(self: Parser): (TokenKind, ASTNode) =

  proc invalidIndex(n: int, pos: Location) =
    var e: ref ParserError
    new(e)
    e.msg = &"invalid index at {pos}: expected 1 expression, found {n}"
    e.location = pos
    raise e

  var op = self.next.kind
  var node: ASTNode
  if op != LeftBracket:
    discard self.expect(Dot)
    node = self.expect(Word)
  else:
    var kind = self.advance()
    var isSlice = false
    var startIndex: ASTNode
    var stopIndex: ASTNode
    var step: ASTNode

    proc getSliceElement: ASTNode =
      var lb = self.listBody()
      var size = len(lb.elements)
      if size != 1:
        invalidIndex(size, lb.startpos)
      lb.elements[0]

    proc tryGetStep() =
      kind = self.advance()
      if kind != RightBracket:
        step = getSliceElement()

    if kind == Colon:
      # it's a slice like [:xyz:abc]
      isSlice = true
    else:
      var elem = getSliceElement()

      kind = self.next.kind
      if kind != Colon:
        node = elem
      else:
        startIndex = elem
        isSlice = true

    if isSlice:
      op = Colon
      # at this point startIndex is either nil (if foo[:xyz]) or a
      # value representing the start. We are pointing at the COLON
      # after the start value
      kind = self.advance()
      if kind == Colon: # no stop, but there might be a step
        tryGetStep()
      elif kind != RightBracket:
        stopIndex = getSliceElement()
        kind = self.next.kind
        if kind == Colon:
          tryGetStep()
      var sn: SliceNode

      new(sn)
      sn.kind = Colon
      sn.startIndex = startIndex
      sn.stopIndex = stopIndex
      sn.step = step
      node = sn
    discard self.expect(RightBracket)
  (op, node)

proc newBinaryNode(op: TokenKind, lhs, rhs: ASTNode): BinaryNode =
  new(result)
  result.kind = op
  result.lhs = lhs
  result.rhs = rhs

# proc `==`(n1, n2: BinaryNode): bool =
#   if n1.kind != n2.kind: return false
#   if n1.lhs != n2.lhs: return false
#   return n1.rhs == n2.rhs

proc primary(self: Parser): ASTNode =
  result = self.atom()
  var kind = self.next.kind

  while kind == Dot or kind == LeftBracket:
    var op: TokenKind
    var node: ASTNode

    (op, node) = self.trailer()
    result = newBinaryNode(op, result, node)
    kind = self.next.kind

proc mappingKey(self: Parser): Token =
  if self.next.kind == StringToken:
    result = self.strings()
  else:
    result = self.next
    discard self.advance()

proc mappingBody(self: Parser): MappingNode =
  var elements: seq[(Token, ASTNode)] = @[]
  var kind = self.consumeNewlines()
  var spos = self.next.startpos
  var e: ref ParserError

  if kind != RightCurly and kind != EOF:
    if kind != Word and kind != StringToken:

      new(e)
      e.msg = &"unexpected type for key: {kind}"
      e.location = spos
      raise e

    while kind == Word or kind == StringToken:
      var key = self.mappingKey()
      kind = self.next.kind
      if kind != Colon and kind != Assign:
        new(e)
        e.msg = &"expected key-value separator, found {kind}"
        e.location = self.next.startpos
        raise e
      discard self.advance()
      discard self.consumeNewlines()
      elements.add((key, self.expr()))
      kind = self.next.kind
      if kind == Newline or kind == Comma:
        discard self.advance()
        kind = self.consumeNewlines()
      elif kind != RightCurly and kind != EOF:
        new(e)
        e.msg = &"unexpected following value: {kind}"
        e.location = self.next.startpos
        raise e
  new(result)
  result.kind = LeftCurly
  result.elements = elements
  result.startpos = spos

proc mapping(self: Parser): MappingNode =
  discard self.expect(LeftCurly)
  result = self.mappingBody()
  discard self.expect(RightCurly)

proc listBody(self: Parser): ListNode =
  var elements: seq[ASTNode] = @[]
  var kind = self.consumeNewlines()
  var spos = self.next.startpos

  while kind in expressionStarters:
    elements.add(self.expr())
    kind = self.next.kind
    if kind != Newline and kind != Comma:
      break
    discard self.advance()
    kind = self.consumeNewlines()
  new(result)
  result.kind = LeftBracket
  result.elements = elements
  result.startpos = spos

proc list(self: Parser): ListNode =
  discard self.expect(LeftBracket)
  result = self.listBody()
  discard self.expect(RightBracket)

proc container(self: Parser): ASTNode =
  var kind = self.consumeNewlines()
  case kind:
  of LeftCurly:
    result = self.mapping()
  of LeftBracket:
    result = self.list()
  of Word, StringToken, EOF:
    result = self.mappingBody()
  else:
    var e: ref ParserError

    new(e)
    e.msg = &"unexpected token for container: {kind}"
    e.location = self.next.startpos
    raise e
  discard self.consumeNewlines()

proc unaryExpr(self: Parser): ASTNode

proc power(self: Parser): ASTNode =
  result = self.primary()
  while self.next.kind == Power:
    discard self.advance()
    # this way makes it right-associative ... not sure if that's
    # the best thing to do
    result = newBinaryNode(Power, result, self.unaryExpr())

# proc `==`(n1, n2: UnaryNode): bool =
#   if n1.kind != n2.kind: return false
#   return n1.operand == n2.operand

proc unaryExpr(self: Parser): ASTNode =
  var kind = self.next.kind
  var spos = self.next.startpos
  if kind != Plus and kind != Minus and kind != BitwiseComplement and kind != At:
    result = self.power()
  else:
    discard self.advance()
    result = newUnaryNode(kind, self.unaryExpr())
  result.startpos = spos

proc mulExpr(self: Parser): ASTNode =
  result = self.unaryExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == Star or kind == Slash or kind == SlashSlash or kind == Modulo:
    discard self.advance()
    result = newBinaryNode(kind, result, self.unaryExpr())
    kind = self.next.kind
  result.startpos = spos

proc addExpr(self: Parser): ASTNode =
  result = self.mulExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == Plus or kind == Minus:
    discard self.advance()
    result = newBinaryNode(kind, result, self.mulExpr())
    kind = self.next.kind
  result.startpos = spos

proc shiftExpr(self: Parser): ASTNode =
  result = self.addExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == LeftShift or kind == RightShift:
    discard self.advance()
    result = newBinaryNode(kind, result, self.addExpr())
    kind = self.next.kind
  result.startpos = spos

proc bitAndExpr(self: Parser): ASTNode =
  result = self.shiftExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == BitwiseAnd:
    discard self.advance()
    result = newBinaryNode(kind, result, self.shiftExpr())
    kind = self.next.kind
  result.startpos = spos

proc bitXorExpr(self: Parser): ASTNode =
  result = self.bitAndExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == BitwiseXor:
    discard self.advance()
    result = newBinaryNode(kind, result, self.bitAndExpr())
    kind = self.next.kind
  result.startpos = spos

proc bitOrExpr(self: Parser): ASTNode =
  result = self.bitXorExpr()
  var kind = self.next.kind
  var spos = self.next.startpos
  while kind == BitwiseOr:
    discard self.advance()
    result = newBinaryNode(kind, result, self.bitXorExpr())
    kind = self.next.kind
  result.startpos = spos

proc compOp(self: Parser): TokenKind =
  result = self.next.kind
  var shouldAdvance = false

  discard self.advance()
  if result == Is and self.next.kind == Not:
    result = IsNot
    shouldAdvance = true
  elif result == Not and self.next.kind == In:
    result = NotIn
    shouldAdvance = true
  if shouldAdvance:
    discard self.advance()

var comparisonOperators = toHashSet([
  LessThan, LessThanOrEqual, GreaterThan, GreaterThanOrEqual,
  Equal, Unequal, AltUnequal, Is, In, Not
])

proc comparison(self: Parser): ASTNode =
  var spos = self.next.startpos
  result = self.bitOrExpr()
  if self.next.kind in comparisonOperators:
    var op = self.compOp()
    result = newBinaryNode(op, result, self.bitOrExpr())
  result.startpos = spos

proc notExpr(self: Parser): ASTNode =
  var spos = self.next.startpos
  if self.next.kind != Not:
    result = self.comparison()
  else:
    discard self.advance()
    result = newUnaryNode(Not, self.notExpr())
  result.startpos = spos

proc andExpr(self: Parser): ASTNode =
  var spos = self.next.startpos
  result = self.notExpr()
  while self.next.kind == And:
    discard self.advance()
    result = newBinaryNode(And, result, self.notExpr())
  result.startpos = spos

proc expr(self: Parser): ASTNode =
  var spos = self.next.startpos
  result = self.andExpr()
  while self.next.kind == Or:
    discard self.advance()
    result = newBinaryNode(Or, result, self.andExpr())
  result.startpos = spos

# ------------------------------------------------------------------------
#  Config
# ------------------------------------------------------------------------

type
  ValueKind* = enum
    ##
    ## This type represents the kinds of configuration value supported.
    ##
    IntegerValue,
    FloatValue,
    ComplexValue,
    BoolValue,
    NoneValue,
    StringValue,
    DateTimeValue,
    ListValue,
    MappingValue,
    NestedConfigValue,
    InternalValue,
    InternalListValue,
    InternalMappingValue

  ConfigValue* = object
    ##
    ## This type represents an individual configuration value, though
    ## that value could be itself a list of values or a mapping of strings
    ## to values. The `kind` field indicates the type of value being
    ## represented, and correspondingly one of the other fields holds the
    ## actual data.
    ##
    case kind*: ValueKind
    of IntegerValue: intValue*: int64
    of FloatValue: floatValue*: float64
    of StringValue: stringValue*: string
    of BoolValue: boolValue*: bool
    of ComplexValue: complexValue*: Complex[float64]
    of DateTimeValue: dateTimeValue*: DateTime
    of ListValue: listValue*: seq[ConfigValue]
    of MappingValue: mappingValue*: Table[string, ConfigValue]
    of NestedConfigValue: configValue*: Config
    of InternalValue, NoneValue: otherValue: int32
    of InternalListValue: internalListValue: seq[ASTNode]
    of InternalMappingValue: internalMappingValue: ref Table[string, ASTNode]

  StringConverter* = proc(s: string, c: Config): ConfigValue

  Config = ref object of RootObj
    ##
    ## This type represents an entire configuration.
    ##
    noDuplicates*: bool
    strictConversions*: bool
    context*: Table[string, ConfigValue]
    path*: string
    includePath*: seq[string]
    stringConverter*: StringConverter
    cache: ref Table[string, ConfigValue]
    data: ref Table[string, ASTNode]
    parent: Config
    refsSeen: HashSet[ASTNode]

proc hash(node: ASTNode): Hash =
  var h: Hash = 0
  h = h !& hash(node.kind)
  h = h !& hash(node.startpos.line)
  h = h !& hash(node.startpos.column)
  result = !$h

proc `==`*(cv1, cv2: ConfigValue): bool

proc compareLists(list1, list2: seq[ConfigValue]): bool =
  if len(list1) != len(list2): return false
  for i in 0..high(list1):
    if list1[i] != list2[i]:
      return false
  true

proc compareMappings(map1, map2: Table[string, ConfigValue]): bool =
  if len(map1) != len(map2): return false
  for k, v in map1:
    if k notin map2:
      return false
    if v != map2[k]:
      return false
  true

proc `==`*(cv1, cv2: ConfigValue): bool =
  ##
  ## Compares two `ConfigValues` for equality.
  ##
  if cv1.kind != cv2.kind: return false
  case cv1.kind
  of IntegerValue: return cv1.intValue == cv2.intValue
  of FloatValue: return cv1.floatValue == cv2.floatValue
  of StringValue: return cv1.stringValue == cv2.stringValue
  of BoolValue: return cv1.boolValue == cv2.boolValue
  of ComplexValue: return cv1.complexValue == cv2.complexValue
  of DateTimeValue: return cv1.dateTimeValue == cv2.dateTimeValue
  of InternalValue, NoneValue: return cv1.otherValue == cv2.otherValue
  of ListValue: return compareLists(cv1.listValue, cv2.listValue)
  of MappingValue: return compareMappings(cv1.mappingValue, cv2.mappingValue)
  of NestedConfigValue: return cv1.configValue == cv2.configValue
  of InternalListValue: return cv1.internalListValue == cv2.internalListValue
  of InternalMappingValue: return cv1.internalMappingValue ==
      cv2.internalMappingValue

var ISO_DATETIME_PATTERN = re(r"^(\d{4})-(\d{2})-(\d{2})(([ T])(((\d{2}):(\d{2}):(\d{2}))(\.\d{1,6})?(([+-])(\d{2}):(\d{2})(:(\d{2})(\.\d{1,6})?)?)?))?$")
var ENV_VALUE_PATTERN = re(r"^\$(\w+)(\|(.*))?$")
var INTERPOLATION_PATTERN = re(r"\$\{([^}]+)\}")

proc notImplemented(s: string = "") =
  var e: ref CatchableError
  new(e)
  if s == "":
    e.msg = "Not implemented"
  else:
    e.msg = &"Not implemented: {s}"
  raise e

proc stringFor(v: ConfigValue): string =
  case v.kind
  of IntegerValue:
    result = $v.intValue
  of FloatValue:
    result = $v.floatValue
  of StringValue:
    result = v.stringValue
  of BoolValue:
    result = $v.boolValue
  of ListValue:
    var parts: seq[string] = @[]
    for item in v.listValue:
      parts.add(stringFor(item))
    result = "[" & parts.join(", ") & "]"
  of MappingValue:
    var parts: seq[string] = @[]
    for k, v in v.mappingValue:
      parts.add(&"{k}: {stringFor(v)}")
    result = "{" & parts.join(", ") & "}"
  else:
    notImplemented(&"stringFor for {v.kind}")

var MISSING = ConfigValue(kind: InternalValue, otherValue: 0)

proc get*(self: Config, key: string, default: ConfigValue = MISSING): ConfigValue
proc `[]`*(self: Config, key: string): ConfigValue

proc defaultStringConverter(s: string, cfg: Config): ConfigValue =
  result = ConfigValue(kind: StringValue, stringValue: s)
  var m = s.match(ISO_DATETIME_PATTERN)

  if m.isSome:
    var dt: DateTime
    var groups = m.get.captures
    var year = parseInt(groups[0])
    var month = parseInt(groups[1])
    var day = parseInt(groups[2])
    var hasTime = groups.contains(4)

    if not hasTime:
      dt = dateTime(year, Month(month), day)
      result = ConfigValue(kind: DateTimeValue, datetimeValue: dt)
    else:
      var hour = parseInt(groups[7])
      var minute = parseInt(groups[8])
      var second = parseInt(groups[9])
      var hasOffset = groups.contains(12)
      var nanos = 0

      if groups.contains(10):
        nanos = int(math.round(parseFloat(groups[10]) * 1.0e9))
      if not hasOffset:
        dt = dateTime(year, Month(month), day, hour, minute, second, nanos)
      else:
        var sign = if groups[12] == "-": -1 else: 1
        var ohour = parseInt(groups[13])
        var ominute = parseInt(groups[14])
        var osecond = if not groups.contains(16): 0 else: parseInt(groups[16])
        var tz = statictZ(sign * ohour, sign * ominute, sign * osecond)
        dt = dateTime(year, Month(month), day, hour, minute, second, nanos, tz)

    result = ConfigValue(kind: DateTimeValue, datetimeValue: dt)
    return
  m = s.match(ENV_VALUE_PATTERN)
  if m.isSome:
    var groups = m.get.captures
    var varName = groups[0]
    if existsEnv(varName):
      result = ConfigValue(kind: StringValue, stringValue: getEnv(varName))
    elif groups.contains(1): # has pipe
      result = ConfigValue(kind: StringValue, stringValue: groups[2])
    else:
      result = ConfigValue(kind: NoneValue)
    return
  m = s.find(INTERPOLATION_PATTERN)
  if m.isSome:
    var pos = 0
    var parts: seq[string] = @[]
    var failed = false

    for m in s.findIter(INTERPOLATION_PATTERN):
      var outer = m.captureBounds[-1]
      var inner = m.captureBounds[0]
      var path = s[inner.a..inner.b]

      if pos < outer.a:
        parts.add(s[pos..outer.a - 1])
      try:
        parts.add(stringFor(cfg[path]))
      except CatchableError:
        failed = true
        break
      pos = outer.b + 1
    if not failed:
      if pos < len(s):
        parts.add(s[pos..^1])
      result.stringValue = parts.join()

proc newConfig*(): Config =
  ##
  ## Creates a new configuration object, without any actual
  ## configuration.
  ##
  new(result)
  result.noDuplicates = true
  result.strictConversions = true
  result.includePath = @[]
  result.stringConverter = defaultStringConverter

proc cached*(self: Config): bool =
  ##
  ## See whether the configuration `self` has a cache.
  ##
  not self.cache.isNil

proc `cached=`*(self: Config, cache: bool) =
  ##
  ## Set whether the configuration `self` has a cache.
  ##
  if cache and self.cache.isNil:
    new(self.cache)
  elif not cache and not self.cache.isNil:
    self.cache = nil

proc newConfigError(msg: string, loc: Location): ref ConfigError =
  new(result)
  result.msg = msg
  result.location = loc

proc wrapMapping(self: Config, mn: MappingNode): ref Table[string, ASTNode] =
  new(result)
  var seen: ref Table[string, Location] = nil

  if self.noDuplicates:
    new(seen)
  for (t, v) in mn.elements:
    var k = (if t.kind == Word: t.text else: t.value.stringValue)
    if not seen.isNil:
      if k in seen:
        raise newConfigError(&"duplicate key {k} seen at {t.startpos} (previously at {seen[k]})", t.startpos)
      seen[k] = t.startpos
    result[k] = v

proc load*(self: Config, stream: Stream) =
  ##
  ## Load or reload the configuration `self` from the specified `stream`.
  ##
  var p = newParser(stream)
  var node = p.container()

  if not (node of MappingNode):
    raise newConfigError(&"root configuration must be a mapping", node.startpos)
  self.data = self.wrapMapping(MappingNode(node))
  if not self.cache.isNil:
    self.cache.clear()

proc rootDir*(self: Config): string =
  ##
  ## Get the parent directory of the `path` field of configuration
  ## `self`. This directory is searched for included configurations
  ## before `includePath` is searched.
  ##
  if len(self.path) == 0: getCurrentDir() else: self.path.parentDir()

proc loadFile*(self: Config, path: string) =
  ##
  ## Load or reload the configuration `self` from the specified `path`.
  ##
  var stream = newFileStream(path)
  self.path = path
  self.load(stream)

proc fromFile*(path: string): Config =
  ##
  ## Creates a new configuration object, with the configuration
  ## read from the file specified in `path`.
  ##
  result = newConfig()
  result.loadFile(path)

proc fromSource*(source: string): Config =
  ##
  ## Creates a new configuration object, with the configuration
  ## specified in `source`.
  ##
  result = newConfig()
  var stream = newStringStream(source)
  result.load(stream)

var IDENTIFIER_PATTERN = re(r"(*U)^(?!\d)(\w+)$")

proc isIdentifier(s: string): bool =
  s.match(IDENTIFIER_PATTERN).isSome

proc parsePath(s: string): ASTNode =

  proc fail(loc: Location) =
    raise newConfigError(&"invalid path: {s}", loc)

  var p = parserFromSource(s)

  if p.next.kind != Word:
    fail(p.next.startpos)
  result = p.primary()
  if not p.atEnd:
    fail(p.next.startpos)

proc visit(n: ASTNode, p: var seq[(TokenKind, ASTNode)]) =
  if n of Token:
    add(p, (Dot, n))
  elif n of UnaryNode:
    visit(UnaryNode(n).operand, p)
  elif n of BinaryNode:
    var bn = BinaryNode(n)
    visit(bn.lhs, p)
    p.add((bn.kind, bn.rhs))

proc unpackPath(node: ASTNode): seq[(TokenKind, ASTNode)] =
  result = @[]
  visit(node, result)

proc evaluate(self: Config, node: ASTNode): ConfigValue
proc getFromPath(self: Config, node: ASTNode): ConfigValue

proc get*(self: Config, key: string, default: ConfigValue = MISSING): ConfigValue =
  ##
  ## Get a value from the configuration `self` using `key`, and
  ## return `default` if not present in the configuration.
  ## The `key` can be a path as well as a simple key.
  ##
  if not self.cache.isNil and key in self.cache:
    result = self.cache[key]
  else:
    self.refsSeen.clear()
    if self.data.isNil:
      raise newConfigError("no data in configuration", nil)
    if key in self.data:
      result = self.evaluate(self.data[key])
    elif isIdentifier(key):
      if default == MISSING:
        raise newConfigError(&"not found in configuration: {key}", nil)
      result = default
    else:
      # not an identifier. Treat as a path
      try:
        result = self.getFromPath(parsePath(key))
      except ConfigError:
        if default == MISSING:
          raise
        result = default
    if not self.cache.isNil:
      self.cache[key] = result

proc unwrap(self: Config, v: ConfigValue): ConfigValue

proc `[]`*(self: Config, key: string): ConfigValue =
  ##
  ## Get a value from the configuration `self` using the indexing
  ## idiom, with `key` as the index. The `key` can be a path as
  ## well as a simple key.
  ##
  self.unwrap(self.get(key))

proc convertString(self: Config, s: string): ConfigValue =
  assert not self.stringConverter.isNil
  result = self.stringConverter(s, self)
  if self.strictConversions and result.kind == StringValue and
      result.stringValue == s:
    raise newConfigError(&"unable to convert string: {s}", nil)

proc evalAt(self: Config, node: UnaryNode): ConfigValue =
  var fn = self.evaluate(node.operand)

  if fn.kind != StringValue:
    raise newConfigError(&"@ operand must be a string, but is {fn.kind}", node.operand.startpos)
  var found = false
  var p = fn.stringValue
  if p.isAbsolute and p.fileExists:
    found = true
  else:
    var rp = p
    if self.rootDir != "":
      p = self.rootDir / rp
      found = p.fileExists
    if not found:
      for d in self.includePath:
        p = d / rp
        if p.fileExists:
          found = true
          break
  if not found:
    raise newConfigError(&"unable to locate {fn.stringValue}", node.operand.startpos)
  if self.path.fileExists and sameFile(self.path, p):
    raise newConfigError(&"configuration cannot include itself: {fn.stringValue}", node.operand.startpos)
  var parser = parserFromFile(p)
  var container = parser.container()
  if container of ListNode:
    var ln = ListNode(container)
    result = ConfigValue(kind: InternalListValue, internalListValue: ln[].elements)
  elif not (container of MappingNode):
    raise newConfigError(&"unexpected container type {container.type.name}", node.operand.startpos)
  else:
    var mn = MappingNode(container)
    var cfg = newConfig()
    cfg.noDuplicates = self.noDuplicates
    cfg.strictConversions = self.strictConversions
    cfg.context = self.context
    cfg.path = p
    cfg.includePath = self.includePath
    cfg.cached = self.cached
    cfg.parent = self
    cfg.data = cfg.wrapMapping(mn)
    result = ConfigValue(kind: NestedConfigValue, configValue: cfg)

proc toSource(node: ASTNode): string =
  if node of Token:
    var t = Token(node)
    case t.kind
    of Word, StringToken:
      result = t.text
    of IntegerNumber:
      result = $t.value.intValue
    of FloatNumber:
      result = $t.value.floatValue
    of TrueToken, FalseToken:
      result = $t.value.boolValue
    of Complex:
      result = $t.value.complexValue
    else:
      result = &"???{t.kind}???"
  else:
    var parts: seq[string] = @[]
    var path = unpackPath(node)
    assert path[0][0] == Dot
    assert path[0][1] of Token
    parts.add(Token(path[0][1]).text)
    if len(path) > 1:
      for i in 1 .. high(path):
        var op: TokenKind
        var operand: ASTNode

        (op, operand) = path[i]
        case op
        of Dot:
          parts.add(".")
          parts.add(Token(operand).text)
        of LeftBracket:
          parts.add("[")
          parts.add(toSource(operand))
          parts.add("]")
        of Colon:
          var sn = SliceNode(operand)
          parts.add("[")
          if not sn.startIndex.isNil:
            parts.add(toSource(sn.startIndex))
          parts.add(":")
          if not sn.stopIndex.isNil:
            parts.add(toSource(sn.stopIndex))
          if not sn.step.isNil:
            parts.add(":")
            parts.add(toSource(sn.step))
          parts.add("]")
        else:
          assert false, &"Unexpected path value: {op}, {repr operand}"
    result = parts.join

proc evalReference(self: Config, node: UnaryNode): ConfigValue =
  if node in self.refsSeen:
    var nodes: seq[ASTNode] = @[]

    for n in self.refsSeen:
      nodes.add(n)

    proc comp(x, y: ASTNode): int =
      if x.startpos.line != y.startpos.line:
        return x.startpos.line - y.startpos.line
      return x.startpos.column - y.startpos.column

    nodes.sort(comp)
    var parts: seq[string] = @[]
    for n in nodes:
      var s = toSource(UnaryNode(n).operand)
      parts.add(&"{s} {n.startpos}")
    raise newConfigError("circular reference: " & parts.join(", "), nil)

  self.refsSeen.incl(node)
  self.getFromPath(node.operand)

func isNumber(v: ConfigValue): bool =
  v.kind == IntegerValue or v.kind == FloatValue

proc isComplex(v: ConfigValue): bool =
  v.kind == ComplexValue

proc isMapping(v: ConfigValue): bool =
  v.kind == InternalMappingValue or v.kind == MappingValue

proc isList(v: ConfigValue): bool =
  v.kind == InternalListValue or v.kind == ListValue

proc toFloat(v: ConfigValue): float64 =
  if v.kind == FloatValue:
    v.floatValue
  else:
    float64(v.intValue)

proc toComplex(v: ConfigValue): Complex64 =
  result.im = 0
  if v.kind == ComplexValue:
    result = v.complexValue
  elif v.kind == IntegerValue:
    result.re = float64(v.intValue)
  else:
    result.re = v.floatValue

proc evalNegate(self: Config, node: UnaryNode): ConfigValue =
  var v = self.evaluate(node.operand)

  proc cannot() =
    raise newConfigError(&"cannot negate {v.kind}", node.startpos)

  if v.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue, intValue: -v.intValue)
  elif v.kind == FloatValue:
    result = ConfigValue(kind: FloatValue, floatValue: -v.floatValue)
  elif v.kind == ComplexValue:
    result = ConfigValue(kind: ComplexValue, complexValue: -v.complexValue)
  else:
    cannot()

proc asList(self: Config, list: seq[ASTNode]): seq[ConfigValue]
proc asDict(self: Config, map: ref Table[string, ASTNode]): Table[string, ConfigValue]
proc asDict*(self: Config): Table[string, ConfigValue]

proc toMapping(self: Config, v: ConfigValue): Table[string, ConfigValue] =
  if v.kind == MappingValue: v.mappingValue else: self.asDict(
      v.internalMappingValue)

proc mergeTables(self: Config, lhs, rhs: Table[string, ConfigValue]): Table[
    string, ConfigValue] =
  result = lhs
  for k, v in rhs:
    if k in result and isMapping(result[k]) and isMapping(v):
      var m = self.mergeTables(self.toMapping(result[k]), self.toMapping(v))
      result[k] = ConfigValue(kind: MappingValue, mappingValue: m)
    else:
      result[k] = v

proc mergeMaps(self: Config, lhs, rhs: ConfigValue): ConfigValue =
  var v1, v2: Table[string, ConfigValue]
  v1 = self.toMapping(lhs)
  v2 = self.toMapping(rhs)
  ConfigValue(kind: MappingValue, mappingValue: self.mergeTables(v1, v2))

proc evalAdd(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot add {lhs.kind} to {rhs.kind}", node.startpos)

  if lhs.kind == StringValue and rhs.kind == StringValue:
    result = ConfigValue(kind: StringValue, stringValue: lhs.stringValue &
        rhs.stringValue)
  elif isNumber(lhs) and isNumber(rhs):
    if lhs.kind != FloatValue and rhs.kind != FloatValue:
      result = ConfigValue(kind: IntegerValue, intValue: lhs.intValue + rhs.intValue)
    else:
      var v1 = toFloat(lhs)
      var v2 = toFloat(rhs)
      result = ConfigValue(kind: FloatValue, floatValue: v1 + v2)
  elif isComplex(lhs) or isComplex(rhs):
    if isComplex(lhs) and isComplex(rhs):
      result = ConfigValue(kind: ComplexValue, complexValue: lhs.complexValue +
          rhs.complexValue)
    elif isNumber(lhs) or isNumber(rhs):
      var c1 = toComplex(lhs)
      var c2 = toComplex(rhs)
      result = ConfigValue(kind: ComplexValue, complexValue: c1 + c2)
    else:
      cannot()
  elif isList(lhs) and isList(rhs):
    var l1, l2: seq[ConfigValue]

    if lhs.kind == ListValue:
      l1 = lhs.listValue
    else:
      l1 = self.asList(lhs.internalListValue)
    if rhs.kind == ListValue:
      l2 = rhs.listValue
    else:
      l2 = self.asList(rhs.internalListValue)
    result = ConfigValue(kind: ListValue, listValue: l1 & l2)
  elif isMapping(lhs) and isMapping(rhs):
    result = self.mergeMaps(lhs, rhs)
  else:
    cannot()

proc subMaps(self: Config, lhs, rhs: ConfigValue): ConfigValue =
  var r: Table[string, ConfigValue]
  var lv = self.toMapping(lhs)
  var rv = self.toMapping(rhs)

  for k, v in lv:
    if k notin rv:
      r[k] = v
  ConfigValue(kind: MappingValue, mappingValue: r)

proc evalSubtract(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot subtract {rhs.kind} from {lhs.kind}", node.startpos)

  if isNumber(lhs) and isNumber(rhs):
    if lhs.kind != FloatValue and rhs.kind != FloatValue:
      result = ConfigValue(kind: IntegerValue, intValue: lhs.intValue - rhs.intValue)
    else:
      var v1 = toFloat(lhs)
      var v2 = toFloat(rhs)
      result = ConfigValue(kind: FloatValue, floatValue: v1 - v2)
  elif isComplex(lhs) or isComplex(rhs):
    if isComplex(lhs) and isComplex(rhs):
      result = ConfigValue(kind: ComplexValue, complexValue: lhs.complexValue -
          rhs.complexValue)
    elif isNumber(lhs) or isNumber(rhs):
      var c1 = toComplex(lhs)
      var c2 = toComplex(rhs)
      result = ConfigValue(kind: ComplexValue, complexValue: c1 - c2)
    else:
      cannot()
  elif isMapping(lhs) and isMapping(rhs):
    result = self.subMaps(lhs, rhs)
  else:
    cannot()

proc evalMultiply(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot multiply {lhs.kind} by {rhs.kind}", node.startpos)

  if isNumber(lhs) and isNumber(rhs):
    if lhs.kind != FloatValue and rhs.kind != FloatValue:
      result = ConfigValue(kind: IntegerValue, intValue: lhs.intValue * rhs.intValue)
    else:
      var v1 = toFloat(lhs)
      var v2 = toFloat(rhs)
      result = ConfigValue(kind: FloatValue, floatValue: v1 * v2)
  elif isComplex(lhs) or isComplex(rhs):
    if isComplex(lhs) and isComplex(rhs):
      result = ConfigValue(kind: ComplexValue, complexValue: lhs.complexValue *
          rhs.complexValue)
    elif isNumber(lhs) or isNumber(rhs):
      var c1 = toComplex(lhs)
      var c2 = toComplex(rhs)
      result = ConfigValue(kind: ComplexValue, complexValue: c1 * c2)
    else:
      cannot()
  else:
    cannot()

proc evalDivide(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot divide {lhs.kind} by {rhs.kind}", node.startpos)

  if isNumber(lhs) and isNumber(rhs):
    var v1 = toFloat(lhs)
    var v2 = toFloat(rhs)
    result = ConfigValue(kind: FloatValue, floatValue: v1 / v2)
  elif isComplex(lhs) or isComplex(rhs):
    if isComplex(lhs) and isComplex(rhs):
      result = ConfigValue(kind: ComplexValue, complexValue: lhs.complexValue /
          rhs.complexValue)
    elif isNumber(lhs) or isNumber(rhs):
      var c1 = toComplex(lhs)
      var c2 = toComplex(rhs)
      result = ConfigValue(kind: ComplexValue, complexValue: c1 / c2)
    else:
      cannot()
  else:
    cannot()

proc evalIntegerDivide(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot integer-divide {lhs.kind} by {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue,
        intValue: lhs.intValue div rhs.intValue)
  else:
    cannot()

proc evalModulo(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot compute {lhs.kind} modulo {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue,
        intValue: lhs.intValue mod rhs.intValue)
  else:
    cannot()

proc evalLeftShift(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot left-shift {lhs.kind} by {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue,
        intValue: lhs.intValue shl rhs.intValue)
  else:
    cannot()

proc evalRightShift(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot right-shift {lhs.kind} by {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue,
        intValue: lhs.intValue shr rhs.intValue)
  else:
    cannot()

proc evalPower(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot raise {lhs.kind} to the power of {rhs.kind}", node.startpos)

  if isNumber(lhs) and isNumber(rhs):
    if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
      if rhs.intValue >= 0:
        result = ConfigValue(kind: IntegerValue, intValue: lhs.intValue ^ rhs.intValue)
      else:
        result = ConfigValue(kind: FloatValue, floatValue: pow(float64(
            lhs.intValue), float64(rhs.intValue)))
    else:
      var v1 = toFloat(lhs)
      var v2 = toFloat(rhs)
      result = ConfigValue(kind: FloatValue, floatValue: pow(v1, v2))
  elif isComplex(lhs) or isComplex(rhs):
    var v1 = toComplex(lhs)
    var v2 = toComplex(rhs)
    result = ConfigValue(kind: ComplexValue, complexValue: pow(v1, v2))
  else:
    cannot()

proc evalLogicalAnd(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)

  if not lhs.boolValue:
    return lhs

  var rhs = self.evaluate(node.rhs)
  rhs


proc evalLogicalOr(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)

  if lhs.boolValue:
    return lhs

  var rhs = self.evaluate(node.rhs)
  rhs

proc evalBitwiseAnd(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot bitwise-and {lhs.kind} and {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue, intValue: bitand(lhs.intValue, rhs.intValue))
  else:
    cannot()

proc evalBitwiseOr(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot bitwise-or {lhs.kind} and {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue, intValue: bitor(lhs.intValue, rhs.intValue))
  elif isMapping(lhs) and isMapping(rhs):
    result = self.mergeMaps(lhs, rhs)
  else:
    cannot()

proc evalBitwiseXor(self: Config, node: BinaryNode): ConfigValue =
  var lhs = self.evaluate(node.lhs)
  var rhs = self.evaluate(node.rhs)

  proc cannot() =
    raise newConfigError(&"cannot bitwise-xor {lhs.kind} and {rhs.kind}", node.startpos)

  if lhs.kind == IntegerValue and rhs.kind == IntegerValue:
    result = ConfigValue(kind: IntegerValue, intValue: bitxor(lhs.intValue, rhs.intValue))
  else:
    cannot()

proc evaluate(self: Config, node: ASTNode): ConfigValue =
  if node of Token:
    var t = Token(node)
    var v = t.value
    case t.kind
    of IntegerNumber:
      result = ConfigValue(kind: IntegerValue, intValue: v.intValue)
    of FloatNumber:
      result = ConfigValue(kind: FloatValue, floatValue: v.floatValue)
    of StringToken:
      result = ConfigValue(kind: StringValue, stringValue: v.stringValue)
    of Complex:
      result = ConfigValue(kind: ComplexValue, complexValue: v.complexValue)
    of TrueToken, FalseToken:
      result = ConfigValue(kind: BoolValue, boolValue: v.boolValue)
    of None:
      result = ConfigValue(kind: NoneValue)
    of Word:
      var k = t.text
      if k notin self.context:
        raise newConfigError(&"unknown variable: {k}", t.startpos)
      result = self.context[k]
    of BackTick:
      result = self.convertString(v.stringValue)
    else:
      raise newConfigError(&"Unable to evaluate token of this kind: {t.kind}", t.startpos)
  elif node of MappingNode:
    var mn = MappingNode(node)
    var wn = self.wrapMapping(mn)
    result = ConfigValue(kind: InternalMappingValue, internalMappingValue: wn)
  elif node of ListNode:
    var ln = ListNode(node)
    result = ConfigValue(kind: InternalListValue,
        internalListValue: ln.elements)
  else:
    case node.kind
    of At:
      result = self.evalAt(UnaryNode(node))
    of Dollar:
      result = self.evalReference(UnaryNode(node))
    of LeftCurly:
      # do we ever get here? MappingNode is handled above
      var mn = MappingNode(node)
      var wn = self.wrapMapping(mn)
      result = ConfigValue(kind: InternalMappingValue, internalMappingValue: wn)
    of Plus:
      result = self.evalAdd(BinaryNode(node))
    of Minus:
      if node of BinaryNode:
        result = self.evalSubtract(BinaryNode(node))
      else:
        result = self.evalNegate(UnaryNode(node))
    of Star:
      result = self.evalMultiply(BinaryNode(node))
    of Slash:
      result = self.evalDivide(BinaryNode(node))
    of SlashSlash:
      result = self.evalIntegerDivide(BinaryNode(node))
    of Modulo:
      result = self.evalModulo(BinaryNode(node))
    of LeftShift:
      result = self.evalLeftShift(BinaryNode(node))
    of RightShift:
      result = self.evalRightShift(BinaryNode(node))
    of Power:
      result = self.evalPower(BinaryNode(node))
    of And:
      result = self.evalLogicalAnd(BinaryNode(node))
    of Or:
      result = self.evalLogicalOr(BinaryNode(node))
    of BitwiseAnd:
      result = self.evalBitwiseAnd(BinaryNode(node))
    of BitwiseOr:
      result = self.evalBitwiseOr(BinaryNode(node))
    of BitwiseXor:
      result = self.evalBitwiseXor(BinaryNode(node))
    else:
      raise newConfigError(&"unable to evaluate node of kind: {node.kind}", node.startpos)

proc getSlice(self: Config, container: ConfigValue,
    sn: SliceNode): ConfigValue =
  var start, stop, step, size: int64

  proc doSlice[T](container: seq[T], start, stop, step: int64): seq[T] =
    var i = start
    var notDone = if step > 0: i <= stop else: i >= stop

    while notDone:
      result.add(container[i])
      i += step
      notDone = if step > 0: i <= stop else: i >= stop

  size = if container.kind == ListValue:
    len(container.listValue)
  else:
    len(container.internalListValue)
  if sn.step.isNil:
    step = 1
  else:
    var v = self.evaluate(sn.step)
    if v.kind != IntegerValue:
      raise newConfigError(&"step is not an integer, but {v.kind}", sn.step.startpos)
    step = v.intValue
    if step == 0:
      raise newConfigError("step cannot be zero", sn.step.startpos)

  if sn.startIndex.isNil:
    start = 0
  else:
    var v = self.evaluate(sn.startIndex)
    if v.kind != IntegerValue:
      raise newConfigError(&"start is not an integer, but {v.kind}", sn.startIndex.startpos)
    start = v.intValue
    if start < 0:
      if start >= -size:
        start += size
      else:
        start = 0
    elif start >= size:
      start = size - 1

  if sn.stopIndex.isNil:
    stop = size - 1
  else:
    var v = self.evaluate(sn.stopIndex)
    if v.kind != IntegerValue:
      raise newConfigError(&"stop is not an integer, but {v.kind}", sn.stopIndex.startpos)
    stop = v.intValue
    if stop < 0:
      if stop >= -size:
        stop += size
      else:
        stop = 0
    if stop > size:
      stop = size
    if step < 0:
      stop += 1
    else:
      stop -= 1
  if step < 0 and start < stop:
    swap(start, stop)

  if container.kind == ListValue:
    result = ConfigValue(kind: ListValue, listValue: doSlice[ConfigValue](
        container.listValue, start, stop, step))
  else:
    result = ConfigValue(kind: InternalListValue, internalListValue: doSlice[
        ASTNode](container.internalListValue, start, stop, step))

proc getFromPath(self: Config, node: ASTNode): ConfigValue =
  var elements = unpackPath(node)
  var node: ASTNode # OK to shadow the param, as not needed any more
  var op: TokenKind
  var operand: ASTNode

  proc notfound(k: string, loc: Location) =
    raise newConfigError(&"not found in configuration: {k}", loc)

  (op, operand) = elements[0]
  if op != Dot:
    raise newConfigError(&"unexpected path start: {op}", operand.startpos)

  var current = ConfigValue(kind: InternalMappingValue,
      internalMappingValue: self.data)
  var config = self
  for item in elements:
    (op, operand) = item
    if op == Dot:
      var t = Token(operand)
      assert t.kind == Word
      var k = t.text
      if current.kind == InternalMappingValue:
        if k notin current.internalMappingValue:
          notfound(k, t.startpos)
        node = current.internalMappingValue[k]
      elif current.kind == MappingValue:
        if k notin current.mappingValue:
          notfound(k, t.startpos)
        current = current.mappingValue[k]
        node = nil
      elif current.kind == NestedConfigValue:
        if k notin current.configValue.data:
          notfound(k, t.startpos)
        node = current.configValue.data[k]
      else:
        raise newConfigError(&"invalid container for key {k}: {current.kind}", t.startpos)
      if not node.isNil: # otherwise, current already set
        current = config.evaluate(node)
      if current.kind == NestedConfigValue:
        config = current.configValue
    elif op == LeftBracket:
      var idx = config.evaluate(operand)
      if idx.kind != IntegerValue:
        raise newConfigError("invalid index {idx.kind}", operand.startpos)
      var size: int
      if current.kind == ListValue:
        size = len(current.listValue)
      elif current.kind == InternalListValue:
        size = len(current.internalListValue)
      else:
        raise newConfigError(&"invalid container for numeric index: {current.kind}", operand.startpos)
      var n = idx.intValue
      if n < 0: n += size
      if n < 0 or n >= size:
        raise newConfigError(&"index out of range: is {idx.intValue}, must be between 0 and {size - 1}", operand.startpos)
      if current.kind == ListValue:
        current = current.listValue[n]
      else:
        current = config.evaluate(current.internalListValue[n])
    elif op == Colon:
      if current.kind != ListValue and current.kind != InternalListValue:
        raise newConfigError(&"invalid container for slicing: {current.kind}", operand.startpos)
      current = self.getSlice(current, SliceNode(operand))
    else:
      raise newConfigError(&"invalid path element {op}", operand.startpos)
  self.refsSeen.clear()
  config.unwrap(current)

proc asList(self: Config, list: seq[ASTNode]): seq[ConfigValue] =
  for node in list:
    var v = self.evaluate(node)
    if v.kind == InternalListValue:
      var lv = self.asList(v.internalListValue)
      v = ConfigValue(kind: ListValue, listValue: lv)
    elif v.kind == InternalMappingValue:
      var dv = self.asDict(v.internalMappingValue)
      v = ConfigValue(kind: MappingValue, mappingValue: dv)
    elif v.kind == NestedConfigValue:
      var dv = v.configValue.asDict()
      v = ConfigValue(kind: MappingValue, mappingValue: dv)
    result.add(v)

proc asDict(self: Config, map: ref Table[string, ASTNode]): Table[string, ConfigValue] =
  for k, v in map:
    var v = self.evaluate(v)
    if v.kind == InternalListValue:
      var lv = self.asList(v.internalListValue)
      v = ConfigValue(kind: ListValue, listValue: lv)
    elif v.kind == InternalMappingValue:
      var dv = self.asDict(v.internalMappingValue)
      v = ConfigValue(kind: MappingValue, mappingValue: dv)
    elif v.kind == NestedConfigValue:
      var dv = v.configValue.asDict()
      v = ConfigValue(kind: MappingValue, mappingValue: dv)
    result[k] = v

proc asDict(self: Config): Table[string, ConfigValue] =
  ##
  ## Get the configuration `cfg` as a `Table`. This will recurse into
  ##  included configurations.
  ##
  if self.data.isNil:
    raise newConfigError("no data in configuration", nil)
  self.asDict(self.data)

proc unwrap(self: Config, v: ConfigValue): ConfigValue =
  if v.kind == InternalMappingValue:
    var dv = self.asDict(v.internalMappingValue)
    result = ConfigValue(kind: MappingValue, mappingValue: dv)
  elif v.kind == InternalListValue:
    var lv = self.asList(v.internalListValue)
    result = ConfigValue(kind: ListValue, listValue: lv)
  else:
    result = v

proc getSubConfig*(self: Config, key: string): Config =
  ## Get an included configuration (sub-configuration)
  ## from `self` via `key`. This can be a path as well as a simple key.
  var conf = self[key]
  assert conf.kind == NestedConfigValue
  conf.configValue
