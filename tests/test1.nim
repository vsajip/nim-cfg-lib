#
# Copyright 2016-2021 by Vinay Sajip. All Rights Reserved.
#
import sequtils
import unittest

# Use include instead of import so as to be able to test non-exported stuff
include ../src/config

proc dataFilePath(paths: varargs[string]): string =
  "tests" / "resources" / paths.join("/")

var separatorPattern = re"^-- ([A-Z]\d+) [-]+"

proc loadData(fn: string): Table[string, string] =
  result = initTable[string, string]()
  var key = ""
  var value: seq[string] = @[]

  for line in lines(fn):
    var matched = line.match(separatorPattern)
    if not matched.isSome:
      value.add(line)
    else:
      var matches = matched.get.captures
      if len(key) > 0 and len(value) > 0:
        result[key] = value.join("\n")
      key = matches[0]
      value = @[]

#
# Tokenizer
#
test "location":
  var loc = newLocation()
  check(loc.line == 1)
  check(loc.column == 1)
  loc.column = 3
  loc.nextLine()
  check(loc.line == 2)
  check(loc.column == 1)

test "tokenizer positions":
  var f = open(dataFilePath("pos.forms.cfg.txt"))
  var positions: seq[seq[int]] = @[]
  for line in f.lines:
    var parts = line.split(' ').map(parseInt)
    positions.add(parts)
  f.close()
  var fs = newFileStream(dataFilePath("forms.cfg"))
  var tokenizer = newTokenizer(fs)
  for i, p in positions:
    var t = tokenizer.getToken
    check(t.startpos.line == p[0])
    check(t.startpos.column == p[1])
    check(t.endpos.line == p[2])
    check(t.endpos.column == p[3])

test "decoder":
  var fs = newFileStream(dataFilePath("all_unicode.bin"))
  var decoder = newUTF8Decoder(fs)

  for i in 0 .. 0xD7FF:
    var c = decoder.getRune()
    check(i == int(c))

  for i in 0xE000 .. 0x10FFFF:
    var c = decoder.getRune()
    check(i == int(c))

  check(fs.atEnd)

func makeTokenizer(s: string): Tokenizer =
  var ss = newStringStream(s)
  newTokenizer(ss)

func L(l: int, c: int): Location = newLocation(l, c)

func T(t: string, v: TokenValue, sloc: Location = L(1, 1),
    eloc: Location = L(1, 1)): Token =
  result = newToken(t, v)
  result.startpos = sloc.copy
  result.endpos = eloc.copy

proc compareNodes(n1, n2: ASTNode) =
  check isNil(n1) == isNil(n2)
  if isNil(n1): return # must both be nil
  check n1.kind == n2.kind
  check n1.type.name == n2.type.name
  if n1 of Token and n2 of Token:
    var t1 = Token(n1)
    var t2 = Token(n2)
    check t1.text == t2.text
    check t1.value == t2.value
  elif n1 of BinaryNode and n2 of BinaryNode:
    var bn1 = BinaryNode(n1)
    var bn2 = BinaryNode(n2)
    compareNodes(bn1.lhs, bn2.lhs)
    compareNodes(bn1.rhs, bn2.rhs)
  elif n1 of UnaryNode and n2 of UnaryNode:
    var un1 = UnaryNode(n1)
    var un2 = UnaryNode(n2)
    compareNodes(un1.operand, un2.operand)
  elif n1 of SliceNode and n2 of SliceNode:
    var sn1 = SliceNode(n1)
    var sn2 = SliceNode(n2)
    compareNodes(sn1.startIndex, sn2.startIndex)
    compareNodes(sn1.stopIndex, sn2.stopIndex)
    compareNodes(sn1.step, sn2.step)

proc compareArrays[T](expected, actual: seq[T]) =
  check(len(expected) == len(actual))
  for i in 0 .. high(expected):
    if expected[i] != actual[i]:
      echo &"failing at {i}: e = {expected[i]}, a = {actual[i]}"
    check(expected[i] == actual[i])

test "tokenizer basic":

  var t = makeTokenizer("foo")
  check(t.pushedBack.len == 0)
  t.charLocation.column = 47
  t.pushBack(R(216))
  t.charLocation.column = 2
  var c = t.getChar()
  check(c == R(216))
  check(t.charLocation.column == 47)
  check(t.location.column == 48)

test "tokenizer fragments":

  type
    TCase = object
      text: string
      token: Token

  var l1 = L(1, 1)
  var l2 = L(1, 2)
  var l6 = L(1, 6)
  var cases: seq[TCase] = @[
    TCase(text: "", token: T("", TokenValue(kind: EOF))),
    TCase(text: "# a comment\n", token: T("# a comment", TokenValue(
        kind: Newline), L(1, 1), L(2, 0))),
    TCase(text: "foo", token: T("foo", TokenValue(kind: Word), l1, L(
        1, 3))),
    TCase(text: "'foo'", token: T("'foo'", TokenValue(kind: StringToken,
        stringValue: "foo"), l1, L(1, 5))),
    TCase(text: "2.71828", token: T("2.71828", TokenValue(
        kind: FloatNumber, floatValue: 2.71828), l1, L(1, 7))),
    TCase(text: ".5", token: T(".5", TokenValue(kind: FloatNumber,
        floatValue: 0.5), l1, l2)),
    TCase(text: "-.5", token: T("-.5", TokenValue(kind: FloatNumber,
        floatValue: -0.5), l1, L(1, 3))),
    TCase(text: "0x123aBc", token: T("0x123aBc", TokenValue(
        kind: IntegerNumber, intValue: 0x123abc), l1, L(1, 8))),
    TCase(text: "0o123", token: T("0o123", TokenValue(
        kind: IntegerNumber, intValue: 83), l1, L(1, 5))),
    TCase(text: "0123", token: T("0123", TokenValue(kind: IntegerNumber,
        intValue: 83), l1, L(1, 4))),
    TCase(text: "0b0001_0110_0111", token: T("0b0001_0110_0111",
        TokenValue(kind: IntegerNumber, intValue: 0x167), l1, L(1, 16))),
    TCase(text: "1e8", token: T("1e8", TokenValue(kind: FloatNumber,
        floatValue: 1e8), l1, L(1, 3))),
    TCase(text: "1e-8", token: T("1e-8", TokenValue(kind: FloatNumber,
        floatValue: 1e-8), l1, L(1, 4))),
    TCase(text: "-4", token: T("-4", TokenValue(kind: IntegerNumber,
        intValue: -4), l1, L(1, 2))),
    TCase(text: "-4e8", token: T("-4e8", TokenValue(kind: FloatNumber,
        floatValue: -4e8), l1, L(1, 4))),
    TCase(text: "\"\"", token: T("\"\"", TokenValue(kind: StringToken,
        stringValue: ""), l1, l2)),
    TCase(text: "''", token: T("''", TokenValue(kind: StringToken,
        stringValue: ""), l1, l2)),
    TCase(text: "''''''", token: T("''''''", TokenValue(
        kind: StringToken, stringValue: ""), l1, l6)),
    TCase(text: "\"\"\"\"\"\"", token: T("\"\"\"\"\"\"", TokenValue(
        kind: StringToken, stringValue: ""), l1, l6)),
    TCase(text: "\"\"\"abc\ndef\n\"\"\"", token: T(
        "\"\"\"abc\ndef\n\"\"\"", TokenValue(kind: StringToken,
        stringValue: "abc\ndef\n"), l1, L(3, 3))),
    TCase(text: "'\\n'", token: T("'\\n'", TokenValue(kind: StringToken,
        stringValue: "\n"), l1, L(1, 4))),
    TCase(text: "`foo`", token: T("`foo`", TokenValue(kind: BackTick,
        stringValue: "foo"), l1, L(1, 5))),
    TCase(text: "==", token: T("==", TokenValue(kind: Equal,
        otherValue: 0))),
    TCase(text: "-2.0999999e-08", token: T("-2.0999999e-08", TokenValue(
        kind: FloatNumber, floatValue: -2.0999999e-08), l1, L(1, 14))),
  ]

  for tcase in cases:
    var t = makeTokenizer(tcase.text)
    # echo &"Checking {tcase.text}:"
    var tk = t.getToken
    check(tk.value == tcase.token.value)
    check(tcase.token.startpos == tk.startpos)
    check(tcase.token.endpos == tk.endpos)
    tk = t.getToken
    check(tk.kind == EOF)

# template print(s: varargs[string, `$`]) =
#   for x in s:
#     stdout.write x

# proc dumpTokens(key: string, tokens: seq[Token]) =
#   echo &"\"{key}\": @["
#   for t in tokens:
#     print "  T(\""
#     print escape(t.text), "\", TokenValue(kind: "
#     print t.kind, ", "
#     case t.kind:
#     of IntegerNumber: print &"intValue: {t.value.intValue}), "
#     of FloatNumber: print &"floatValue: {t.value.floatValue}), "
#     of StringToken, BackTick: print &"stringValue: \"{escape(t.value.stringValue)}\"), "
#     of TrueToken, FalseToken: print &"boolValue: {t.value.boolValue}), "
#     of Complex: print &"complexValue: complex64{t.value.complexValue}), "
#     else: print "otherValue: 0), "
#     print "loc", t.startpos, ", loc", t.endpos
#     echo "),"
#   echo "],\n"

