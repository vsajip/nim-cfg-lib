#
# Copyright 2016 by Vinay Sajip. All Rights Reserved.
#
import sequtils
import unittest

# Use include instead of import so as to be able to test non-exported stuff
include ../src/config

test "location":
  var loc = newLocation()
  check(loc.line == 1)
  check(loc.column == 1)
  loc.column = 3
  loc.nextLine()
  check(loc.line == 2)
  check(loc.column == 1)

test "positions":
  var f = open("pos.forms.cfg.txt")
  var positions: seq[seq[int]] = @[]
  for line in f.lines:
    var parts = line.split(' ').map(parseInt)
    positions.add(parts)
  f.close()
  var fs = newFileStream("forms.cfg")
  var tokenizer = newTokenizer(fs)
  for i, p in positions:
    var t = tokenizer.getToken
    # echo &"{t.text}:{t.startpos} -> {t.endpos}"
    check(t.startpos.line == p[0])
    check(t.startpos.column == p[1])
    check(t.endpos.line == p[2])
    check(t.endpos.column == p[3])

test "decoder":
  var fs = newFileStream("all_unicode.bin")
  var decoder = newUTF8Decoder(fs)

  for i in 0 .. 0xD7FF:
    var c = decoder.getRune()
    check(i == int(c))

  for i in 0xE000 .. 0x10FFFF:
    var c = decoder.getRune()
    check(i == int(c))

  check(fs.atEnd)

proc makeTokenizer(s: string) : Tokenizer =
  var ss = newStringStream(s)
  newTokenizer(ss)

proc compareLocations(expected, actual: Location) =
  check(expected.line == actual.line)
  check(expected.column == actual.column)

test "tokenizer":
  var t = makeTokenizer("foo")
  check(t.pushedBack.len == 0)
  t.charLocation.column = 47
  t.pushBack(R(216))
  t.charLocation.column = 2
  var c = t.getChar()
  check(c == R(216))
  check(t.charLocation.column == 47)
  check(t.location.column == 48)

  t = makeTokenizer("")
  var tk = t.getToken
  check(tk.kind == EOF)
  tk = t.getToken
  check(tk.kind == EOF)

  t = makeTokenizer("# a comment\n")
  tk = t.getToken()
  check(tk.kind == Newline)
  check(tk.text == "# a comment")
  check(EOF == t.getToken().kind)

  t = makeTokenizer("foo")
  tk = t.getToken()
  check(tk.kind == Word)
  check(tk.text == "foo")
  check(EOF == t.getToken().kind)

  if false: # TODO below
    t = makeTokenizer("'foo'")
    tk = t.getToken()
    check(StringToken == tk.kind)
    check("'foo'" == tk.text)
    check("foo" == tk.value.stringValue)
    compareLocations(newLocation(1, 1), tk.startpos)
    compareLocations(newLocation(1, 5), tk.endpos)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("2.71828")
    tk = t.getToken()
    check(FloatNumber == tk.kind)
    check("2.71828" == tk.text)
    check(2.71828 == tk.value.floatValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer(".5")
    tk = t.getToken()
    check(FloatNumber == tk.kind)
    check(".5" == tk.text)
    check(0.5 == tk.value.floatValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("0x123aBc")
    tk = t.getToken()
    check(UnsignedNumber == tk.kind)
    check("0x123aBc" == tk.text)
    check(uint64(0x123abc) == tk.value.intValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("0o123")
    tk = t.getToken()
    check(UnsignedNumber == tk.kind)
    check("0o123" == tk.text)
    check(uint64(83) == tk.value.intValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("0123")
    tk = t.getToken()
    check(UnsignedNumber == tk.kind)
    check("0123" == tk.text)
    check(uint64(83) == tk.value.intValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("1e8")
    tk = t.getToken()
    check(FloatNumber == tk.kind)
    check("1e8" == tk.text)
    check(1e8 == tk.value.floatValue)
    check(EOF == t.getToken().kind)

    t = makeTokenizer("1e-8")
    tk = t.getToken()
    check(FloatNumber == tk.kind)
    check("1e-8" == tk.text)
    check(1e-8 == tk.value.floatValue)
    check(EOF == t.getToken().kind)
