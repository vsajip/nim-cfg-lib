#
# Copyright 2016-2021 by Vinay Sajip (vinay_sajip@yahoo.co.uk). All Rights Reserved.
#
import complex
import parseutils
import streams
import strformat
import strutils
import tables
import unicode

type
  TokenKind* = enum
    EOF,
    Word,
    UnsignedNumber,
    SignedNumber,
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

  Location* = ref object of RootObj
    line* : int
    column* : int

  R = Rune

  DecoderError* = object of CatchableError

  RecognizerError* = object of CatchableError
    location: Location

  TokenizerError* = object of RecognizerError

  Any = ref RootObj

  TokenValue = object
    case kind: TokenKind
    of UnsignedNumber, SignedNumber: 
      intValue: uint64
    of FloatNumber:
      floatValue: float
    of StringToken:
      stringValue: string
    of TrueToken, FalseToken:
      boolValue: bool
    of Complex:
      complexValue: Complex[float64]
    else:
      otherValue: Any

  NumberReturnValue = TokenValue

  Token* = ref object of RootObj
    text: string
    value: TokenValue
    startpos: Location
    endpos: Location

  UTF8Decoder = ref object of RootObj
    stream: Stream

  PushBackData = tuple[c : Rune, loc: Location]

  Tokenizer = ref object of RootObj
    stream : UTF8Decoder
    location: Location
    charLocation: Location
    pushedBack: seq[PushBackData]

# ------------------------------------------------------------------------
#  Location
# ------------------------------------------------------------------------

proc newLocation(line: int = 1, column: int = 1) : Location = Location(line: line, column: column)

proc copy(source: Location) : Location = newLocation(source.line, source.column)

proc update(self: Location, source: Location) =
  self.line = source.line
  self.column = source.column

proc nextLine* (loc: Location) =
  loc.line += 1
  loc.column = 1

proc `$` (loc: Location) : string = &"({loc.line}, {loc.column})"

# ------------------------------------------------------------------------
#  Token
# ------------------------------------------------------------------------

proc newToken(kind: TokenKind, text: string) : Token =
  Token(value: TokenValue(kind: kind), text: text)

# ------------------------------------------------------------------------
#  UTF8 Decoder
# see http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
# ------------------------------------------------------------------------

const UTF8_ACCEPT = 0
const UTF8_REJECT = 12

const UTF8_LOOKUP = [
  0'u8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
  10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,

  # The second part is a transition table that maps a combination
  # of a state of the automaton and a character class to a state.
   0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
   12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
   12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
   12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
   12,36,12,12,12,12,12,12,12,12,12,12,
]

proc newUTF8Decoder(s : Stream) : UTF8Decoder =
  new(result)
  result.stream = s

proc getRune(self : UTF8Decoder) : Rune =
  var state : int = UTF8_ACCEPT
  var code_point: int
  var stream = self.stream
  var b : int

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

proc newTokenizer* (stream : Stream) : Tokenizer =
  new(result)
  result.stream = newUTF8Decoder(stream)
  result.location = newLocation()
  result.charLocation = newLocation()
  result.pushedBack = @[]

proc pushBack(self: Tokenizer, c: Rune) =
  if (c != R(0)) and ((c == R('\n') or not c.isWhiteSpace())):
    var loc = self.charLocation.copy
    var t : PushBackData = (c, loc)
    self.pushedBack.add(t)

proc getChar(self: Tokenizer) : Rune =
  if self.pushedBack.len() > 0:
    var pb = self.pushedBack.pop()
    result = pb.c
    self.charLocation.update(pb.loc)
    self.location.update(pb.loc)
  else:
    self.charLocation.update(self.location)
    result = self.stream.getRune
  if result != R(0):
    if result == R('\n'):
      self.location.nextLine
    else:
      self.location.column += 1

proc isHexDigit(c : Rune) : bool {.noSideEffect, gcsafe, locks: 0 .} =
  var ch = char(c).toUpperAscii
  if ch.isDigit:
    result = true
  else:
    result = ch >= 'A' and ch <= 'F'

proc isOctalDigit(c : Rune) : bool {.noSideEffect, gcsafe, locks: 0 .} =
  var ch = char(c)
  if not ch.isDigit:
    result = false
  else:
    result = ch <= '7'