test "tokenizer data":
  var cases = loadData(dataFilePath("testdata.txt"))
  var expected: Table[string, seq[Token]] = {
    "C01": @[
      T("# Basic mapping with a single key-value pair and comment",
          TokenValue(kind: Newline), L(1, 1), L(2, 0)),
      T("message", TokenValue(kind: Word), L(2, 1),
          L(2, 7)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("\'Hello, world!\'", TokenValue(kind: StringToken,
          stringValue: "Hello, world!"), L(2, 10), L(2, 24)),
      T("", TokenValue(kind: EOF), L(2, 25), L(2,
          25)),
    ],

    "C02": @[
      T("# Mapping with multiple key-value pairs", TokenValue(
          kind: Newline), L(1, 1), L(2, 0)),
      T("message", TokenValue(kind: Word), L(2, 1),
          L(2, 7)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("\'Hello, world!\'", TokenValue(kind: StringToken,
          stringValue: "Hello, world!"), L(2, 10), L(2, 24)),
      T("\n", TokenValue(kind: Newline), L(2, 25), L(
          3, 0)),
      T("ident", TokenValue(kind: Word), L(3, 1), L(
          3, 5)),
      T(":", TokenValue(kind: Colon), L(3, 6), L(3, 6)),
      T("42", TokenValue(kind: IntegerNumber, intValue: 42), L(3, 8),
          L(3, 9)),
      T("", TokenValue(kind: EOF), L(3, 10), L(3,
          10)),
    ],

    "C03": @[
      T("# Mapping with interspersed comments", TokenValue(
          kind: Newline), L(1, 1), L(2, 0)),
      T("message", TokenValue(kind: Word), L(2, 1),
          L(2, 7)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("\'Hello, world!\'", TokenValue(kind: StringToken,
          stringValue: "Hello, world!"), L(2, 10), L(2, 24)),
      T("\n", TokenValue(kind: Newline), L(2, 25), L(
          3, 0)),
      T("# A separating comment", TokenValue(kind: Newline,
          otherValue: 0), L(3, 1), L(4, 0)),
      T("ident", TokenValue(kind: Word), L(4, 1), L(
          4, 5)),
      T(":", TokenValue(kind: Colon), L(4, 6), L(4, 6)),
      T("43", TokenValue(kind: IntegerNumber, intValue: 43), L(4, 8),
          L(4, 9)),
      T("", TokenValue(kind: EOF), L(4, 10), L(4,
          10)),
    ],

    "C04": @[
      T("# With included trailing commas for both list and mapping",
          TokenValue(kind: Newline), L(1, 1), L(2, 0)),
      T("numbers", TokenValue(kind: Word), L(2, 1),
          L(2, 7)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("[", TokenValue(kind: LeftBracket), L(2, 10),
          L(2, 10)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(2, 11),
          L(2, 11)),
      T(",", TokenValue(kind: Comma), L(2, 12), L(2,
          12)),
      T("0x012", TokenValue(kind: IntegerNumber, intValue: 18), L(2,
          14), L(2, 19)),
      T(",", TokenValue(kind: Comma), L(2, 19), L(2,
          19)),
      T("013", TokenValue(kind: IntegerNumber, intValue: 11), L(2,
          21), L(2, 24)),
      T(",", TokenValue(kind: Comma), L(2, 24), L(2,
          24)),
      T("1014", TokenValue(kind: IntegerNumber, intValue: 1014), L(2,
          26), L(2, 30)),
      T(",", TokenValue(kind: Comma), L(2, 30), L(2,
          30)),
      T("]", TokenValue(kind: RightBracket), L(2, 32),
          L(2, 32)),
      T(",", TokenValue(kind: Comma), L(2, 33), L(2,
          33)),
      T("", TokenValue(kind: EOF), L(2, 34), L(2,
          34)),
    ],

    "C05": @[
      T("complex", TokenValue(kind: Word), L(1, 1),
          L(1, 7)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("[", TokenValue(kind: LeftBracket), L(1, 10),
          L(1, 10)),
      T("0j", TokenValue(kind: Complex, complexValue: complex64(0.0,
          0.0)), L(1, 11), L(1, 13)),
      T(",", TokenValue(kind: Comma), L(1, 13), L(1,
          13)),
      T("1j", TokenValue(kind: Complex, complexValue: complex64(0.0,
          1.0)), L(1, 15), L(1, 17)),
      T(",", TokenValue(kind: Comma), L(1, 17), L(1,
          17)),
      T("\n", TokenValue(kind: Newline), L(1, 18), L(
          2, 0)),
      T(".4j", TokenValue(kind: Complex, complexValue: complex64(0.0,
          0.4)), L(2, 11), L(2, 14)),
      T(",", TokenValue(kind: Comma), L(2, 14), L(2,
          14)),
      T("0.7j", TokenValue(kind: Complex, complexValue: complex64(0.0,
          0.7)), L(2, 16), L(2, 20)),
      T("]", TokenValue(kind: RightBracket), L(2, 20),
          L(2, 20)),
      T("", TokenValue(kind: EOF), L(2, 21), L(2,
          21)),
    ],

    "C06": @[
      T("nested", TokenValue(kind: Word), L(1, 1), L(
          1, 6)),
      T(":", TokenValue(kind: Colon), L(1, 7), L(1, 7)),
      T("{", TokenValue(kind: LeftCurly), L(1, 9), L(
          1, 9)),
      T("a", TokenValue(kind: Word), L(1, 10), L(1,
          10)),
      T(":", TokenValue(kind: Colon), L(1, 11), L(1,
          11)),
      T("b", TokenValue(kind: Word), L(1, 13), L(1,
          13)),
      T(",", TokenValue(kind: Comma), L(1, 14), L(1,
          14)),
      T("c", TokenValue(kind: Word), L(1, 16), L(1,
          16)),
      T(":", TokenValue(kind: Colon), L(1, 18), L(1,
          18)),
      T("d", TokenValue(kind: Word), L(1, 20), L(1,
          20)),
      T(",", TokenValue(kind: Comma), L(1, 21), L(1,
          21)),
      T("\'e f\'", TokenValue(kind: StringToken, stringValue: "e f"),
          L(1, 23), L(1, 27)),
      T(":", TokenValue(kind: Colon), L(1, 28), L(1,
          28)),
      T("\'g\'", TokenValue(kind: StringToken, stringValue: "g"), L(1,
          30), L(1, 32)),
      T("}", TokenValue(kind: RightCurly), L(1, 33),
          L(1, 33)),
      T("", TokenValue(kind: EOF), L(1, 34), L(1,
          34)),
    ],

    "C07": @[
      T("foo", TokenValue(kind: Word), L(1, 1), L(1, 3)),
      T(":", TokenValue(kind: Colon), L(1, 4), L(1, 4)),
      T("[", TokenValue(kind: LeftBracket), L(1, 6),
          L(1, 6)),
      T("1", TokenValue(kind: IntegerNumber, intValue: 1), L(1, 7),
          L(1, 7)),
      T(",", TokenValue(kind: Comma), L(1, 8), L(1, 8)),
      T("2", TokenValue(kind: IntegerNumber, intValue: 2), L(1, 10),
          L(1, 10)),
      T(",", TokenValue(kind: Comma), L(1, 11), L(1,
          11)),
      T("3", TokenValue(kind: IntegerNumber, intValue: 3), L(1, 13),
          L(1, 13)),
      T("]", TokenValue(kind: RightBracket), L(1, 14),
          L(1, 14)),
      T("\n", TokenValue(kind: Newline), L(1, 15), L(
          2, 0)),
      T("\n", TokenValue(kind: Newline), L(2, 1), L(
          3, 0)),
      T("\n", TokenValue(kind: Newline), L(3, 1), L(
          4, 0)),
      T("bar", TokenValue(kind: Word), L(4, 1), L(4, 3)),
      T(":", TokenValue(kind: Colon), L(4, 4), L(4, 4)),
      T("[", TokenValue(kind: LeftBracket), L(4, 6),
          L(4, 6)),
      T("\n", TokenValue(kind: Newline), L(4, 7), L(
          5, 0)),
      T("4", TokenValue(kind: IntegerNumber, intValue: 4), L(5, 5),
          L(5, 5)),
      T("+", TokenValue(kind: Plus), L(5, 7), L(5, 7)),
      T("x", TokenValue(kind: Word), L(5, 9), L(5, 9)),
      T("# random comment", TokenValue(kind: Newline),
          L(5, 13), L(6, 0)),
      T("\n", TokenValue(kind: Newline), L(6, 1), L(
          7, 0)),
      T("\n", TokenValue(kind: Newline), L(7, 1), L(
          8, 0)),
      T("5", TokenValue(kind: IntegerNumber, intValue: 5), L(8, 5),
          L(8, 5)),
      T(",", TokenValue(kind: Comma), L(8, 6), L(8, 6)),
      T("# another one", TokenValue(kind: Newline), L(
          8, 13), L(9, 0)),
      T("\n", TokenValue(kind: Newline), L(9, 1), L(
          10, 0)),
      T("6", TokenValue(kind: IntegerNumber, intValue: 6), L(10, 5),
          L(10, 5)),
      T("# and one more", TokenValue(kind: Newline), L(
          10, 13), L(11, 0)),
      T("]", TokenValue(kind: RightBracket), L(11, 1),
          L(11, 1)),
      T("\n", TokenValue(kind: Newline), L(11, 2), L(
          12, 0)),
      T("baz", TokenValue(kind: Word), L(12, 1), L(
          12, 3)),
      T(":", TokenValue(kind: Colon), L(12, 4), L(12, 4)),
      T("{", TokenValue(kind: LeftCurly), L(12, 6),
          L(12, 6)),
      T("\n", TokenValue(kind: Newline), L(12, 7), L(
          13, 0)),
      T("foo", TokenValue(kind: Word), L(13, 5), L(
          13, 7)),
      T(":", TokenValue(kind: Colon), L(13, 8), L(13, 8)),
      T("[", TokenValue(kind: LeftBracket), L(13, 10),
          L(13, 10)),
      T("1", TokenValue(kind: IntegerNumber, intValue: 1), L(13, 11),
          L(13, 11)),
      T(",", TokenValue(kind: Comma), L(13, 12), L(
          13, 12)),
      T("2", TokenValue(kind: IntegerNumber, intValue: 2), L(13, 14),
          L(13, 14)),
      T(",", TokenValue(kind: Comma), L(13, 15), L(
          13, 15)),
      T("3", TokenValue(kind: IntegerNumber, intValue: 3), L(13, 17),
          L(13, 17)),
      T("]", TokenValue(kind: RightBracket), L(13, 18),
          L(13, 18)),
      T("\n", TokenValue(kind: Newline), L(13, 19),
          L(14, 0)),
      T("\n", TokenValue(kind: Newline), L(14, 1), L(
          15, 0)),
      T("bar", TokenValue(kind: Word), L(15, 5), L(
          15, 7)),
      T(":", TokenValue(kind: Colon), L(15, 8), L(15, 8)),
      T("\'baz\'", TokenValue(kind: StringToken, stringValue: "baz"),
          L(15, 10), L(15, 14)),
      T("+", TokenValue(kind: Plus), L(15, 16), L(15,
          16)),
      T("3", TokenValue(kind: IntegerNumber, intValue: 3), L(15, 18),
          L(15, 18)),
      T("\n", TokenValue(kind: Newline), L(15, 19),
          L(16, 0)),
      T("}", TokenValue(kind: RightCurly), L(16, 1),
          L(16, 1)),
      T("", TokenValue(kind: EOF), L(16, 2), L(16, 2)),
    ],

    "C08": @[
      T("total_period", TokenValue(kind: Word), L(1,
          1), L(1, 12)),
      T(":", TokenValue(kind: Colon), L(1, 14), L(1,
          14)),
      T("100", TokenValue(kind: IntegerNumber, intValue: 100), L(1,
          16), L(1, 19)),
      T("\n", TokenValue(kind: Newline), L(1, 19), L(
          2, 0)),
      T("header_time", TokenValue(kind: Word), L(2, 1),
          L(2, 11)),
      T(":", TokenValue(kind: Colon), L(2, 12), L(2,
          12)),
      T("0.3", TokenValue(kind: FloatNumber, floatValue: 0.3), L(2,
          14), L(2, 17)),
      T("*", TokenValue(kind: Star), L(2, 18), L(2,
          18)),
      T("total_period", TokenValue(kind: Word), L(2,
          20), L(2, 31)),
      T("\n", TokenValue(kind: Newline), L(2, 32), L(
          3, 0)),
      T("steady_time", TokenValue(kind: Word), L(3, 1),
          L(3, 11)),
      T(":", TokenValue(kind: Colon), L(3, 12), L(3,
          12)),
      T("0.5", TokenValue(kind: FloatNumber, floatValue: 0.5), L(3,
          14), L(3, 17)),
      T("*", TokenValue(kind: Star), L(3, 18), L(3,
          18)),
      T("total_period", TokenValue(kind: Word), L(3,
          20), L(3, 31)),
      T("\n", TokenValue(kind: Newline), L(3, 32), L(
          4, 0)),
      T("trailer_time", TokenValue(kind: Word), L(4,
          1), L(4, 12)),
      T(":", TokenValue(kind: Colon), L(4, 13), L(4,
          13)),
      T("0.2", TokenValue(kind: FloatNumber, floatValue: 0.2), L(4,
          15), L(4, 18)),
      T("*", TokenValue(kind: Star), L(4, 19), L(4,
          19)),
      T("total_period", TokenValue(kind: Word), L(4,
          21), L(4, 32)),
      T("\n", TokenValue(kind: Newline), L(4, 33), L(
          5, 0)),
      T("base_prefix", TokenValue(kind: Word), L(5, 1),
          L(5, 11)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("\'/my/app/\'", TokenValue(kind: StringToken,
          stringValue: "/my/app/"), L(5, 14), L(5, 23)),
      T("\n", TokenValue(kind: Newline), L(5, 24), L(
          6, 0)),
      T("log_file", TokenValue(kind: Word), L(6, 1),
          L(6, 8)),
      T(":", TokenValue(kind: Colon), L(6, 9), L(6, 9)),
      T("base_prefix", TokenValue(kind: Word), L(6,
          11), L(6, 21)),
      T("+", TokenValue(kind: Plus), L(6, 23), L(6,
          23)),
      T("\'test.log\'", TokenValue(kind: StringToken,
          stringValue: "test.log"), L(6, 25), L(6, 34)),
      T("", TokenValue(kind: EOF), L(6, 35), L(6,
          35)),
    ],

    "C09": @[
      T("# The message to print (this is a comment)", TokenValue(
          kind: Newline), L(1, 1), L(2, 0)),
      T("message", TokenValue(kind: Word), L(2, 1),
          L(2, 7)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("\'Hello, world!\'", TokenValue(kind: StringToken,
          stringValue: "Hello, world!"), L(2, 10), L(2, 24)),
      T("\n", TokenValue(kind: Newline), L(2, 25), L(
          3, 0)),
      T("stream", TokenValue(kind: Word), L(3, 1), L(
          3, 6)),
      T(":", TokenValue(kind: Colon), L(3, 7), L(3, 7)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(3, 9), L(3, 20)),
      T("", TokenValue(kind: EOF), L(3, 21), L(3,
          21)),
    ],

    "C10": @[
      T("messages", TokenValue(kind: Word), L(1, 1),
          L(1, 8)),
      T(":", TokenValue(kind: Colon), L(1, 9), L(1, 9)),
      T("\n", TokenValue(kind: Newline), L(1, 10), L(
          2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("\n", TokenValue(kind: Newline), L(2, 2), L(
          3, 0)),
      T("{", TokenValue(kind: LeftCurly), L(3, 3), L(
          3, 3)),
      T("stream", TokenValue(kind: Word), L(3, 5), L(
          3, 10)),
      T(":", TokenValue(kind: Colon), L(3, 12), L(3,
          12)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(3, 14), L(3, 25)),
      T(",", TokenValue(kind: Comma), L(3, 26), L(3,
          26)),
      T("message", TokenValue(kind: Word), L(3, 28),
          L(3, 34)),
      T(":", TokenValue(kind: Colon), L(3, 35), L(3,
          35)),
      T("\'Welcome\'", TokenValue(kind: StringToken,
          stringValue: "Welcome"), L(3, 37), L(3, 45)),
      T("}", TokenValue(kind: RightCurly), L(3, 47),
          L(3, 47)),
      T(",", TokenValue(kind: Comma), L(3, 48), L(3,
          48)),
      T("\n", TokenValue(kind: Newline), L(3, 49), L(
          4, 0)),
      T("{", TokenValue(kind: LeftCurly), L(4, 3), L(
          4, 3)),
      T("stream", TokenValue(kind: Word), L(4, 5), L(
          4, 10)),
      T(":", TokenValue(kind: Colon), L(4, 12), L(4,
          12)),
      T("`sys.stdout`", TokenValue(kind: BackTick,
          stringValue: "sys.stdout"), L(4, 14), L(4, 25)),
      T(",", TokenValue(kind: Comma), L(4, 26), L(4,
          26)),
      T("message", TokenValue(kind: Word), L(4, 28),
          L(4, 34)),
      T(":", TokenValue(kind: Colon), L(4, 35), L(4,
          35)),
      T("\'Welkom\'", TokenValue(kind: StringToken,
          stringValue: "Welkom"), L(4, 37), L(4, 44)),
      T("}", TokenValue(kind: RightCurly), L(4, 46),
          L(4, 46)),
      T(",", TokenValue(kind: Comma), L(4, 47), L(4,
          47)),
      T("\n", TokenValue(kind: Newline), L(4, 48), L(
          5, 0)),
      T("{", TokenValue(kind: LeftCurly), L(5, 3), L(
          5, 3)),
      T("stream", TokenValue(kind: Word), L(5, 5), L(
          5, 10)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(5, 14), L(5, 25)),
      T(",", TokenValue(kind: Comma), L(5, 26), L(5,
          26)),
      T("message", TokenValue(kind: Word), L(5, 28),
          L(5, 34)),
      T(":", TokenValue(kind: Colon), L(5, 35), L(5,
          35)),
      T("\'Bienvenue\'", TokenValue(kind: StringToken,
          stringValue: "Bienvenue"), L(5, 37), L(5, 47)),
      T("}", TokenValue(kind: RightCurly), L(5, 49),
          L(5, 49)),
      T(",", TokenValue(kind: Comma), L(5, 50), L(5,
          50)),
      T("\n", TokenValue(kind: Newline), L(5, 51), L(
          6, 0)),
      T("]", TokenValue(kind: RightBracket), L(6, 1),
          L(6, 1)),
      T("", TokenValue(kind: EOF), L(6, 2), L(6, 2)),
    ],

    "C11": @[
      T("messages", TokenValue(kind: Word), L(1, 1),
          L(1, 8)),
      T(":", TokenValue(kind: Colon), L(1, 9), L(1, 9)),
      T("\n", TokenValue(kind: Newline), L(1, 10), L(
          2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("\n", TokenValue(kind: Newline), L(2, 2), L(
          3, 0)),
      T("{", TokenValue(kind: LeftCurly), L(3, 3), L(
          3, 3)),
      T("\n", TokenValue(kind: Newline), L(3, 4), L(
          4, 0)),
      T("stream", TokenValue(kind: Word), L(4, 5), L(
          4, 10)),
      T(":", TokenValue(kind: Colon), L(4, 12), L(4,
          12)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(4, 14), L(4, 25)),
      T("\n", TokenValue(kind: Newline), L(4, 26), L(
          5, 0)),
      T("message", TokenValue(kind: Word), L(5, 5),
          L(5, 11)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("Welcome", TokenValue(kind: Word), L(5, 14),
          L(5, 20)),
      T("\n", TokenValue(kind: Newline), L(5, 21), L(
          6, 0)),
      T("name", TokenValue(kind: Word), L(6, 5), L(6, 8)),
      T(":", TokenValue(kind: Colon), L(6, 9), L(6, 9)),
      T("\'Harry\'", TokenValue(kind: StringToken,
          stringValue: "Harry"), L(6, 11), L(6, 17)),
      T("\n", TokenValue(kind: Newline), L(6, 18), L(
          7, 0)),
      T("}", TokenValue(kind: RightCurly), L(7, 3),
          L(7, 3)),
      T("\n", TokenValue(kind: Newline), L(7, 4), L(
          8, 0)),
      T("{", TokenValue(kind: LeftCurly), L(8, 3), L(
          8, 3)),
      T("\n", TokenValue(kind: Newline), L(8, 4), L(
          9, 0)),
      T("stream", TokenValue(kind: Word), L(9, 5), L(
          9, 10)),
      T(":", TokenValue(kind: Colon), L(9, 12), L(9,
          12)),
      T("`sys.stdout`", TokenValue(kind: BackTick,
          stringValue: "sys.stdout"), L(9, 14), L(9, 25)),
      T("\n", TokenValue(kind: Newline), L(9, 26), L(
          10, 0)),
      T("message", TokenValue(kind: Word), L(10, 5),
          L(10, 11)),
      T(":", TokenValue(kind: Colon), L(10, 12), L(
          10, 12)),
      T("Welkom", TokenValue(kind: Word), L(10, 14),
          L(10, 19)),
      T("\n", TokenValue(kind: Newline), L(10, 20),
          L(11, 0)),
      T("name", TokenValue(kind: Word), L(11, 5), L(
          11, 8)),
      T(":", TokenValue(kind: Colon), L(11, 9), L(11, 9)),
      T("\'Ruud\'", TokenValue(kind: StringToken, stringValue: "Ruud"),
          L(11, 11), L(11, 16)),
      T("\n", TokenValue(kind: Newline), L(11, 17),
          L(12, 0)),
      T("}", TokenValue(kind: RightCurly), L(12, 3),
          L(12, 3)),
      T("\n", TokenValue(kind: Newline), L(12, 4), L(
          13, 0)),
      T("{", TokenValue(kind: LeftCurly), L(13, 3),
          L(13, 3)),
      T("\n", TokenValue(kind: Newline), L(13, 4), L(
          14, 0)),
      T("stream", TokenValue(kind: Word), L(14, 5),
          L(14, 10)),
      T(":", TokenValue(kind: Colon), L(14, 13), L(
          14, 13)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(14, 15), L(14, 26)),
      T("\n", TokenValue(kind: Newline), L(14, 27),
          L(15, 0)),
      T("message", TokenValue(kind: Word), L(15, 5),
          L(15, 11)),
      T(":", TokenValue(kind: Colon), L(15, 13), L(
          15, 13)),
      T("Bienvenue", TokenValue(kind: Word), L(15, 15),
          L(15, 23)),
      T("\n", TokenValue(kind: Newline), L(15, 24),
          L(16, 0)),
      T("name", TokenValue(kind: Word), L(16, 5), L(
          16, 8)),
      T(":", TokenValue(kind: Colon), L(16, 13), L(
          16, 13)),
      T("Yves", TokenValue(kind: Word), L(16, 15), L(
          16, 18)),
      T("\n", TokenValue(kind: Newline), L(16, 19),
          L(17, 0)),
      T("}", TokenValue(kind: RightCurly), L(17, 3),
          L(17, 3)),
      T("\n", TokenValue(kind: Newline), L(17, 4), L(
          18, 0)),
      T("]", TokenValue(kind: RightBracket), L(18, 1),
          L(18, 1)),
      T("", TokenValue(kind: EOF), L(18, 2), L(18, 2)),
    ],

    "C12": @[
      T("messages", TokenValue(kind: Word), L(1, 1),
          L(1, 8)),
      T(":", TokenValue(kind: Colon), L(1, 9), L(1, 9)),
      T("\n", TokenValue(kind: Newline), L(1, 10), L(
          2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("\n", TokenValue(kind: Newline), L(2, 2), L(
          3, 0)),
      T("{", TokenValue(kind: LeftCurly), L(3, 3), L(
          3, 3)),
      T("\n", TokenValue(kind: Newline), L(3, 4), L(
          4, 0)),
      T("stream", TokenValue(kind: Word), L(4, 5), L(
          4, 10)),
      T(":", TokenValue(kind: Colon), L(4, 12), L(4,
          12)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(4, 14), L(4, 25)),
      T("\n", TokenValue(kind: Newline), L(4, 26), L(
          5, 0)),
      T("message", TokenValue(kind: Word), L(5, 5),
          L(5, 11)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("\'Welcome\'", TokenValue(kind: StringToken,
          stringValue: "Welcome"), L(5, 14), L(5, 22)),
      T("\n", TokenValue(kind: Newline), L(5, 23), L(
          6, 0)),
      T("name", TokenValue(kind: Word), L(6, 5), L(6, 8)),
      T(":", TokenValue(kind: Colon), L(6, 9), L(6, 9)),
      T("\'Harry\'", TokenValue(kind: StringToken,
          stringValue: "Harry"), L(6, 11), L(6, 17)),
      T("\n", TokenValue(kind: Newline), L(6, 18), L(
          7, 0)),
      T("}", TokenValue(kind: RightCurly), L(7, 3),
          L(7, 3)),
      T("\n", TokenValue(kind: Newline), L(7, 4), L(
          8, 0)),
      T("{", TokenValue(kind: LeftCurly), L(8, 3), L(
          8, 3)),
      T("\n", TokenValue(kind: Newline), L(8, 4), L(
          9, 0)),
      T("stream", TokenValue(kind: Word), L(9, 5), L(
          9, 10)),
      T(":", TokenValue(kind: Colon), L(9, 12), L(9,
          12)),
      T("`sys.stdout`", TokenValue(kind: BackTick,
          stringValue: "sys.stdout"), L(9, 14), L(9, 25)),
      T("\n", TokenValue(kind: Newline), L(9, 26), L(
          10, 0)),
      T("message", TokenValue(kind: Word), L(10, 5),
          L(10, 11)),
      T(":", TokenValue(kind: Colon), L(10, 12), L(
          10, 12)),
      T("\'Welkom\'", TokenValue(kind: StringToken,
          stringValue: "Welkom"), L(10, 14), L(10, 21)),
      T("\n", TokenValue(kind: Newline), L(10, 22),
          L(11, 0)),
      T("name", TokenValue(kind: Word), L(11, 5), L(
          11, 8)),
      T(":", TokenValue(kind: Colon), L(11, 9), L(11, 9)),
      T("\'Ruud\'", TokenValue(kind: StringToken, stringValue: "Ruud"),
          L(11, 11), L(11, 16)),
      T("\n", TokenValue(kind: Newline), L(11, 17),
          L(12, 0)),
      T("}", TokenValue(kind: RightCurly), L(12, 3),
          L(12, 3)),
      T("\n", TokenValue(kind: Newline), L(12, 4), L(
          13, 0)),
      T("{", TokenValue(kind: LeftCurly), L(13, 3),
          L(13, 3)),
      T("\n", TokenValue(kind: Newline), L(13, 4), L(
          14, 0)),
      T("stream", TokenValue(kind: Word), L(14, 5),
          L(14, 10)),
      T(":", TokenValue(kind: Colon), L(14, 12), L(
          14, 12)),
      T("$", TokenValue(kind: Dollar), L(14, 14), L(
          14, 14)),
      T("{", TokenValue(kind: LeftCurly), L(14, 15),
          L(14, 15)),
      T("messages", TokenValue(kind: Word), L(14, 16),
          L(14, 23)),
      T("[", TokenValue(kind: LeftBracket), L(14, 24),
          L(14, 24)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(14, 25),
          L(14, 25)),
      T("]", TokenValue(kind: RightBracket), L(14, 26),
          L(14, 26)),
      T(".", TokenValue(kind: Dot), L(14, 27), L(14,
          27)),
      T("stream", TokenValue(kind: Word), L(14, 28),
          L(14, 33)),
      T("}", TokenValue(kind: RightCurly), L(14, 34),
          L(14, 34)),
      T("\n", TokenValue(kind: Newline), L(14, 35),
          L(15, 0)),
      T("message", TokenValue(kind: Word), L(15, 5),
          L(15, 11)),
      T(":", TokenValue(kind: Colon), L(15, 12), L(
          15, 12)),
      T("\'Bienvenue\'", TokenValue(kind: StringToken,
          stringValue: "Bienvenue"), L(15, 14), L(15, 24)),
      T("\n", TokenValue(kind: Newline), L(15, 25),
          L(16, 0)),
      T("name", TokenValue(kind: Word), L(16, 5), L(
          16, 8)),
      T(":", TokenValue(kind: Colon), L(16, 9), L(16, 9)),
      T("Yves", TokenValue(kind: Word), L(16, 11), L(
          16, 14)),
      T("\n", TokenValue(kind: Newline), L(16, 15),
          L(17, 0)),
      T("}", TokenValue(kind: RightCurly), L(17, 3),
          L(17, 3)),
      T("\n", TokenValue(kind: Newline), L(17, 4), L(
          18, 0)),
      T("]", TokenValue(kind: RightBracket), L(18, 1),
          L(18, 1)),
      T("", TokenValue(kind: EOF), L(18, 2), L(18, 2)),
    ],

    "C13": @[
      T("logging", TokenValue(kind: Word), L(1, 1),
          L(1, 7)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("@", TokenValue(kind: At), L(1, 10), L(1,
          10)),
      T("\"logging.cfg\"", TokenValue(kind: StringToken,
          stringValue: "logging.cfg"), L(1, 11), L(1, 23)),
      T("\n", TokenValue(kind: Newline), L(1, 24), L(
          2, 0)),
      T("test", TokenValue(kind: Word), L(2, 1), L(2, 4)),
      T(":", TokenValue(kind: Colon), L(2, 5), L(2, 5)),
      T("$", TokenValue(kind: Dollar), L(2, 7), L(2, 7)),
      T("{", TokenValue(kind: LeftCurly), L(2, 8), L(
          2, 8)),
      T("logging", TokenValue(kind: Word), L(2, 9),
          L(2, 15)),
      T(".", TokenValue(kind: Dot), L(2, 16), L(2,
          16)),
      T("handler", TokenValue(kind: Word), L(2, 17),
          L(2, 23)),
      T(".", TokenValue(kind: Dot), L(2, 24), L(2,
          24)),
      T("email", TokenValue(kind: Word), L(2, 25), L(
          2, 29)),
      T(".", TokenValue(kind: Dot), L(2, 30), L(2,
          30)),
      T("from", TokenValue(kind: Word), L(2, 31), L(
          2, 34)),
      T("}", TokenValue(kind: RightCurly), L(2, 35),
          L(2, 35)),
      T("", TokenValue(kind: EOF), L(2, 36), L(2,
          36)),
    ],

    "C14": @[
      T("# root logger configuration", TokenValue(kind: Newline,
          otherValue: 0), L(1, 1), L(2, 0)),
      T("root", TokenValue(kind: Word), L(2, 1), L(2, 4)),
      T(":", TokenValue(kind: Colon), L(2, 5), L(2, 5)),
      T("\n", TokenValue(kind: Newline), L(2, 6), L(
          3, 0)),
      T("{", TokenValue(kind: LeftCurly), L(3, 1), L(
          3, 1)),
      T("\n", TokenValue(kind: Newline), L(3, 2), L(
          4, 0)),
      T("level", TokenValue(kind: Word), L(4, 3), L(
          4, 7)),
      T(":", TokenValue(kind: Colon), L(4, 13), L(4,
          13)),
      T("DEBUG", TokenValue(kind: Word), L(4, 15), L(
          4, 19)),
      T("\n", TokenValue(kind: Newline), L(4, 20), L(
          5, 0)),
      T("handlers", TokenValue(kind: Word), L(5, 3),
          L(5, 10)),
      T(":", TokenValue(kind: Colon), L(5, 13), L(5,
          13)),
      T("[", TokenValue(kind: LeftBracket), L(5, 15),
          L(5, 15)),
      T("$", TokenValue(kind: Dollar), L(5, 16), L(5,
          16)),
      T("{", TokenValue(kind: LeftCurly), L(5, 17),
          L(5, 17)),
      T("handlers", TokenValue(kind: Word), L(5, 18),
          L(5, 25)),
      T(".", TokenValue(kind: Dot), L(5, 26), L(5,
          26)),
      T("console", TokenValue(kind: Word), L(5, 27),
          L(5, 33)),
      T("}", TokenValue(kind: RightCurly), L(5, 34),
          L(5, 34)),
      T(",", TokenValue(kind: Comma), L(5, 35), L(5,
          35)),
      T("$", TokenValue(kind: Dollar), L(5, 37), L(5,
          37)),
      T("{", TokenValue(kind: LeftCurly), L(5, 38),
          L(5, 38)),
      T("handlers", TokenValue(kind: Word), L(5, 39),
          L(5, 46)),
      T(".", TokenValue(kind: Dot), L(5, 47), L(5,
          47)),
      T("file", TokenValue(kind: Word), L(5, 48), L(
          5, 51)),
      T("}", TokenValue(kind: RightCurly), L(5, 52),
          L(5, 52)),
      T(",", TokenValue(kind: Comma), L(5, 53), L(5,
          53)),
      T("$", TokenValue(kind: Dollar), L(5, 55), L(5,
          55)),
      T("{", TokenValue(kind: LeftCurly), L(5, 56),
          L(5, 56)),
      T("handlers", TokenValue(kind: Word), L(5, 57),
          L(5, 64)),
      T(".", TokenValue(kind: Dot), L(5, 65), L(5,
          65)),
      T("email", TokenValue(kind: Word), L(5, 66), L(
          5, 70)),
      T("}", TokenValue(kind: RightCurly), L(5, 71),
          L(5, 71)),
      T("]", TokenValue(kind: RightBracket), L(5, 72),
          L(5, 72)),
      T("\n", TokenValue(kind: Newline), L(5, 73), L(
          6, 0)),
      T("}", TokenValue(kind: RightCurly), L(6, 1),
          L(6, 1)),
      T("\n", TokenValue(kind: Newline), L(6, 2), L(
          7, 0)),
      T("# logging handlers", TokenValue(kind: Newline),
          L(7, 1), L(8, 0)),
      T("handlers", TokenValue(kind: Word), L(8, 1),
          L(8, 8)),
      T(":", TokenValue(kind: Colon), L(8, 9), L(8, 9)),
      T("\n", TokenValue(kind: Newline), L(8, 10), L(
          9, 0)),
      T("{", TokenValue(kind: LeftCurly), L(9, 1), L(
          9, 1)),
      T("\n", TokenValue(kind: Newline), L(9, 2), L(
          10, 0)),
      T("console", TokenValue(kind: Word), L(10, 3),
          L(10, 9)),
      T(":", TokenValue(kind: Colon), L(10, 10), L(
          10, 10)),
      T("[", TokenValue(kind: LeftBracket), L(10, 13),
          L(10, 13)),
      T("\n", TokenValue(kind: Newline), L(10, 14),
          L(11, 0)),
      T("# the class to instantiate", TokenValue(kind: Newline,
          otherValue: 0), L(11, 15), L(12, 0)),
      T("StreamHandler", TokenValue(kind: Word), L(12,
          15), L(12, 27)),
      T(",", TokenValue(kind: Comma), L(12, 28), L(
          12, 28)),
      T("\n", TokenValue(kind: Newline), L(12, 29),
          L(13, 0)),
      T("# how to configure the instance", TokenValue(kind: Newline,
          otherValue: 0), L(13, 15), L(14, 0)),
      T("{", TokenValue(kind: LeftCurly), L(14, 15),
          L(14, 15)),
      T("\n", TokenValue(kind: Newline), L(14, 16),
          L(15, 0)),
      T("level", TokenValue(kind: Word), L(15, 17),
          L(15, 21)),
      T(":", TokenValue(kind: Colon), L(15, 23), L(
          15, 23)),
      T("WARNING", TokenValue(kind: Word), L(15, 25),
          L(15, 31)),
      T("# the logger level", TokenValue(kind: Newline),
          L(15, 45), L(16, 0)),
      T("stream", TokenValue(kind: Word), L(16, 17),
          L(16, 22)),
      T(":", TokenValue(kind: Colon), L(16, 25), L(
          16, 25)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(16, 27), L(16, 38)),
      T("}", TokenValue(kind: RightCurly), L(16, 40),
          L(16, 40)),
      T("# the stream to use", TokenValue(kind: Newline),
          L(16, 45), L(17, 0)),
      T("]", TokenValue(kind: RightBracket), L(17, 13),
          L(17, 13)),
      T("\n", TokenValue(kind: Newline), L(17, 14),
          L(18, 0)),
      T("file", TokenValue(kind: Word), L(18, 3), L(
          18, 6)),
      T(":", TokenValue(kind: Colon), L(18, 7), L(18, 7)),
      T("[", TokenValue(kind: LeftBracket), L(18, 13),
          L(18, 13)),
      T("FileHandler", TokenValue(kind: Word), L(18,
          15), L(18, 25)),
      T(",", TokenValue(kind: Comma), L(18, 26), L(
          18, 26)),
      T("{", TokenValue(kind: LeftCurly), L(18, 28),
          L(18, 28)),
      T("filename", TokenValue(kind: Word), L(18, 30),
          L(18, 37)),
      T(":", TokenValue(kind: Colon), L(18, 38), L(
          18, 38)),
      T("$", TokenValue(kind: Dollar), L(18, 40), L(
          18, 40)),
      T("{", TokenValue(kind: LeftCurly), L(18, 41),
          L(18, 41)),
      T("app", TokenValue(kind: Word), L(18, 42), L(
          18, 44)),
      T(".", TokenValue(kind: Dot), L(18, 45), L(18,
          45)),
      T("base", TokenValue(kind: Word), L(18, 46), L(
          18, 49)),
      T("}", TokenValue(kind: RightCurly), L(18, 50),
          L(18, 50)),
      T("+", TokenValue(kind: Plus), L(18, 52), L(18,
          52)),
      T("$", TokenValue(kind: Dollar), L(18, 54), L(
          18, 54)),
      T("{", TokenValue(kind: LeftCurly), L(18, 55),
          L(18, 55)),
      T("app", TokenValue(kind: Word), L(18, 56), L(
          18, 58)),
      T(".", TokenValue(kind: Dot), L(18, 59), L(18,
          59)),
      T("name", TokenValue(kind: Word), L(18, 60), L(
          18, 63)),
      T("}", TokenValue(kind: RightCurly), L(18, 64),
          L(18, 64)),
      T("+", TokenValue(kind: Plus), L(18, 66), L(18,
          66)),
      T("\'.log\'", TokenValue(kind: StringToken, stringValue: ".log"),
          L(18, 68), L(18, 73)),
      T(",", TokenValue(kind: Comma), L(18, 74), L(
          18, 74)),
      T("mode", TokenValue(kind: Word), L(18, 76), L(
          18, 79)),
      T(":", TokenValue(kind: Colon), L(18, 81), L(
          18, 81)),
      T("\'a\'", TokenValue(kind: StringToken, stringValue: "a"), L(
          18, 83), L(18, 85)),
      T("}", TokenValue(kind: RightCurly), L(18, 87),
          L(18, 87)),
      T("]", TokenValue(kind: RightBracket), L(18, 89),
          L(18, 89)),
      T("\n", TokenValue(kind: Newline), L(18, 90),
          L(19, 0)),
      T("socket", TokenValue(kind: Word), L(19, 3),
          L(19, 8)),
      T(":", TokenValue(kind: Colon), L(19, 9), L(19, 9)),
      T("[", TokenValue(kind: LeftBracket), L(19, 13),
          L(19, 13)),
      T("`handlers.SocketHandler`", TokenValue(kind: BackTick,
          stringValue: "handlers.SocketHandler"), L(19, 15), L(19, 38)),
      T(",", TokenValue(kind: Comma), L(19, 39), L(
          19, 39)),
      T("{", TokenValue(kind: LeftCurly), L(19, 41),
          L(19, 41)),
      T("\n", TokenValue(kind: Newline), L(19, 42),
          L(20, 0)),
      T("host", TokenValue(kind: Word), L(20, 19), L(
          20, 22)),
      T(":", TokenValue(kind: Colon), L(20, 23), L(
          20, 23)),
      T("localhost", TokenValue(kind: Word), L(20, 25),
          L(20, 33)),
      T(",", TokenValue(kind: Comma), L(20, 34), L(
          20, 34)),
      T("\n", TokenValue(kind: Newline), L(20, 35),
          L(21, 0)),
      T("# use this port for now", TokenValue(kind: Newline,
          otherValue: 0), L(21, 19), L(22, 0)),
      T("port", TokenValue(kind: Word), L(22, 19), L(
          22, 22)),
      T(":", TokenValue(kind: Colon), L(22, 23), L(
          22, 23)),
      T("`handlers.DEFAULT_TCP_LOGGING_PORT`", TokenValue(
          kind: BackTick, stringValue: "handlers.DEFAULT_TCP_LOGGING_PORT"),
          L(22, 25), L(22, 59)),
      T("}", TokenValue(kind: RightCurly), L(22, 60),
          L(22, 60)),
      T("]", TokenValue(kind: RightBracket), L(22, 62),
          L(22, 62)),
      T("\n", TokenValue(kind: Newline), L(22, 63),
          L(23, 0)),
      T("nt_eventlog", TokenValue(kind: Word), L(23,
          3), L(23, 13)),
      T(":", TokenValue(kind: Colon), L(23, 14), L(
          23, 14)),
      T("[", TokenValue(kind: LeftBracket), L(23, 16),
          L(23, 16)),
      T("`handlers.NTEventLogHandler`", TokenValue(kind: BackTick,
          stringValue: "handlers.NTEventLogHandler"), L(23, 17), L(23, 44)),
      T(",", TokenValue(kind: Comma), L(23, 45), L(
          23, 45)),
      T("{", TokenValue(kind: LeftCurly), L(23, 47),
          L(23, 47)),
      T("appname", TokenValue(kind: Word), L(23, 49),
          L(23, 55)),
      T(":", TokenValue(kind: Colon), L(23, 56), L(
          23, 56)),
      T("$", TokenValue(kind: Dollar), L(23, 58), L(
          23, 58)),
      T("{", TokenValue(kind: LeftCurly), L(23, 59),
          L(23, 59)),
      T("app", TokenValue(kind: Word), L(23, 60), L(
          23, 62)),
      T(".", TokenValue(kind: Dot), L(23, 63), L(23,
          63)),
      T("name", TokenValue(kind: Word), L(23, 64), L(
          23, 67)),
      T("}", TokenValue(kind: RightCurly), L(23, 68),
          L(23, 68)),
      T(",", TokenValue(kind: Comma), L(23, 69), L(
          23, 69)),
      T("logtype", TokenValue(kind: Word), L(23, 71),
          L(23, 77)),
      T(":", TokenValue(kind: Colon), L(23, 79), L(
          23, 79)),
      T("Application", TokenValue(kind: Word), L(23,
          81), L(23, 91)),
      T("}", TokenValue(kind: RightCurly), L(23, 93),
          L(23, 93)),
      T("]", TokenValue(kind: RightBracket), L(23, 95),
          L(23, 95)),
      T("\n", TokenValue(kind: Newline), L(23, 96),
          L(24, 0)),
      T("email", TokenValue(kind: Word), L(24, 3), L(
          24, 7)),
      T(":", TokenValue(kind: Colon), L(24, 8), L(24, 8)),
      T("[", TokenValue(kind: LeftBracket), L(24, 13),
          L(24, 13)),
      T("`handlers.SMTPHandler`", TokenValue(kind: BackTick,
          stringValue: "handlers.SMTPHandler"), L(24, 15), L(24, 36)),
      T(",", TokenValue(kind: Comma), L(24, 37), L(
          24, 37)),
      T("\n", TokenValue(kind: Newline), L(24, 38),
          L(25, 0)),
      T("{", TokenValue(kind: LeftCurly), L(25, 15),
          L(25, 15)),
      T("level", TokenValue(kind: Word), L(25, 17),
          L(25, 21)),
      T(":", TokenValue(kind: Colon), L(25, 22), L(
          25, 22)),
      T("CRITICAL", TokenValue(kind: Word), L(25, 24),
          L(25, 31)),
      T(",", TokenValue(kind: Comma), L(25, 32), L(
          25, 32)),
      T("\n", TokenValue(kind: Newline), L(25, 33),
          L(26, 0)),
      T("host", TokenValue(kind: Word), L(26, 17), L(
          26, 20)),
      T(":", TokenValue(kind: Colon), L(26, 21), L(
          26, 21)),
      T("localhost", TokenValue(kind: Word), L(26, 23),
          L(26, 31)),
      T(",", TokenValue(kind: Comma), L(26, 32), L(
          26, 32)),
      T("\n", TokenValue(kind: Newline), L(26, 33),
          L(27, 0)),
      T("port", TokenValue(kind: Word), L(27, 17), L(
          27, 20)),
      T(":", TokenValue(kind: Colon), L(27, 21), L(
          27, 21)),
      T("25", TokenValue(kind: IntegerNumber, intValue: 25), L(27,
          23), L(27, 25)),
      T(",", TokenValue(kind: Comma), L(27, 25), L(
          27, 25)),
      T("\n", TokenValue(kind: Newline), L(27, 26),
          L(28, 0)),
      T("from", TokenValue(kind: Word), L(28, 17), L(
          28, 20)),
      T(":", TokenValue(kind: Colon), L(28, 21), L(
          28, 21)),
      T("$", TokenValue(kind: Dollar), L(28, 23), L(
          28, 23)),
      T("{", TokenValue(kind: LeftCurly), L(28, 24),
          L(28, 24)),
      T("app", TokenValue(kind: Word), L(28, 25), L(
          28, 27)),
      T(".", TokenValue(kind: Dot), L(28, 28), L(28,
          28)),
      T("name", TokenValue(kind: Word), L(28, 29), L(
          28, 32)),
      T("}", TokenValue(kind: RightCurly), L(28, 33),
          L(28, 33)),
      T("+", TokenValue(kind: Plus), L(28, 35), L(28,
          35)),
      T("$", TokenValue(kind: Dollar), L(28, 37), L(
          28, 37)),
      T("{", TokenValue(kind: LeftCurly), L(28, 38),
          L(28, 38)),
      T("app", TokenValue(kind: Word), L(28, 39), L(
          28, 41)),
      T(".", TokenValue(kind: Dot), L(28, 42), L(28,
          42)),
      T("mail_domain", TokenValue(kind: Word), L(28,
          43), L(28, 53)),
      T("}", TokenValue(kind: RightCurly), L(28, 54),
          L(28, 54)),
      T(",", TokenValue(kind: Comma), L(28, 55), L(
          28, 55)),
      T("\n", TokenValue(kind: Newline), L(28, 56),
          L(29, 0)),
      T("to", TokenValue(kind: Word), L(29, 17), L(
          29, 18)),
      T(":", TokenValue(kind: Colon), L(29, 19), L(
          29, 19)),
      T("[", TokenValue(kind: LeftBracket), L(29, 21),
          L(29, 21)),
      T("$", TokenValue(kind: Dollar), L(29, 22), L(
          29, 22)),
      T("{", TokenValue(kind: LeftCurly), L(29, 23),
          L(29, 23)),
      T("app", TokenValue(kind: Word), L(29, 24), L(
          29, 26)),
      T(".", TokenValue(kind: Dot), L(29, 27), L(29,
          27)),
      T("support_team", TokenValue(kind: Word), L(29,
          28), L(29, 39)),
      T("}", TokenValue(kind: RightCurly), L(29, 40),
          L(29, 40)),
      T("+", TokenValue(kind: Plus), L(29, 42), L(29,
          42)),
      T("$", TokenValue(kind: Dollar), L(29, 44), L(
          29, 44)),
      T("{", TokenValue(kind: LeftCurly), L(29, 45),
          L(29, 45)),
      T("app", TokenValue(kind: Word), L(29, 46), L(
          29, 48)),
      T(".", TokenValue(kind: Dot), L(29, 49), L(29,
          49)),
      T("mail_domain", TokenValue(kind: Word), L(29,
          50), L(29, 60)),
      T("}", TokenValue(kind: RightCurly), L(29, 61),
          L(29, 61)),
      T(",", TokenValue(kind: Comma), L(29, 62), L(
          29, 62)),
      T("\'QA\'", TokenValue(kind: StringToken, stringValue: "QA"), L(
          29, 64), L(29, 67)),
      T("+", TokenValue(kind: Plus), L(29, 69), L(29,
          69)),
      T("$", TokenValue(kind: Dollar), L(29, 71), L(
          29, 71)),
      T("{", TokenValue(kind: LeftCurly), L(29, 72),
          L(29, 72)),
      T("app", TokenValue(kind: Word), L(29, 73), L(
          29, 75)),
      T(".", TokenValue(kind: Dot), L(29, 76), L(29,
          76)),
      T("mail_domain", TokenValue(kind: Word), L(29,
          77), L(29, 87)),
      T("}", TokenValue(kind: RightCurly), L(29, 88),
          L(29, 88)),
      T(",", TokenValue(kind: Comma), L(29, 89), L(
          29, 89)),
      T("\'product_manager\'", TokenValue(kind: StringToken,
          stringValue: "product_manager"), L(29, 91), L(29, 107)),
      T("+", TokenValue(kind: Plus), L(29, 109), L(
          29, 109)),
      T("$", TokenValue(kind: Dollar), L(29, 111), L(
          29, 111)),
      T("{", TokenValue(kind: LeftCurly), L(29, 112),
          L(29, 112)),
      T("app", TokenValue(kind: Word), L(29, 113), L(
          29, 115)),
      T(".", TokenValue(kind: Dot), L(29, 116), L(29,
          116)),
      T("mail_domain", TokenValue(kind: Word), L(29,
          117), L(29, 127)),
      T("}", TokenValue(kind: RightCurly), L(29, 128),
          L(29, 128)),
      T("]", TokenValue(kind: RightBracket), L(29,
          129), L(29, 129)),
      T(",", TokenValue(kind: Comma), L(29, 130), L(
          29, 130)),
      T("\n", TokenValue(kind: Newline), L(29, 131),
          L(30, 0)),
      T("subject", TokenValue(kind: Word), L(30, 17),
          L(30, 23)),
      T(":", TokenValue(kind: Colon), L(30, 24), L(
          30, 24)),
      T("\'Take cover\'", TokenValue(kind: StringToken,
          stringValue: "Take cover"), L(30, 26), L(30, 37)),
      T("}", TokenValue(kind: RightCurly), L(30, 39),
          L(30, 39)),
      T("]", TokenValue(kind: RightBracket), L(30, 41),
          L(30, 41)),
      T("# random comment", TokenValue(kind: Newline),
          L(30, 43), L(31, 0)),
      T("}", TokenValue(kind: RightCurly), L(31, 1),
          L(31, 1)),
      T("\n", TokenValue(kind: Newline), L(31, 2), L(
          32, 0)),
      T("# the loggers which are configured", TokenValue(kind: Newline,
          otherValue: 0), L(32, 1), L(33, 0)),
      T("loggers", TokenValue(kind: Word), L(33, 1),
          L(33, 7)),
      T(":", TokenValue(kind: Colon), L(33, 8), L(33, 8)),
      T("\n", TokenValue(kind: Newline), L(33, 9), L(
          34, 0)),
      T("{", TokenValue(kind: LeftCurly), L(34, 1),
          L(34, 1)),
      T("\n", TokenValue(kind: Newline), L(34, 2), L(
          35, 0)),
      T("\"input\"", TokenValue(kind: StringToken,
          stringValue: "input"), L(35, 3), L(35, 9)),
      T(":", TokenValue(kind: Colon), L(35, 15), L(
          35, 15)),
      T("{", TokenValue(kind: LeftCurly), L(35, 17),
          L(35, 17)),
      T("handlers", TokenValue(kind: Word), L(35, 19),
          L(35, 26)),
      T(":", TokenValue(kind: Colon), L(35, 27), L(
          35, 27)),
      T("[", TokenValue(kind: LeftBracket), L(35, 29),
          L(35, 29)),
      T("$", TokenValue(kind: Dollar), L(35, 30), L(
          35, 30)),
      T("{", TokenValue(kind: LeftCurly), L(35, 31),
          L(35, 31)),
      T("handlers", TokenValue(kind: Word), L(35, 32),
          L(35, 39)),
      T(".", TokenValue(kind: Dot), L(35, 40), L(35,
          40)),
      T("socket", TokenValue(kind: Word), L(35, 41),
          L(35, 46)),
      T("}", TokenValue(kind: RightCurly), L(35, 47),
          L(35, 47)),
      T("]", TokenValue(kind: RightBracket), L(35, 48),
          L(35, 48)),
      T("}", TokenValue(kind: RightCurly), L(35, 50),
          L(35, 50)),
      T("\n", TokenValue(kind: Newline), L(35, 51),
          L(36, 0)),
      T("\"input.xls\"", TokenValue(kind: StringToken,
          stringValue: "input.xls"), L(36, 3), L(36, 13)),
      T(":", TokenValue(kind: Colon), L(36, 15), L(
          36, 15)),
      T("{", TokenValue(kind: LeftCurly), L(36, 17),
          L(36, 17)),
      T("handlers", TokenValue(kind: Word), L(36, 19),
          L(36, 26)),
      T(":", TokenValue(kind: Colon), L(36, 27), L(
          36, 27)),
      T("[", TokenValue(kind: LeftBracket), L(36, 29),
          L(36, 29)),
      T("$", TokenValue(kind: Dollar), L(36, 30), L(
          36, 30)),
      T("{", TokenValue(kind: LeftCurly), L(36, 31),
          L(36, 31)),
      T("handlers", TokenValue(kind: Word), L(36, 32),
          L(36, 39)),
      T(".", TokenValue(kind: Dot), L(36, 40), L(36,
          40)),
      T("nt_eventlog", TokenValue(kind: Word), L(36,
          41), L(36, 51)),
      T("}", TokenValue(kind: RightCurly), L(36, 52),
          L(36, 52)),
      T("]", TokenValue(kind: RightBracket), L(36, 53),
          L(36, 53)),
      T("}", TokenValue(kind: RightCurly), L(36, 55),
          L(36, 55)),
      T("\n", TokenValue(kind: Newline), L(36, 56),
          L(37, 0)),
      T("}", TokenValue(kind: RightCurly), L(37, 1),
          L(37, 1)),
      T("", TokenValue(kind: EOF), L(37, 2), L(37, 2)),
    ],

    "C15": @[
      T("a", TokenValue(kind: Word), L(1, 1), L(1, 1)),
      T(":", TokenValue(kind: Colon), L(1, 2), L(1, 2)),
      T("$", TokenValue(kind: Dollar), L(1, 4), L(1, 4)),
      T("{", TokenValue(kind: LeftCurly), L(1, 5), L(
          1, 5)),
      T("foo", TokenValue(kind: Word), L(1, 6), L(1, 8)),
      T(".", TokenValue(kind: Dot), L(1, 9), L(1, 9)),
      T("bar", TokenValue(kind: Word), L(1, 10), L(1,
          12)),
      T("}", TokenValue(kind: RightCurly), L(1, 13),
          L(1, 13)),
      T(".", TokenValue(kind: Dot), L(1, 14), L(1,
          14)),
      T("baz", TokenValue(kind: Word), L(1, 15), L(1,
          17)),
      T("\n", TokenValue(kind: Newline), L(1, 18), L(
          2, 0)),
      T("b", TokenValue(kind: Word), L(2, 1), L(2, 1)),
      T(":", TokenValue(kind: Colon), L(2, 2), L(2, 2)),
      T("`bish.bash`", TokenValue(kind: BackTick,
          stringValue: "bish.bash"), L(2, 4), L(2, 14)),
      T(".", TokenValue(kind: Dot), L(2, 15), L(2,
          15)),
      T("bosh", TokenValue(kind: Word), L(2, 16), L(
          2, 19)),
      T("", TokenValue(kind: EOF), L(2, 20), L(2,
          20)),
    ],

    "C16": @[
      T("test", TokenValue(kind: Word), L(1, 1), L(1, 4)),
      T(":", TokenValue(kind: Colon), L(1, 6), L(1, 6)),
      T("False", TokenValue(kind: Word), L(1, 8), L(
          1, 12)),
      T("\n", TokenValue(kind: Newline), L(1, 13), L(
          2, 0)),
      T("another_test", TokenValue(kind: Word), L(2,
          1), L(2, 12)),
      T(":", TokenValue(kind: Colon), L(2, 13), L(2,
          13)),
      T("True", TokenValue(kind: Word), L(2, 15), L(
          2, 18)),
      T("", TokenValue(kind: EOF), L(2, 19), L(2,
          19)),
    ],

    "C17": @[
      T("test", TokenValue(kind: Word), L(1, 1), L(1, 4)),
      T(":", TokenValue(kind: Colon), L(1, 6), L(1, 6)),
      T("None", TokenValue(kind: Word), L(1, 8), L(1,
          11)),
      T("", TokenValue(kind: EOF), L(1, 12), L(1,
          12)),
    ],

    "C18": @[
      T("root", TokenValue(kind: Word), L(1, 1), L(1, 4)),
      T(":", TokenValue(kind: Colon), L(1, 5), L(1, 5)),
      T("1", TokenValue(kind: IntegerNumber, intValue: 1), L(1, 7),
          L(1, 7)),
      T("\n", TokenValue(kind: Newline), L(1, 8), L(
          2, 0)),
      T("stream", TokenValue(kind: Word), L(2, 1), L(
          2, 6)),
      T(":", TokenValue(kind: Colon), L(2, 7), L(2, 7)),
      T("1.7", TokenValue(kind: FloatNumber, floatValue: 1.7), L(2,
          9), L(2, 12)),
      T("\n", TokenValue(kind: Newline), L(2, 12), L(
          3, 0)),
      T("neg", TokenValue(kind: Word), L(3, 1), L(3, 3)),
      T(":", TokenValue(kind: Colon), L(3, 4), L(3, 4)),
      T("-1", TokenValue(kind: IntegerNumber, intValue: -1), L(3, 6),
          L(3, 8)),
      T("\n", TokenValue(kind: Newline), L(3, 8), L(
          4, 0)),
      T("negfloat", TokenValue(kind: Word), L(4, 1),
          L(4, 8)),
      T(":", TokenValue(kind: Colon), L(4, 9), L(4, 9)),
      T("-2.0", TokenValue(kind: FloatNumber, floatValue: -2.0), L(4,
          11), L(4, 15)),
      T("\n", TokenValue(kind: Newline), L(4, 15), L(
          5, 0)),
      T("posexponent", TokenValue(kind: Word), L(5, 1),
          L(5, 11)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("2.0999999e-08", TokenValue(kind: FloatNumber,
          floatValue: 2.0999999e-08), L(5, 14), L(5, 27)),
      T("\n", TokenValue(kind: Newline), L(5, 27), L(
          6, 0)),
      T("negexponent", TokenValue(kind: Word), L(6, 1),
          L(6, 11)),
      T(":", TokenValue(kind: Colon), L(6, 12), L(6,
          12)),
      T("-2.0999999e-08", TokenValue(kind: FloatNumber,
          floatValue: -2.0999999e-08), L(6, 14), L(6, 28)),
      T("\n", TokenValue(kind: Newline), L(6, 28), L(
          7, 0)),
      T("exponent", TokenValue(kind: Word), L(7, 1),
          L(7, 8)),
      T(":", TokenValue(kind: Colon), L(7, 9), L(7, 9)),
      T("2.0999999e08", TokenValue(kind: FloatNumber,
          floatValue: 2.0999999e08), L(7, 11), L(7, 22)),
      T("", TokenValue(kind: EOF), L(7, 23), L(7,
          23)),
    ],

    "C19": @[
      T("mixed", TokenValue(kind: Word), L(1, 1), L(
          1, 5)),
      T(":", TokenValue(kind: Colon), L(1, 6), L(1, 6)),
      T("[", TokenValue(kind: LeftBracket), L(1, 8),
          L(1, 8)),
      T("\"VALIGN\"", TokenValue(kind: StringToken,
          stringValue: "VALIGN"), L(1, 10), L(1, 17)),
      T(",", TokenValue(kind: Comma), L(1, 18), L(1,
          18)),
      T("[", TokenValue(kind: LeftBracket), L(1, 20),
          L(1, 20)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(1, 22),
          L(1, 22)),
      T(",", TokenValue(kind: Comma), L(1, 23), L(1,
          23)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(1, 25),
          L(1, 25)),
      T("]", TokenValue(kind: RightBracket), L(1, 27),
          L(1, 27)),
      T(",", TokenValue(kind: Comma), L(1, 28), L(1,
          28)),
      T("[", TokenValue(kind: LeftBracket), L(1, 30),
          L(1, 30)),
      T("-1", TokenValue(kind: IntegerNumber, intValue: -1), L(1, 32),
          L(1, 34)),
      T(",", TokenValue(kind: Comma), L(1, 34), L(1,
          34)),
      T("-1", TokenValue(kind: IntegerNumber, intValue: -1), L(1, 36),
          L(1, 38)),
      T("]", TokenValue(kind: RightBracket), L(1, 39),
          L(1, 39)),
      T(",", TokenValue(kind: Comma), L(1, 40), L(1,
          40)),
      T("\"TOP\"", TokenValue(kind: StringToken, stringValue: "TOP"),
          L(1, 42), L(1, 46)),
      T("]", TokenValue(kind: RightBracket), L(1, 48),
          L(1, 48)),
      T("\n", TokenValue(kind: Newline), L(1, 49), L(
          2, 0)),
      T("simple", TokenValue(kind: Word), L(2, 1), L(
          2, 6)),
      T(":", TokenValue(kind: Colon), L(2, 7), L(2, 7)),
      T("[", TokenValue(kind: LeftBracket), L(2, 9),
          L(2, 9)),
      T("1", TokenValue(kind: IntegerNumber, intValue: 1), L(2, 10),
          L(2, 10)),
      T(",", TokenValue(kind: Comma), L(2, 11), L(2,
          11)),
      T("2", TokenValue(kind: IntegerNumber, intValue: 2), L(2, 13),
          L(2, 13)),
      T("]", TokenValue(kind: RightBracket), L(2, 14),
          L(2, 14)),
      T("\n", TokenValue(kind: Newline), L(2, 15), L(
          3, 0)),
      T("nested", TokenValue(kind: Word), L(3, 1), L(
          3, 6)),
      T(":", TokenValue(kind: Colon), L(3, 7), L(3, 7)),
      T("[", TokenValue(kind: LeftBracket), L(3, 9),
          L(3, 9)),
      T("1", TokenValue(kind: IntegerNumber, intValue: 1), L(3, 10),
          L(3, 10)),
      T(",", TokenValue(kind: Comma), L(3, 11), L(3,
          11)),
      T("[", TokenValue(kind: LeftBracket), L(3, 13),
          L(3, 13)),
      T("2", TokenValue(kind: IntegerNumber, intValue: 2), L(3, 14),
          L(3, 14)),
      T(",", TokenValue(kind: Comma), L(3, 15), L(3,
          15)),
      T("3", TokenValue(kind: IntegerNumber, intValue: 3), L(3, 17),
          L(3, 17)),
      T("]", TokenValue(kind: RightBracket), L(3, 18),
          L(3, 18)),
      T(",", TokenValue(kind: Comma), L(3, 19), L(3,
          19)),
      T("[", TokenValue(kind: LeftBracket), L(3, 21),
          L(3, 21)),
      T("4", TokenValue(kind: IntegerNumber, intValue: 4), L(3, 22),
          L(3, 22)),
      T(",", TokenValue(kind: Comma), L(3, 23), L(3,
          23)),
      T("[", TokenValue(kind: LeftBracket), L(3, 25),
          L(3, 25)),
      T("5", TokenValue(kind: IntegerNumber, intValue: 5), L(3, 26),
          L(3, 26)),
      T(",", TokenValue(kind: Comma), L(3, 27), L(3,
          27)),
      T("6", TokenValue(kind: IntegerNumber, intValue: 6), L(3, 29),
          L(3, 29)),
      T("]", TokenValue(kind: RightBracket), L(3, 30),
          L(3, 30)),
      T("]", TokenValue(kind: RightBracket), L(3, 31),
          L(3, 31)),
      T("]", TokenValue(kind: RightBracket), L(3, 32),
          L(3, 32)),
      T("", TokenValue(kind: EOF), L(3, 33), L(3,
          33)),
    ],

    "C20": @[
      T("value1", TokenValue(kind: Word), L(1, 1), L(
          1, 6)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("10", TokenValue(kind: IntegerNumber, intValue: 10), L(1, 10),
          L(1, 12)),
      T("\n", TokenValue(kind: Newline), L(1, 12), L(
          2, 0)),
      T("value2", TokenValue(kind: Word), L(2, 1), L(
          2, 6)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("5", TokenValue(kind: IntegerNumber, intValue: 5), L(2, 10),
          L(2, 10)),
      T("\n", TokenValue(kind: Newline), L(2, 11), L(
          3, 0)),
      T("value3", TokenValue(kind: Word), L(3, 1), L(
          3, 6)),
      T(":", TokenValue(kind: Colon), L(3, 8), L(3, 8)),
      T("\'abc\'", TokenValue(kind: StringToken, stringValue: "abc"),
          L(3, 10), L(3, 14)),
      T("\n", TokenValue(kind: Newline), L(3, 15), L(
          4, 0)),
      T("value4", TokenValue(kind: Word), L(4, 1), L(
          4, 6)),
      T(":", TokenValue(kind: Colon), L(4, 8), L(4, 8)),
      T("\"\'ghi\'\"", TokenValue(kind: StringToken,
          stringValue: "\'ghi\'"), L(4, 10), L(4, 16)),
      T("\'\"jkl\"\'", TokenValue(kind: StringToken,
          stringValue: "\"jkl\""), L(4, 18), L(4, 24)),
      T("\n", TokenValue(kind: Newline), L(4, 25), L(
          5, 0)),
      T("value5", TokenValue(kind: Word), L(5, 1), L(
          5, 6)),
      T(":", TokenValue(kind: Colon), L(5, 8), L(5, 8)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(5, 10),
          L(5, 10)),
      T("\n", TokenValue(kind: Newline), L(5, 11), L(
          6, 0)),
      T("value6", TokenValue(kind: Word), L(6, 1), L(
          6, 6)),
      T(":", TokenValue(kind: Colon), L(6, 8), L(6, 8)),
      T("{", TokenValue(kind: LeftCurly), L(6, 10),
          L(6, 10)),
      T("\'a\'", TokenValue(kind: StringToken, stringValue: "a"), L(6,
          12), L(6, 14)),
      T(":", TokenValue(kind: Colon), L(6, 16), L(6,
          16)),
      T("$", TokenValue(kind: Dollar), L(6, 18), L(6,
          18)),
      T("{", TokenValue(kind: LeftCurly), L(6, 19),
          L(6, 19)),
      T("value1", TokenValue(kind: Word), L(6, 20),
          L(6, 25)),
      T("}", TokenValue(kind: RightCurly), L(6, 26),
          L(6, 26)),
      T(",", TokenValue(kind: Comma), L(6, 27), L(6,
          27)),
      T("\'b\'", TokenValue(kind: StringToken, stringValue: "b"), L(6,
          29), L(6, 31)),
      T(":", TokenValue(kind: Colon), L(6, 32), L(6,
          32)),
      T("$", TokenValue(kind: Dollar), L(6, 34), L(6,
          34)),
      T("{", TokenValue(kind: LeftCurly), L(6, 35),
          L(6, 35)),
      T("value2", TokenValue(kind: Word), L(6, 36),
          L(6, 41)),
      T("}", TokenValue(kind: RightCurly), L(6, 42),
          L(6, 42)),
      T("}", TokenValue(kind: RightCurly), L(6, 44),
          L(6, 44)),
      T("\n", TokenValue(kind: Newline), L(6, 45), L(
          7, 0)),
      T("derived1", TokenValue(kind: Word), L(7, 1),
          L(7, 8)),
      T(":", TokenValue(kind: Colon), L(7, 10), L(7,
          10)),
      T("$", TokenValue(kind: Dollar), L(7, 12), L(7,
          12)),
      T("{", TokenValue(kind: LeftCurly), L(7, 13),
          L(7, 13)),
      T("value1", TokenValue(kind: Word), L(7, 14),
          L(7, 19)),
      T("}", TokenValue(kind: RightCurly), L(7, 20),
          L(7, 20)),
      T("+", TokenValue(kind: Plus), L(7, 22), L(7,
          22)),
      T("$", TokenValue(kind: Dollar), L(7, 24), L(7,
          24)),
      T("{", TokenValue(kind: LeftCurly), L(7, 25),
          L(7, 25)),
      T("value2", TokenValue(kind: Word), L(7, 26),
          L(7, 31)),
      T("}", TokenValue(kind: RightCurly), L(7, 32),
          L(7, 32)),
      T("\n", TokenValue(kind: Newline), L(7, 33), L(
          8, 0)),
      T("derived2", TokenValue(kind: Word), L(8, 1),
          L(8, 8)),
      T(":", TokenValue(kind: Colon), L(8, 10), L(8,
          10)),
      T("$", TokenValue(kind: Dollar), L(8, 12), L(8,
          12)),
      T("{", TokenValue(kind: LeftCurly), L(8, 13),
          L(8, 13)),
      T("value1", TokenValue(kind: Word), L(8, 14),
          L(8, 19)),
      T("}", TokenValue(kind: RightCurly), L(8, 20),
          L(8, 20)),
      T("-", TokenValue(kind: Minus), L(8, 22), L(8,
          22)),
      T("$", TokenValue(kind: Dollar), L(8, 24), L(8,
          24)),
      T("{", TokenValue(kind: LeftCurly), L(8, 25),
          L(8, 25)),
      T("value2", TokenValue(kind: Word), L(8, 26),
          L(8, 31)),
      T("}", TokenValue(kind: RightCurly), L(8, 32),
          L(8, 32)),
      T("\n", TokenValue(kind: Newline), L(8, 33), L(
          9, 0)),
      T("derived3", TokenValue(kind: Word), L(9, 1),
          L(9, 8)),
      T(":", TokenValue(kind: Colon), L(9, 10), L(9,
          10)),
      T("$", TokenValue(kind: Dollar), L(9, 12), L(9,
          12)),
      T("{", TokenValue(kind: LeftCurly), L(9, 13),
          L(9, 13)),
      T("value1", TokenValue(kind: Word), L(9, 14),
          L(9, 19)),
      T("}", TokenValue(kind: RightCurly), L(9, 20),
          L(9, 20)),
      T("*", TokenValue(kind: Star), L(9, 22), L(9,
          22)),
      T("$", TokenValue(kind: Dollar), L(9, 24), L(9,
          24)),
      T("{", TokenValue(kind: LeftCurly), L(9, 25),
          L(9, 25)),
      T("value2", TokenValue(kind: Word), L(9, 26),
          L(9, 31)),
      T("}", TokenValue(kind: RightCurly), L(9, 32),
          L(9, 32)),
      T("\n", TokenValue(kind: Newline), L(9, 33), L(
          10, 0)),
      T("derived4", TokenValue(kind: Word), L(10, 1),
          L(10, 8)),
      T(":", TokenValue(kind: Colon), L(10, 10), L(
          10, 10)),
      T("(", TokenValue(kind: LeftParenthesis), L(10,
          12), L(10, 12)),
      T("$", TokenValue(kind: Dollar), L(10, 13), L(
          10, 13)),
      T("{", TokenValue(kind: LeftCurly), L(10, 14),
          L(10, 14)),
      T("value1", TokenValue(kind: Word), L(10, 15),
          L(10, 20)),
      T("}", TokenValue(kind: RightCurly), L(10, 21),
          L(10, 21)),
      T("/", TokenValue(kind: Slash), L(10, 23), L(
          10, 23)),
      T("$", TokenValue(kind: Dollar), L(10, 25), L(
          10, 25)),
      T("{", TokenValue(kind: LeftCurly), L(10, 26),
          L(10, 26)),
      T("value2", TokenValue(kind: Word), L(10, 27),
          L(10, 32)),
      T("}", TokenValue(kind: RightCurly), L(10, 33),
          L(10, 33)),
      T(")", TokenValue(kind: RightParenthesis), L(10,
          34), L(10, 34)),
      T("+", TokenValue(kind: Plus), L(10, 36), L(10,
          36)),
      T("$", TokenValue(kind: Dollar), L(10, 38), L(
          10, 38)),
      T("{", TokenValue(kind: LeftCurly), L(10, 39),
          L(10, 39)),
      T("value5", TokenValue(kind: Word), L(10, 40),
          L(10, 45)),
      T("}", TokenValue(kind: RightCurly), L(10, 46),
          L(10, 46)),
      T("\n", TokenValue(kind: Newline), L(10, 47),
          L(11, 0)),
      T("derived5", TokenValue(kind: Word), L(11, 1),
          L(11, 8)),
      T(":", TokenValue(kind: Colon), L(11, 10), L(
          11, 10)),
      T("$", TokenValue(kind: Dollar), L(11, 12), L(
          11, 12)),
      T("{", TokenValue(kind: LeftCurly), L(11, 13),
          L(11, 13)),
      T("value1", TokenValue(kind: Word), L(11, 14),
          L(11, 19)),
      T("}", TokenValue(kind: RightCurly), L(11, 20),
          L(11, 20)),
      T("%", TokenValue(kind: Modulo), L(11, 22), L(
          11, 22)),
      T("$", TokenValue(kind: Dollar), L(11, 24), L(
          11, 24)),
      T("{", TokenValue(kind: LeftCurly), L(11, 25),
          L(11, 25)),
      T("value2", TokenValue(kind: Word), L(11, 26),
          L(11, 31)),
      T("}", TokenValue(kind: RightCurly), L(11, 32),
          L(11, 32)),
      T("\n", TokenValue(kind: Newline), L(11, 33),
          L(12, 0)),
      T("derived6", TokenValue(kind: Word), L(12, 1),
          L(12, 8)),
      T(":", TokenValue(kind: Colon), L(12, 10), L(
          12, 10)),
      T("$", TokenValue(kind: Dollar), L(12, 12), L(
          12, 12)),
      T("{", TokenValue(kind: LeftCurly), L(12, 13),
          L(12, 13)),
      T("value3", TokenValue(kind: Word), L(12, 14),
          L(12, 19)),
      T("}", TokenValue(kind: RightCurly), L(12, 20),
          L(12, 20)),
      T("+", TokenValue(kind: Plus), L(12, 22), L(12,
          22)),
      T("$", TokenValue(kind: Dollar), L(12, 24), L(
          12, 24)),
      T("{", TokenValue(kind: LeftCurly), L(12, 25),
          L(12, 25)),
      T("value4", TokenValue(kind: Word), L(12, 26),
          L(12, 31)),
      T("}", TokenValue(kind: RightCurly), L(12, 32),
          L(12, 32)),
      T("\n", TokenValue(kind: Newline), L(12, 33),
          L(13, 0)),
      T("derived7", TokenValue(kind: Word), L(13, 1),
          L(13, 8)),
      T(":", TokenValue(kind: Colon), L(13, 10), L(
          13, 10)),
      T("$", TokenValue(kind: Dollar), L(13, 12), L(
          13, 12)),
      T("{", TokenValue(kind: LeftCurly), L(13, 13),
          L(13, 13)),
      T("value3", TokenValue(kind: Word), L(13, 14),
          L(13, 19)),
      T("}", TokenValue(kind: RightCurly), L(13, 20),
          L(13, 20)),
      T("+", TokenValue(kind: Plus), L(13, 22), L(13,
          22)),
      T("\'def\'", TokenValue(kind: StringToken, stringValue: "def"),
          L(13, 24), L(13, 28)),
      T("+", TokenValue(kind: Plus), L(13, 30), L(13,
          30)),
      T("$", TokenValue(kind: Dollar), L(13, 32), L(
          13, 32)),
      T("{", TokenValue(kind: LeftCurly), L(13, 33),
          L(13, 33)),
      T("value4", TokenValue(kind: Word), L(13, 34),
          L(13, 39)),
      T("}", TokenValue(kind: RightCurly), L(13, 40),
          L(13, 40)),
      T("\n", TokenValue(kind: Newline), L(13, 41),
          L(14, 0)),
      T("derived8", TokenValue(kind: Word), L(14, 1),
          L(14, 8)),
      T(":", TokenValue(kind: Colon), L(14, 10), L(
          14, 10)),
      T("$", TokenValue(kind: Dollar), L(14, 12), L(
          14, 12)),
      T("{", TokenValue(kind: LeftCurly), L(14, 13),
          L(14, 13)),
      T("value3", TokenValue(kind: Word), L(14, 14),
          L(14, 19)),
      T("}", TokenValue(kind: RightCurly), L(14, 20),
          L(14, 20)),
      T("-", TokenValue(kind: Minus), L(14, 22), L(
          14, 22)),
      T("$", TokenValue(kind: Dollar), L(14, 24), L(
          14, 24)),
      T("{", TokenValue(kind: LeftCurly), L(14, 25),
          L(14, 25)),
      T("value4", TokenValue(kind: Word), L(14, 26),
          L(14, 31)),
      T("}", TokenValue(kind: RightCurly), L(14, 32),
          L(14, 32)),
      T("\n", TokenValue(kind: Newline), L(14, 33),
          L(15, 0)),
      T("derived9", TokenValue(kind: Word), L(15, 1),
          L(15, 8)),
      T(":", TokenValue(kind: Colon), L(15, 10), L(
          15, 10)),
      T("$", TokenValue(kind: Dollar), L(15, 12), L(
          15, 12)),
      T("{", TokenValue(kind: LeftCurly), L(15, 13),
          L(15, 13)),
      T("value1", TokenValue(kind: Word), L(15, 14),
          L(15, 19)),
      T("}", TokenValue(kind: RightCurly), L(15, 20),
          L(15, 20)),
      T("//", TokenValue(kind: SlashSlash), L(15, 22),
          L(15, 23)),
      T("$", TokenValue(kind: Dollar), L(15, 25), L(
          15, 25)),
      T("{", TokenValue(kind: LeftCurly), L(15, 26),
          L(15, 26)),
      T("value5", TokenValue(kind: Word), L(15, 27),
          L(15, 32)),
      T("}", TokenValue(kind: RightCurly), L(15, 33),
          L(15, 33)),
      T("\n", TokenValue(kind: Newline), L(15, 34),
          L(16, 0)),
      T("derived10", TokenValue(kind: Word), L(16, 1),
          L(16, 9)),
      T(":", TokenValue(kind: Colon), L(16, 11), L(
          16, 11)),
      T("$", TokenValue(kind: Dollar), L(16, 13), L(
          16, 13)),
      T("{", TokenValue(kind: LeftCurly), L(16, 14),
          L(16, 14)),
      T("value1", TokenValue(kind: Word), L(16, 15),
          L(16, 20)),
      T("}", TokenValue(kind: RightCurly), L(16, 21),
          L(16, 21)),
      T("%", TokenValue(kind: Modulo), L(16, 23), L(
          16, 23)),
      T("$", TokenValue(kind: Dollar), L(16, 25), L(
          16, 25)),
      T("{", TokenValue(kind: LeftCurly), L(16, 26),
          L(16, 26)),
      T("value5", TokenValue(kind: Word), L(16, 27),
          L(16, 32)),
      T("}", TokenValue(kind: RightCurly), L(16, 33),
          L(16, 33)),
      T("\n", TokenValue(kind: Newline), L(16, 34),
          L(17, 0)),
      T("derived11", TokenValue(kind: Word), L(17, 1),
          L(17, 9)),
      T(":", TokenValue(kind: Colon), L(17, 11), L(
          17, 11)),
      T("$", TokenValue(kind: Dollar), L(17, 13), L(
          17, 13)),
      T("{", TokenValue(kind: LeftCurly), L(17, 14),
          L(17, 14)),
      T("value17", TokenValue(kind: Word), L(17, 15),
          L(17, 21)),
      T("}", TokenValue(kind: RightCurly), L(17, 22),
          L(17, 22)),
      T("# non-existent", TokenValue(kind: Newline), L(
          17, 41), L(18, 0)),
      T("derived12", TokenValue(kind: Word), L(18, 1),
          L(18, 9)),
      T(":", TokenValue(kind: Colon), L(18, 11), L(
          18, 11)),
      T("$", TokenValue(kind: Dollar), L(18, 13), L(
          18, 13)),
      T("{", TokenValue(kind: LeftCurly), L(18, 14),
          L(18, 14)),
      T("value6", TokenValue(kind: Word), L(18, 15),
          L(18, 20)),
      T("}", TokenValue(kind: RightCurly), L(18, 21),
          L(18, 21)),
      T(".", TokenValue(kind: Dot), L(18, 22), L(18,
          22)),
      T("a", TokenValue(kind: Word), L(18, 23), L(18,
          23)),
      T("+", TokenValue(kind: Plus), L(18, 25), L(18,
          25)),
      T("$", TokenValue(kind: Dollar), L(18, 27), L(
          18, 27)),
      T("{", TokenValue(kind: LeftCurly), L(18, 28),
          L(18, 28)),
      T("value6", TokenValue(kind: Word), L(18, 29),
          L(18, 34)),
      T("}", TokenValue(kind: RightCurly), L(18, 35),
          L(18, 35)),
      T(".", TokenValue(kind: Dot), L(18, 36), L(18,
          36)),
      T("b", TokenValue(kind: Word), L(18, 37), L(18,
          37)),
      T("", TokenValue(kind: EOF), L(18, 38), L(18,
          38)),
    ],

    "C21": @[
      T("stderr", TokenValue(kind: Word), L(1, 1), L(
          1, 6)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(1, 10), L(1, 21)),
      T("\n", TokenValue(kind: Newline), L(1, 22), L(
          2, 0)),
      T("stdout", TokenValue(kind: Word), L(2, 1), L(
          2, 6)),
      T(":", TokenValue(kind: Colon), L(2, 8), L(2, 8)),
      T("`sys.stdout`", TokenValue(kind: BackTick,
          stringValue: "sys.stdout"), L(2, 10), L(2, 21)),
      T("\n", TokenValue(kind: Newline), L(2, 22), L(
          3, 0)),
      T("stdin", TokenValue(kind: Word), L(3, 1), L(
          3, 5)),
      T(":", TokenValue(kind: Colon), L(3, 7), L(3, 7)),
      T("`sys.stdin`", TokenValue(kind: BackTick,
          stringValue: "sys.stdin"), L(3, 9), L(3, 19)),
      T("\n", TokenValue(kind: Newline), L(3, 20), L(
          4, 0)),
      T("debug", TokenValue(kind: Word), L(4, 1), L(
          4, 5)),
      T(":", TokenValue(kind: Colon), L(4, 7), L(4, 7)),
      T("`debug`", TokenValue(kind: BackTick, stringValue: "debug"),
          L(4, 9), L(4, 15)),
      T("\n", TokenValue(kind: Newline), L(4, 16), L(
          5, 0)),
      T("DEBUG", TokenValue(kind: Word), L(5, 1), L(
          5, 5)),
      T(":", TokenValue(kind: Colon), L(5, 7), L(5, 7)),
      T("`DEBUG`", TokenValue(kind: BackTick, stringValue: "DEBUG"),
          L(5, 9), L(5, 15)),
      T("\n", TokenValue(kind: Newline), L(5, 16), L(
          6, 0)),
      T("derived", TokenValue(kind: Word), L(6, 1),
          L(6, 7)),
      T(":", TokenValue(kind: Colon), L(6, 8), L(6, 8)),
      T("$", TokenValue(kind: Dollar), L(6, 10), L(6,
          10)),
      T("{", TokenValue(kind: LeftCurly), L(6, 11),
          L(6, 11)),
      T("DEBUG", TokenValue(kind: Word), L(6, 12), L(
          6, 16)),
      T("}", TokenValue(kind: RightCurly), L(6, 17),
          L(6, 17)),
      T("*", TokenValue(kind: Star), L(6, 19), L(6,
          19)),
      T("10", TokenValue(kind: IntegerNumber, intValue: 10), L(6, 21),
          L(6, 22)),
      T("", TokenValue(kind: EOF), L(6, 23), L(6,
          23)),
    ],

    "C22": @[
      T("messages", TokenValue(kind: Word), L(1, 1),
          L(1, 8)),
      T(":", TokenValue(kind: Colon), L(1, 9), L(1, 9)),
      T("\n", TokenValue(kind: Newline), L(1, 10), L(
          2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("\n", TokenValue(kind: Newline), L(2, 2), L(
          3, 0)),
      T("{", TokenValue(kind: LeftCurly), L(3, 3), L(
          3, 3)),
      T("\n", TokenValue(kind: Newline), L(3, 4), L(
          4, 0)),
      T("stream", TokenValue(kind: Word), L(4, 5), L(
          4, 10)),
      T(":", TokenValue(kind: Colon), L(4, 12), L(4,
          12)),
      T("`sys.stderr`", TokenValue(kind: BackTick,
          stringValue: "sys.stderr"), L(4, 14), L(4, 25)),
      T("\n", TokenValue(kind: Newline), L(4, 26), L(
          5, 0)),
      T("message", TokenValue(kind: Word), L(5, 5),
          L(5, 11)),
      T(":", TokenValue(kind: Colon), L(5, 12), L(5,
          12)),
      T("\'Welcome\'", TokenValue(kind: StringToken,
          stringValue: "Welcome"), L(5, 14), L(5, 22)),
      T("\n", TokenValue(kind: Newline), L(5, 23), L(
          6, 0)),
      T("name", TokenValue(kind: Word), L(6, 5), L(6, 8)),
      T(":", TokenValue(kind: Colon), L(6, 9), L(6, 9)),
      T("\'Harry\'", TokenValue(kind: StringToken,
          stringValue: "Harry"), L(6, 11), L(6, 17)),
      T("\n", TokenValue(kind: Newline), L(6, 18), L(
          7, 0)),
      T("}", TokenValue(kind: RightCurly), L(7, 3),
          L(7, 3)),
      T("\n", TokenValue(kind: Newline), L(7, 4), L(
          8, 0)),
      T("{", TokenValue(kind: LeftCurly), L(8, 3), L(
          8, 3)),
      T("\n", TokenValue(kind: Newline), L(8, 4), L(
          9, 0)),
      T("stream", TokenValue(kind: Word), L(9, 5), L(
          9, 10)),
      T(":", TokenValue(kind: Colon), L(9, 12), L(9,
          12)),
      T("`sys.stdout`", TokenValue(kind: BackTick,
          stringValue: "sys.stdout"), L(9, 14), L(9, 25)),
      T("\n", TokenValue(kind: Newline), L(9, 26), L(
          10, 0)),
      T("message", TokenValue(kind: Word), L(10, 5),
          L(10, 11)),
      T(":", TokenValue(kind: Colon), L(10, 12), L(
          10, 12)),
      T("\'Welkom\'", TokenValue(kind: StringToken,
          stringValue: "Welkom"), L(10, 14), L(10, 21)),
      T("\n", TokenValue(kind: Newline), L(10, 22),
          L(11, 0)),
      T("name", TokenValue(kind: Word), L(11, 5), L(
          11, 8)),
      T(":", TokenValue(kind: Colon), L(11, 9), L(11, 9)),
      T("\'Ruud\'", TokenValue(kind: StringToken, stringValue: "Ruud"),
          L(11, 11), L(11, 16)),
      T("\n", TokenValue(kind: Newline), L(11, 17),
          L(12, 0)),
      T("}", TokenValue(kind: RightCurly), L(12, 3),
          L(12, 3)),
      T("\n", TokenValue(kind: Newline), L(12, 4), L(
          13, 0)),
      T("# override an existing value with specific elements",
          TokenValue(kind: Newline), L(13, 3), L(14, 0)),
      T("$", TokenValue(kind: Dollar), L(14, 3), L(
          14, 3)),
      T("{", TokenValue(kind: LeftCurly), L(14, 4),
          L(14, 4)),
      T("messages", TokenValue(kind: Word), L(14, 5),
          L(14, 12)),
      T("[", TokenValue(kind: LeftBracket), L(14, 13),
          L(14, 13)),
      T("0", TokenValue(kind: IntegerNumber, intValue: 0), L(14, 14),
          L(14, 14)),
      T("]", TokenValue(kind: RightBracket), L(14, 15),
          L(14, 15)),
      T("}", TokenValue(kind: RightCurly), L(14, 16),
          L(14, 16)),
      T("+", TokenValue(kind: Plus), L(14, 18), L(14,
          18)),
      T("{", TokenValue(kind: LeftCurly), L(14, 20),
          L(14, 20)),
      T("message", TokenValue(kind: Word), L(14, 21),
          L(14, 27)),
      T(":", TokenValue(kind: Colon), L(14, 28), L(
          14, 28)),
      T("Bienvenue", TokenValue(kind: Word), L(14, 30),
          L(14, 38)),
      T(",", TokenValue(kind: Comma), L(14, 39), L(
          14, 39)),
      T("name", TokenValue(kind: Word), L(14, 41), L(
          14, 44)),
      T(":", TokenValue(kind: Colon), L(14, 45), L(
          14, 45)),
      T("Yves", TokenValue(kind: Word), L(14, 47), L(
          14, 50)),
      T("}", TokenValue(kind: RightCurly), L(14, 51),
          L(14, 51)),
      T("\n", TokenValue(kind: Newline), L(14, 52),
          L(15, 0)),
      T("]", TokenValue(kind: RightBracket), L(15, 1),
          L(15, 1)),
      T("", TokenValue(kind: EOF), L(15, 2), L(15, 2)),
    ],

    "C23": @[
      T("foo", TokenValue(kind: Word), L(1, 1), L(1, 3)),
      T(":", TokenValue(kind: Colon), L(1, 4), L(1, 4)),
      T("\n", TokenValue(kind: Newline), L(1, 5), L(
          2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("\n", TokenValue(kind: Newline), L(2, 2), L(
          3, 0)),
      T("bar", TokenValue(kind: Word), L(3, 5), L(3, 7)),
      T("\n", TokenValue(kind: Newline), L(3, 8), L(
          4, 0)),
      T("baz", TokenValue(kind: Word), L(4, 5), L(4, 7)),
      T("\n", TokenValue(kind: Newline), L(4, 8), L(
          5, 0)),
      T("bozz", TokenValue(kind: Word), L(5, 5), L(5, 8)),
      T("\n", TokenValue(kind: Newline), L(5, 9), L(
          6, 0)),
      T("]", TokenValue(kind: RightBracket), L(6, 1),
          L(6, 1)),
      T("", TokenValue(kind: EOF), L(6, 2), L(6, 2)),
    ],

    "C24": @[
      T("foo", TokenValue(kind: Word), L(1, 1), L(1, 3)),
      T(":", TokenValue(kind: Colon), L(1, 4), L(1, 4)),
      T("[", TokenValue(kind: LeftBracket), L(1, 6),
          L(1, 6)),
      T("\n", TokenValue(kind: Newline), L(1, 7), L(
          2, 0)),
      T("\'bar\'", TokenValue(kind: StringToken, stringValue: "bar"),
          L(2, 5), L(2, 9)),
      T(",", TokenValue(kind: Comma), L(2, 10), L(2,
          10)),
      T("\n", TokenValue(kind: Newline), L(2, 11), L(
          3, 0)),
      T("a", TokenValue(kind: Word), L(3, 5), L(3, 5)),
      T("+", TokenValue(kind: Plus), L(3, 7), L(3, 7)),
      T("b", TokenValue(kind: Word), L(3, 9), L(3, 9)),
      T("-", TokenValue(kind: Minus), L(3, 11), L(3,
          11)),
      T("c", TokenValue(kind: Word), L(3, 13), L(3,
          13)),
      T("+", TokenValue(kind: Plus), L(3, 15), L(3,
          15)),
      T("d", TokenValue(kind: Word), L(3, 17), L(3,
          17)),
      T("\n", TokenValue(kind: Newline), L(3, 18), L(
          4, 0)),
      T("]", TokenValue(kind: RightBracket), L(4, 1),
          L(4, 1)),
      T("", TokenValue(kind: EOF), L(4, 2), L(4, 2)),
    ],

    "C25": @[
      T("unicode", TokenValue(kind: Word), L(1, 1),
          L(1, 7)),
      T("=", TokenValue(kind: Assign), L(1, 9), L(1, 9)),
      T("'Grüß Gott'", TokenValue(kind: StringToken,
          stringValue: "Grüß Gott"), L(1, 11), L(1, 21)),
      T("\n", TokenValue(kind: Newline), L(1, 22), L(
          2, 0)),
      T("more_unicode", TokenValue(kind: Word), L(2,
          1), L(2, 12)),
      T(":", TokenValue(kind: Colon), L(2, 13), L(2,
          13)),
      T("'Øresund'", TokenValue(kind: StringToken,
          stringValue: "Øresund"), L(2, 15), L(2, 23)),
      T("", TokenValue(kind: EOF), L(2, 24), L(2,
          24)),
    ],

    "C26": @[
      T("foo", TokenValue(kind: Word), L(1, 5), L(1, 7)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("[", TokenValue(kind: LeftBracket), L(1, 10),
          L(1, 10)),
      T("\n", TokenValue(kind: Newline), L(1, 11), L(
          2, 0)),
      T("\'bar\'", TokenValue(kind: StringToken, stringValue: "bar"),
          L(2, 9), L(2, 13)),
      T(",", TokenValue(kind: Comma), L(2, 14), L(2,
          14)),
      T("\n", TokenValue(kind: Newline), L(2, 15), L(
          3, 0)),
      T("a", TokenValue(kind: Word), L(3, 9), L(3, 9)),
      T("+", TokenValue(kind: Plus), L(3, 11), L(3,
          11)),
      T("b", TokenValue(kind: Word), L(3, 13), L(3,
          13)),
      T("-", TokenValue(kind: Minus), L(3, 15), L(3,
          15)),
      T("c", TokenValue(kind: Word), L(3, 17), L(3,
          17)),
      T("+", TokenValue(kind: Plus), L(3, 19), L(3,
          19)),
      T("d", TokenValue(kind: Word), L(3, 21), L(3,
          21)),
      T("\n", TokenValue(kind: Newline), L(3, 22), L(
          4, 0)),
      T("]", TokenValue(kind: RightBracket), L(4, 5),
          L(4, 5)),
      T("", TokenValue(kind: EOF), L(4, 6), L(4, 6)),
    ],

    "C27": @[
      T("foo", TokenValue(kind: Word), L(1, 5), L(1, 7)),
      T(":", TokenValue(kind: Colon), L(1, 8), L(1, 8)),
      T("(", TokenValue(kind: LeftParenthesis), L(1,
          10), L(1, 10)),
      T("a", TokenValue(kind: Word), L(1, 11), L(1,
          11)),
      T("&", TokenValue(kind: BitwiseAnd), L(1, 13),
          L(1, 13)),
      T("b", TokenValue(kind: Word), L(1, 15), L(1,
          15)),
      T(")", TokenValue(kind: RightParenthesis), L(1,
          16), L(1, 16)),
      T("^", TokenValue(kind: BitwiseXor), L(1, 18),
          L(1, 18)),
      T("(", TokenValue(kind: LeftParenthesis), L(1,
          20), L(1, 20)),
      T("c", TokenValue(kind: Word), L(1, 21), L(1,
          21)),
      T("|", TokenValue(kind: BitwiseOr), L(1, 23),
          L(1, 23)),
      T("d", TokenValue(kind: Word), L(1, 25), L(1,
          25)),
      T(")", TokenValue(kind: RightParenthesis), L(1,
          26), L(1, 26)),
      T("", TokenValue(kind: EOF), L(1, 27), L(1,
          27)),
    ],

    "C28": @[
      T("foo", TokenValue(kind: Word), L(1, 1), L(1, 3)),
      T(":", TokenValue(kind: Colon), L(1, 4), L(1, 4)),
      T("\'\'\'\na multi-line string with internal\n\'\' and \"\" sequences\n\'\'\'",
          TokenValue(kind: StringToken,
          stringValue: "\na multi-line string with internal\n\'\' and \"\" sequences\n"),
          L(1, 6), L(4, 3)),
      T("\n", TokenValue(kind: Newline), L(4, 4), L(
          5, 0)),
      T("bar", TokenValue(kind: Word), L(5, 1), L(5, 3)),
      T(":", TokenValue(kind: Colon), L(5, 4), L(5, 4)),
      T("\"\"\"\nanother multi-line string with internal\n\'\' and \"\" sequences\n\"\"\"",
          TokenValue(kind: StringToken,
          stringValue: "\nanother multi-line string with internal\n\'\' and \"\" sequences\n"),
          L(5, 6), L(8, 3)),
      T("", TokenValue(kind: EOF), L(8, 4), L(8, 4)),
    ],

    "C29": @[
      T("empty_dict", TokenValue(kind: Word), L(1, 1),
          L(1, 10)),
      T(":", TokenValue(kind: Colon), L(1, 11), L(1,
          11)),
      T("{", TokenValue(kind: LeftCurly), L(1, 13),
          L(1, 13)),
      T("\n", TokenValue(kind: Newline), L(1, 14), L(
          2, 0)),
      T("}", TokenValue(kind: RightCurly), L(2, 1),
          L(2, 1)),
      T("", TokenValue(kind: EOF), L(2, 2), L(2, 2)),
    ],

    "C30": @[
      T("empty_list", TokenValue(kind: Word), L(1, 1),
          L(1, 10)),
      T(":", TokenValue(kind: Colon), L(1, 11), L(1,
          11)),
      T("[", TokenValue(kind: LeftBracket), L(1, 13),
          L(1, 13)),
      T("\n", TokenValue(kind: Newline), L(1, 14), L(
          2, 0)),
      T("]", TokenValue(kind: RightBracket), L(2, 1),
          L(2, 1)),
      T("", TokenValue(kind: EOF), L(2, 2), L(2, 2)),
    ],

    "D01": @[
      T("# a plain scalar value is not legal", TokenValue(kind: Newline,
          otherValue: 0), L(1, 1), L(2, 0)),
      T("123", TokenValue(kind: IntegerNumber, intValue: 123), L(2,
          1), L(2, 3)),
      T("", TokenValue(kind: EOF), L(2, 4), L(2, 4)),
    ],

    "D02": @[
      T("# nor is a list (unless using the \'container\' rule)",
          TokenValue(kind: Newline), L(1, 1), L(2, 0)),
      T("[", TokenValue(kind: LeftBracket), L(2, 1),
          L(2, 1)),
      T("123", TokenValue(kind: IntegerNumber, intValue: 123), L(2,
          3), L(2, 6)),
      T(",", TokenValue(kind: Comma), L(2, 6), L(2, 6)),
      T("\'abc\'", TokenValue(kind: StringToken, stringValue: "abc"),
          L(2, 8), L(2, 12)),
      T("]", TokenValue(kind: RightBracket), L(2, 14),
          L(2, 14)),
      T("", TokenValue(kind: EOF), L(2, 15), L(2,
          15)),
    ],

    "D03": @[
      T("# nor is a mapping (unless using the \'container\' rule)",
          TokenValue(kind: Newline), L(1, 1), L(2, 0)),
      T("{", TokenValue(kind: LeftCurly), L(2, 1), L(
          2, 1)),
      T("a", TokenValue(kind: Word), L(2, 3), L(2, 3)),
      T(":", TokenValue(kind: Colon), L(2, 5), L(2, 5)),
      T("7", TokenValue(kind: IntegerNumber, intValue: 7), L(2, 7),
          L(2, 7)),
      T(",", TokenValue(kind: Comma), L(2, 8), L(2, 8)),
      T("b", TokenValue(kind: Word), L(2, 10), L(2,
          10)),
      T(":", TokenValue(kind: Colon), L(2, 12), L(2,
          12)),
      T("1.3", TokenValue(kind: FloatNumber, floatValue: 1.3), L(2,
          14), L(2, 17)),
      T(",", TokenValue(kind: Comma), L(2, 17), L(2,
          17)),
      T("c", TokenValue(kind: Word), L(2, 19), L(2,
          19)),
      T(":", TokenValue(kind: Colon), L(2, 21), L(2,
          21)),
      T("\'test\'", TokenValue(kind: StringToken, stringValue: "test"),
          L(2, 23), L(2, 28)),
      T("}", TokenValue(kind: RightCurly), L(2, 30),
          L(2, 30)),
      T("", TokenValue(kind: EOF), L(2, 31), L(2,
          31)),
    ],

  }.toTable
  for k, s in cases.pairs:
    var t = makeTokenizer(s)
    var tokens = t.getAllTokens
    if k in expected:
      # echo &"*** comparing for {k}"
      compareArrays(expected[k], tokens)
    # else:
    #   dumpTokens(k, tokens)

test "bad tokens":
  type
    TCase = object
      text: string
      msg: string
      loc: Location

  var cases = @[
    # numbers
    TCase(text: "9a", msg: "invalid character in number: a", loc: L(1, 2)),
    TCase(text: "079", msg: "badly formed octal constant: 079", loc: L(1, 1)),
    TCase(text: "0xaBcz", msg: "invalid character in number: z", loc: L(1, 6)),
    TCase(text: "0o79", msg: "invalid character in number: 9", loc: L(1, 4)),
    TCase(text: ".5z", msg: "invalid character in number: z", loc: L(1, 3)),
    TCase(text: "0.5.7", msg: "invalid character in number: 0.5.", loc: L(1, 4)),
    TCase(text: " 0.4e-z", msg: "invalid character in number: z", loc: L(1, 7)),
    TCase(text: " 0.4e-8.3", msg: "invalid character in number: 0.4e-8.",
        loc: L(1, 8)),
    TCase(text: " 089z", msg: "invalid character in number: z", loc: L(1, 5)),
    TCase(text: "0o89z", msg: "invalid character in number: 8", loc: L(1, 3)),
    TCase(text: "0X89g", msg: "invalid character in number: g", loc: L(1, 5)),
    TCase(text: "10z", msg: "invalid character in number: z", loc: L(1, 3)),
    TCase(text: " 0.4e-8Z", msg: "invalid character in number: Z", loc: L(1, 8)),
    TCase(text: "123_", msg: "invalid '_' at end of number: 123_", loc: L(1, 1)),
    TCase(text: "1__23", msg: "invalid '_' in number: 1__", loc: L(1, 3)),
    TCase(text: "1_2__3", msg: "invalid '_' in number: 1_2__", loc: L(1, 5)),
    TCase(text: " 0.4e-8_", msg: "invalid '_' at end of number: 0.4e-8_",
        loc: L(1, 2)),
    TCase(text: " 0.4_e-8", msg: "invalid character in number: e", loc: L(1, 6)),
    TCase(text: " 0._4e-8", msg: "invalid '_' in number: 0._", loc: L(1, 4)),
    # strings
    TCase(text: "'", msg: "unterminated quoted string: '", loc: L(1, 1)),
    TCase(text: "\"", msg: "unterminated quoted string: \"", loc: L(1, 1)),
    TCase(text: "'''", msg: "unterminated quoted string: '''", loc: L(1, 1)),
    TCase(text: "\"abc", msg: "unterminated quoted string: \"abc", loc: L(1, 1)),
    TCase(text: "\"abc\\\ndef", msg: "unterminated quoted string: \"abc\\\ndef",
        loc: L(1, 1)),
    #other
    TCase(text: "\\ ", msg: "unexpected character: \\", loc: L(1, 1)),
    TCase(text: "  ;", msg: "unexpected character: ;", loc: L(1, 3)),
  ]

  for tcase in cases:
    var t = makeTokenizer(tcase.text)
    try:
      discard t.getToken
      assert false, "An exception should have been raised"
    except TokenizerError as e:
      check tcase.msg == e.msg
      check tcase.loc == e.location

test "escapes":
  type
    TCase = object
      text: string
      expected: string

  var cases: seq[TCase] = @[
    TCase(text: "'\\a'", expected: "\a"),
    TCase(text: "'\\b'", expected: "\b"),
    TCase(text: "'\\f'", expected: "\f"),
    TCase(text: "'\\n'", expected: "\n"),
    TCase(text: "'\\r'", expected: "\r"),
    TCase(text: "'\\t'", expected: "\t"),
    TCase(text: "'\\v'", expected: "\v"),
    TCase(text: "'\\\\'", expected: "\\"),
    TCase(text: "'\\''", expected: "'"),
    TCase(text: "'\\\"'", expected: "\""),
    TCase(text: "'\\xAB'", expected: "\xc2\xab"),
    TCase(text: "'\\u2603'", expected: "\xe2\x98\x83"),
    TCase(text: "'\\u28a0abc\\u28a0'", expected: "\xe2\xa2\xa0abc\xe2\xa2\xa0"),
    TCase(text: "'\\u28a0abc'", expected: "\xe2\xa2\xa0abc"),
    TCase(text: "'\\U0010ffff'", expected: "\xf4\x8f\xbf\xbf"),
  ]

  for tcase in cases:
    var t = makeTokenizer(tcase.text)
    var tk = t.getToken
    check tk.kind == StringToken
    check tk.text == tcase.text
    if tcase.expected != tk.value.stringValue:
      echo escape(tcase.expected)
      echo escape(tk.value.stringValue)
    check tcase.expected == tk.value.stringValue

  cases = @[
    TCase(text: "'\\z'", expected: "invalid escape sequence in: \\z"),
    TCase(text: "'\\xa'", expected: "invalid escape sequence in: \\xa"),
    TCase(text: "'\\xaz'", expected: "invalid escape sequence in: \\xaz"),
    TCase(text: "'\\u'", expected: "invalid escape sequence in: \\u"),
    TCase(text: "'\\u0'", expected: "invalid escape sequence in: \\u0"),
    TCase(text: "'\\u01'", expected: "invalid escape sequence in: \\u01"),
    TCase(text: "'\\u012'", expected: "invalid escape sequence in: \\u012"),
    TCase(text: "'\\u012z'", expected: "invalid escape sequence in: \\u012z"),
    TCase(text: "'\\u012zA'", expected: "invalid escape sequence in: \\u012zA"),
    TCase(text: "'\\ud800'", expected: "invalid escape sequence in: \\ud800"),
    TCase(text: "'\\udfff'", expected: "invalid escape sequence in: \\udfff"),
    TCase(text: "'\\U00110000'", expected: "invalid escape sequence in: \\U00110000"),
  ]

  for tcase in cases:
    var t = makeTokenizer(tcase.text)
    try:
      discard t.getToken
      assert false, "An exception should have been raised"
    except TokenizerError as e:
      check tcase.expected == e.msg

#
# Parser
#

proc BN(kind: TokenKind, lhs, rhs: ASTNode): BinaryNode =
  newBinaryNode(kind, lhs, rhs)

proc UN(kind: TokenKind, operand: ASTNode): UnaryNode =
  newUnaryNode(kind, operand)

proc SN(start, stop, step: ASTNode): SliceNode =
  new(result)
  result.kind = Colon
  result.startIndex = start
  result.stopIndex = stop
  result.step = step

proc W(s: string): Token =
  T(s, TokenValue(kind: Word))

proc N(n: int64): Token =
  T($n, TokenValue(kind: IntegerNumber, intValue: n))

proc F(f: float64): Token =
  T($f, TokenValue(kind: FloatNumber, floatValue: f))

proc S(t: string, v: string): Token =
  T(t, TokenValue(kind: StringToken, stringValue: v))

test "parser expressions":
  type
    TCase = object
      text: string
      ev: ASTNode

  var cases: seq[TCase] = @[
    TCase(text: "a + 4", ev: BN(Plus, W("a"), N(4))),
    TCase(text: "foo", ev: W("foo")),
    TCase(text: "0.5", ev: F(0.5)),
    TCase(text: "'foo' \"bar\"", ev: S("'foo'\"bar\"", "foobar")),
    TCase(text: "a.b", ev: BN(Dot, W("a"), W("b"))),

    # unaries
    TCase(text: "+bar", ev: UN(Plus, W("bar"))),
    # TCase(text: "-bar", ev: UN(Minus, W("bar"))),
    TCase(text: "~bar", ev: UN(BitwiseComplement, W("bar"))),
    TCase(text: "not bar", ev: UN(Not, W("bar"))),
    TCase(text: "!bar", ev: UN(Not, W("bar"))),
    TCase(text: "@bar", ev: UN(At, W("bar"))),

    #binaries
    TCase(text: "a + b", ev: BN(Plus, W("a"), W("b"))),
    TCase(text: "a - b", ev: BN(Minus, W("a"), W("b"))),
    TCase(text: "a * b", ev: BN(Star, W("a"), W("b"))),
    TCase(text: "a / b", ev: BN(Slash, W("a"), W("b"))),
    TCase(text: "a // b", ev: BN(SlashSlash, W("a"), W("b"))),
    TCase(text: "a % b", ev: BN(Modulo, W("a"), W("b"))),
    TCase(text: "a ** b", ev: BN(Power, W("a"), W("b"))),
    TCase(text: "a << b", ev: BN(LeftShift, W("a"), W("b"))),
    TCase(text: "a >> b", ev: BN(RightShift, W("a"), W("b"))),
    TCase(text: "a and b", ev: BN(And, W("a"), W("b"))),
    TCase(text: "a && b", ev: BN(And, W("a"), W("b"))),
    TCase(text: "a or b", ev: BN(Or, W("a"), W("b"))),
    TCase(text: "a || b", ev: BN(Or, W("a"), W("b"))),
    TCase(text: "a & b", ev: BN(BitwiseAnd, W("a"), W("b"))),
    TCase(text: "a | b", ev: BN(BitwiseOr, W("a"), W("b"))),
    TCase(text: "a ^ b", ev: BN(BitwiseXor, W("a"), W("b"))),

    TCase(text: "a < b", ev: BN(LessThan, W("a"), W("b"))),
    TCase(text: "a <= b", ev: BN(LessThanOrEqual, W("a"), W("b"))),
    TCase(text: "a > b", ev: BN(GreaterThan, W("a"), W("b"))),
    TCase(text: "a >= b", ev: BN(GreaterThanOrEqual, W("a"), W("b"))),
    TCase(text: "a == b", ev: BN(Equal, W("a"), W("b"))),
    TCase(text: "a != b", ev: BN(Unequal, W("a"), W("b"))),
    TCase(text: "a <> b", ev: BN(AltUnequal, W("a"), W("b"))),
    TCase(text: "a in b", ev: BN(In, W("a"), W("b"))),
    TCase(text: "a not in b", ev: BN(NotIn, W("a"), W("b"))),
    TCase(text: "a is b", ev: BN(Is, W("a"), W("b"))),
    TCase(text: "a is not b", ev: BN(IsNot, W("a"), W("b"))),

    TCase(text: "a + b + c", ev: BN(Plus, BN(Plus, W("a"), W("b")), W("c"))),
    TCase(text: "a - b - c", ev: BN(Minus, BN(Minus, W("a"), W("b")), W("c"))),
    TCase(text: "a * b * c", ev: BN(Star, BN(Star, W("a"), W("b")), W("c"))),
    TCase(text: "a / b / c", ev: BN(Slash, BN(Slash, W("a"), W("b")), W("c"))),
    TCase(text: "a // b // c", ev: BN(SlashSlash, BN(SlashSlash, W("a"), W(
        "b")), W("c"))),
    TCase(text: "a % b % c", ev: BN(Modulo, BN(Modulo, W("a"), W("b")), W("c"))),
    TCase(text: "a << b << c", ev: BN(LeftShift, BN(LeftShift, W("a"), W("b")),
        W("c"))),
    TCase(text: "a >> b >> c", ev: BN(RightShift, BN(RightShift, W("a"), W(
        "b")), W("c"))),
    TCase(text: "a and b and c", ev: BN(And, BN(And, W("a"), W("b")), W("c"))),
    TCase(text: "a or b or c", ev: BN(Or, BN(Or, W("a"), W("b")), W("c"))),
    TCase(text: "a & b & c", ev: BN(BitwiseAnd, BN(BitwiseAnd, W("a"), W("b")),
        W("c"))),
    TCase(text: "a | b | c", ev: BN(BitwiseOr, BN(BitwiseOr, W("a"), W("b")), W("c"))),
    TCase(text: "a ^ b ^ c", ev: BN(BitwiseXor, BN(BitwiseXor, W("a"), W("b")),
        W("c"))),
    TCase(text: "a ** b ** c", ev: BN(Power, W("a"), BN(Power, W("b"), W(
        "c")))),

    TCase(text: "a + b * c", ev: BN(Plus, W("a"), BN(Star, W("b"), W("c")))),
  ]

  for tcase in cases:
    # echo &"Processing {tcase.text}:"
    var p = parserFromSource(tcase.text)
    var av = p.expr()
    compareNodes(tcase.ev, av)

test "parser data":
  var cases = loadData(dataFilePath("testdata.txt"))
  var expected: Table[string, string] = {
    "D01": "unexpected type for key: IntegerNumber",
    "D02": "unexpected type for key: LeftBracket",
    "D03": "unexpected type for key: LeftCurly",
  }.toTable

  for k, s in cases.pairs:
    var p = parserFromSource(s)
    if k < "D01":
      discard p.mappingBody()
      check p.atEnd()
    else:
      try:
        discard p.mappingBody()
      except RecognizerError as e:
        check e.msg == expected[k]

test "json":
  var path = dataFilePath("forms.conf")
  var parser = parserFromFile(path)
  var m = parser.mapping()
  var expected = toHashSet(["refs", "fieldsets", "forms", "modals", "pages"])
  var actual = toHashSet(["foo"])

  actual.excl("foo")
  for (t, e) in m.elements:
    var s: string
    case t.kind
    of Word:
      s = t.text
    else:
      s = t.value.stringValue
    actual.incl(s)
  check expected == actual

test "parser files":
  var d = dataFilePath("derived")
  for kind, p in walkDir(d):
    if kind == pcFile:
      var parser = parserFromFile(p)
      discard parser.container()

test "slices":
  type
    TCase = object
      text: string
      ev: ASTNode

  var cases: seq[TCase] = @[
   TCase(text: "foo[start:stop:step]", ev: SN(W("start"), W("stop"), W(
       "step"))),
   TCase(text: "foo[start:stop]", ev: SN(W("start"), W("stop"), nil)),
   TCase(text: "foo[start:stop:]", ev: SN(W("start"), W("stop"), nil)),
   TCase(text: "foo[start:]", ev: SN(W("start"), nil, nil)),
   TCase(text: "foo[start::]", ev: SN(W("start"), nil, nil)),
   TCase(text: "foo[:stop]", ev: SN(nil, W("stop"), nil)),
   TCase(text: "foo[::step]", ev: SN(nil, nil, W("step"))),
   TCase(text: "foo[::]", ev: SN(nil, nil, nil)),
   TCase(text: "foo[:]", ev: SN(nil, nil, nil)),
   TCase(text: "foo[start::step]", ev: SN(W("start"), nil, W("step"))),
   TCase(text: "foo[start]", ev: nil),
  ]

  for tcase in cases:
    var p = parserFromSource(tcase.text)
    var node = p.expr()

    check node of BinaryNode
    var binode = BinaryNode(node)
    check binode.lhs of Token
    var t = Token(binode.lhs)
    check t.kind == Word
    check t.text == "foo"
    if tcase.text == "foo[start]":
      # non-slice case
      check node.kind == LeftBracket
      check binode.rhs of Token
      t = Token(binode.rhs)
      check t.kind == Word
      check t.text == "start"
    else:
      check node.kind == Colon
      check binode.rhs of SliceNode
      var sn = SliceNode(binode.rhs)
      if not isNil(tcase.ev):
        compareNodes(tcase.ev, sn)

test "bad slices":
  type
    TCase = object
      text: string
      msg: string

  var cases: seq[TCase] = @[
    TCase(text: "foo[start::step:]", msg: "expected RightBracket but got Colon"),
    TCase(text: "foo[a, b:c:d]", msg: "invalid index at (1, 5): expected 1 expression, found 2"),
    TCase(text: "foo[a:b, c:d]", msg: "invalid index at (1, 7): expected 1 expression, found 2"),
    TCase(text: "foo[a:b:c,d, e]", msg: "invalid index at (1, 9): expected 1 expression, found 3"),
  ]

  for tcase in cases:
    var p = parserFromSource(tcase.text)
    try:
      discard p.expr()
      assert false, "Exception should have been raised, but wasn't"
    except RecognizerError as e:
      check e.msg == tcase.msg

#
# Config
#

test "path iteration":
  var node = parsePath("foo[bar].baz.bozz[3].fizz ")
  var actual = unpackPath(node)
  var expected: seq[(TokenKind, ASTNode)] = @[
    (Dot, ASTNode(W("foo"))),
    (LeftBracket, ASTNode(W("bar"))),
    (Dot, ASTNode(W("baz"))),
    (Dot, ASTNode(W("bozz"))),
    (LeftBracket, ASTNode(N(3))),
    (Dot, ASTNode(W("fizz"))),
  ]
  check len(expected) == len(actual)
  for i in 0..high(expected):
    check expected[i][0] == actual[i][0]
    compareNodes(expected[i][1], actual[i][1])

  node = parsePath("foo[1:2]")
  actual = unpackPath(node)
  expected = @[
    (Dot, ASTNode(W("foo"))),
    (Colon, SN(N(1), N(2), nil)),
  ]
  check len(expected) == len(actual)
  for i in 0..high(expected):
    check expected[i][0] == actual[i][0]
    compareNodes(expected[i][1], actual[i][1])

test "bad paths":
  type
    TCase = object
      text: string
      msg: string

  var cases: seq[TCase] = @[
    TCase(text: "foo[1, 2]", msg: "invalid index at (1, 5): expected 1 expression, found 2"),
    TCase(text: "foo[1] bar", msg: "invalid path: foo[1] bar"),
    TCase(text: "foo.123", msg: "invalid path: foo.123"),
    TCase(text: "foo.", msg: "expected Word but got EOF"),
    TCase(text: "foo[]", msg: "invalid index at (1, 5): expected 1 expression, found 0"),
    TCase(text: "foo[1a]", msg: "invalid character in number: a"),
    TCase(text: "4", msg: "invalid path: 4"),
  ]

  for tcase in cases:
    try:
      discard parsePath(tcase.text)
      assert false, "Exception should have been raised but wasn't"
    except RecognizerError as e:
      check tcase.msg == e.msg

test "sources":
  var cases = @[
      "foo[::2]",
      "foo[:]",
      "foo[:2]",
      "foo[2:]",
      "foo[::1]",
      "foo[::-1]",
      "foo[3]",
      "foo[\"bar\"]",
      "foo['bar']"
  ]

  for s in cases:
    var node = parsePath(s)
    check s == toSource(node)

test "identifiers":
  type
    TCase = object
      text: string
      ev: bool

  var cases: seq[TCase] = @[
    TCase(text: "foo", ev: true),
    TCase(text: "\u0935\u092e\u0938", ev: true),
    TCase(text: "\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868", ev: true),
    TCase(text: "foo ", ev: false),
    TCase(text: "foo[", ev: false),
    TCase(text: "foo [", ev: false),
    TCase(text: "foo.", ev: false),
    TCase(text: "foo .", ev: false),
    TCase(text: "\u0935\u092e\u0938.", ev: false),
    TCase(text: "\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868.", ev: false),
    TCase(text: "9", ev: false),
    TCase(text: "9foo", ev: false),
    TCase(text: "hyphenated-key", ev: false),
  ]

  for tcase in cases:
    # echo &"*** {tcase.text} -> {isIdentifier(tcase.text)}"
    check isIdentifier(tcase.text) == tcase.ev