proc asComplex(x: float64): Complex[float64] =
  result.re = 0
  result.im = x

const DIGITS = "0123456789ABCDEF"
const QUOTES = "\"'"
const PUNCT = {':': Colon, '-': Minus, '+': Plus, '*': Star, '/': Slash,
               '%': Modulo, ',': Comma, '.': Dot, '{': LeftCurly, '}': RightCurly,
               '[': LeftBracket, ']': RightBracket, '(': LeftParenthesis,
               ')': RightParenthesis, '@': At, '`': BackTick, '$': Dollar,
               '<': LessThan, '>': GreaterThan, '!': Not, '~': BitwiseComplement,
               '&': BitwiseAnd, '|': BitwiseOr, '^': BitwiseXor}.toTable

const KEYWORDS = {"true":TrueToken, "false": FalseToken, "null": None, "is": Is,
                  "in": In, "not": Not, "and": And, "or": Or}.toTable

proc parseUInt64(s : string, radix: range[8u..16u]) : uint64 =
  var str = unicode.toUpper(s)
  result = 0

  for i in 0 .. str.high:
    let c = str[i]
    assert c in DIGITS[0 ..< radix.int]
    result = result * radix + uint64(DIGITS.find c)

proc getToken(self: Tokenizer) : Token =
  result = newToken(Error, "")
  var startLocation = self.location.copy
  var endLocation = startLocation.copy
  var text : seq[Rune] = @[]

  proc getNumber() : NumberReturnValue =
    var inExponent = false
    var radix = 0
    var dotSeen = text[0] == R('.')
    var c : Rune
    var ch : char
    var e: ref TokenizerError
    var fv : float

    while true:
      c = self.getChar
      ch = char(int(c) and 0xFF)
      if ch == '.':
        dotSeen = true
      if ch == '\0':
        break
      if (radix == 0) and ch.isDigit:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 8) and c.isOctalDigit:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 16) and c.isHexDigit:
        text.add(c)
        endLocation.update(self.location)
      elif ch in "OXox" and text[0] == R('0'):
        radix = if ch in "Oo" : 8 else: 16
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
      elif (radix == 0) and (ch == '-') and text.find(R('-')) < 0 and inExponent:
        text.add(c)
        endLocation.update(self.location)
      elif (radix == 0) and (ch in "eE") and text.find(R('e')) < 0 and text.find(R('E')) < 0:
        text.add(c)
        endLocation.update(self.location)
        inExponent = true
      else:
        if (radix == 0) and ch in "jJ":
          text.add(c)
          endLocation.update(self.location)
          result.kind = Complex
        else:
          if ch != '.' and not ch.isAlphaNumeric:
            self.pushBack(c)
          else:
            new(e)
            e.msg = &"invalid character in number: {ch}"
            e.location = self.charLocation.copy
            raise e
        break
    try:
      if radix != 0:
        result = TokenValue(kind: UnsignedNumber, intValue: parseUInt64($text, radix))
      elif char(text[^1]) in "jJ":
        discard parseFloat($text, fv)
        result = TokenValue(kind: Complex, complexValue: asComplex(fv))
      elif inExponent or dotSeen:
        discard parseFloat($text, fv)
        result = TokenValue(kind: FloatNumber, floatValue: fv)
      else:
        radix = if char(text[0]) == '0': 8 else: 10
        result = TokenValue(kind: UnsignedNumber, intValue: parseUInt64($text, radix))
    except ValueError:
      new(e)
      e.msg = &"badly-formed number: {text}"
      e.location = startLocation.copy
      raise e

  var c : Rune
  var ch: char
  var e: ref TokenizerError
  var nv : NumberReturnValue

  while true:
    c = self.getChar
    ch = char(c)

    startLocation.update(self.charLocation)
    endLocation.update(self.charLocation)

    if ch == '\0':
      result.value = TokenValue(kind: EOF)
      break
    elif ch == '#':
      result.text = &"#{self.stream.stream.readLine}"
      self.location.nextLine
      endLocation.update(self.charLocation)
      result.value = TokenValue(kind: Newline)
      break
    elif ch == '\n':
      result.value = TokenValue(kind: Newline)
      result.text.add(ch)
      endLocation.update(self.location)
      break
    elif ch == '\r':
      c = self.getChar
      ch = char(c)
      if ch != '\n':
        self.pushBack(c)
      result.value = TokenValue(kind: Newline)
      endLocation.update(self.location)
      break
    elif c.isWhiteSpace:
      continue
    if ch in QUOTES:
      text.add(c)
      endLocation.update(self.charLocation)
      var quote = ch
      result.value = TokenValue(kind: StringToken)
      var escaped = false
      var multiline = false
      var c1 = self.getChar
      var ch1 = char(c1)
      if ch1 != quote:
          self.pushBack(c1)
      else:
        var c2 = self.getChar
        var ch2 = char(c2)
        if ch2 != quote:
          self.pushBack(c2)
          self.pushBack(c1)
        else:
          multiline = true
          text.add(c2)
          text.add(c2)
        # Keep the quoting string around for later
      # var quoter = $text
      while true:
        c = self.getChar
        ch = char(c)
        if ch == '\0':
          break
        text.add(c)
        endLocation.update(self.charLocation)
        if (ch == quote) and not escaped:
          if not multiline or (len(text) >= 6 and ($text[^3..^1] == $text[0..2]) and text[-4] != R('\\')):
            break
        if ch == '\\':
          escaped = not escaped
        else:
          escaped = false
      # echo &"*** string loop done: {text}"
      if ch == '\0':
        new(e)
        e.msg = &"unterminated quoted string: {text}"
        e.location = startLocation.copy
        raise e
      break
    elif c.isAlpha or (ch == '_'):
      text.add(c)
      endLocation.update(self.charLocation)
      result.value = TokenValue(kind: Word)
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
        result.value = TokenValue(kind: KEYWORDS[s])
        # result.value = KEYWORD_VALUES[s]
        if result.value.kind == TrueToken:
          result.value.boolValue = true
        elif result.value.kind == FalseToken:
          result.value.boolValue = false
        else:
          result.value.otherValue = nil
      break
    elif ch.isDigit:
      text.add(c)
      endLocation.update(self.charLocation)
      nv = getNumber()
      result.value = nv
      #result.value = nv.value
      break
    elif ch == '=':
      var loc = self.charLocation.copy
      var nc = self.getChar
      var nch = char(nc)
      if nch == '\0' or nch != '=':
        new(e)
        e.msg = "unexpected solitary '-'"
        e.location = loc
        raise e
      text.add(c)
      text.add(nc)
      endLocation.update(self.charLocation)
      break
    elif ch in PUNCT:
      # echo &"PUNCT: {ch}"
      text.add(c)
      endLocation.update(self.charLocation)
      result.value.kind = PUNCT[ch]
      if ch == '.':
        c = self.getChar
        ch = char(c)
        if ch != '\0':
            if not ch.isDigit:
              self.pushBack(c)
            else:
              text.add(c)
              endLocation.update(self.charLocation)
              nv = getNumber()
              result.value = nv
              break
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
              result.value.kind = LeftShift
            elif ch == '>':
              result.value.kind = AltUnequal
            elif ch == '=':
              result.value.kind = LessThanOrEqual
            pb = false
        elif pch == '>':
          if ch in ">=":
            text.add(c)
            endLocation.update(self.charLocation)
            if ch == '>':
              result.value.kind = RightShift
            else:
              result.value.kind = GreaterThanOrEqual
            pb = false
        elif pch in "!=":
          if ch == '=':
            text.add(c)
            endLocation.update(self.charLocation)
            result.value.kind = Unequal
            pb = false
          else:
            pb = true
        elif pch in "*/=":
          if ch == pch:
            text.add(c)
            endLocation.update(self.charLocation)
            if pch == '*':
              result.value.kind = Power
            elif pch == '/':
              result.value.kind = SlashSlash
            else:
              result.value.kind = Equal
            pb = false
        if pb:
            self.pushBack(c)
      break
    else:
      new(e)
      e.msg = &"unexpected character: {ch}"
      e.location = self.charLocation.copy
      raise e
  if result.text == "":
    result.text = $text
  result.startpos = startLocation
  result.endpos = endLocation
  # echo &"*** {result.text} ({result.startpos.line}, {result.startpos.column}) -> ({result.endpos.line}, {result.endpos.column})"
