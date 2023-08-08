#
# Copyright 2016-2023 by Vinay Sajip. All Rights Reserved.
#
import bitops
import complex
import os
import sequtils
import sets
import strformat
import strutils
import tables
import times
import timezones
import typetraits
import unittest

import ../src/config

proc dataFilePath(paths: varargs[string]): string =
  "tests" / "resources" / paths.join("/")

#
# Config
#

test "config files":
  var notMappings = toHashSet([
    "data.cfg",
    "incl_list.cfg",
    "pages.cfg",
    "routes.cfg"
  ])

  var d = dataFilePath("derived")
  var cfg = newConfig()
  for kind, p in walkDir(d):
    if kind == pcFile:
      try:
        cfg.loadFile(p)
      except ConfigError as e:
        var dn, fn: string

        (dn, fn) = splitPath(p)
        if fn in notMappings:
          check e.msg == "root configuration must be a mapping"
        else:
          check fn == "dupes.cfg"
          check e.msg == "duplicate key foo seen at (4, 1) (previously at (1, 1))"

proc CV(s: string): ConfigValue =
  ConfigValue(kind: StringValue, stringValue: s)

proc CV(i: int64): ConfigValue =
  ConfigValue(kind: IntegerValue, intValue: i)

proc CV(f: float64): ConfigValue =
  ConfigValue(kind: FloatValue, floatValue: f)

proc CV(b: bool): ConfigValue =
  ConfigValue(kind: BoolValue, boolValue: b)

proc CV(slist: seq[string]): ConfigValue =
  var vlist: seq[ConfigValue]
  for s in slist:
    vlist.add(CV(s))
  ConfigValue(kind: ListValue, listValue: vlist)

proc CV(list: seq[ConfigValue]): ConfigValue =
  ConfigValue(kind: ListValue, listValue: list)

proc CV(d: DateTime): ConfigValue =
  ConfigValue(kind: DateTimeValue, datetimeValue: d)

proc CV(m: Table[string, ConfigValue]): ConfigValue =
  ConfigValue(kind: MappingValue, mappingValue: m)

proc CV(c: Complex64): ConfigValue =
  ConfigValue(kind: ComplexValue, complexValue: c)

test "main config":
  var p = dataFilePath("derived", "main.cfg")
  var cfg = newConfig()
  cfg.includePath.add(dataFilePath("base"))
  cfg.loadFile(p)

  var lcfg = cfg.getSubConfig("logging")
  var d = lcfg.asDict()
  var keys = toHashSet(d.keys.toSeq)
  check keys == toHashSet(["formatters", "handlers", "loggers", "root"])
  try:
    discard lcfg["handlers.file/filename"]
  except ConfigError as e:
    check e.msg == "invalid path: handlers.file/filename"
  var ev = CV("bar")
  check ev == lcfg.get("foo", ev)
  ev.stringValue = "baz"
  check ev == lcfg.get("foo.bar", ev)
  ev.stringValue = "bozz"
  check ev == lcfg.get("handlers.debug.lvl", ev)
  ev.stringValue = "run/server.log"
  check ev == lcfg["handlers.file.filename"]
  ev.stringValue = "run/server-debug.log"
  check ev == lcfg["handlers.debug.filename"]
  check CV(@["file", "error", "debug"]) == lcfg["root.handlers"]
  check CV("debug") == lcfg["root.handlers[2]"]
  ev = CV(@["file", "error"])
  check ev == lcfg["root.handlers[:2]"]
  ev = CV(@["file", "debug"])
  check ev == lcfg["root.handlers[::2]"]
  var tcfg = cfg.getSubConfig("test")
  check CV(1.0e-7) == tcfg["float"]
  check CV(0.3) == tcfg["float2"]
  check CV(3.0) == tcfg["float3"]
  check CV(2) == tcfg["list[1]"]
  check CV("b") == tcfg["dict.a"]
  var ldt = dateTime(2019, Month(3), 28)
  check CV(ldt) == tcfg["date"]
  ldt = dateTime(2019, Month(3), 28, 23, 27, 4, 314159000, staticTz(5, 30))
  check CV(ldt) == tcfg["date_time"]
  ldt = dateTime(2019, Month(3), 28, 23, 27, 4, 314159000, staticTz(-5, -30))
  check CV(ldt) == tcfg["neg_offset_time"]
  ldt = dateTime(2019, Month(3), 28, 23, 27, 4, 271828000)
  check CV(ldt) == tcfg["alt_date_time"]
  ldt = dateTime(2019, Month(3), 28, 23, 27, 4)
  check CV(ldt) == tcfg["no_ms_time"]
  check CV(3.3) == tcfg["computed"]
  check CV(2.7) == tcfg["computed2"]
  check abs(tcfg["computed3"].floatValue - 0.9) < 1.0e-7
  check CV(10.0) == tcfg["computed4"]
  discard cfg.getSubConfig("base")
  ev = CV(@[
    "derived_foo", "derived_bar", "derived_baz",
    "test_foo", "test_bar", "test_baz",
    "base_foo", "base_bar", "base_baz"
  ])
  check ev == cfg["combined_list"]
  var m = {
    "foo_key": CV("base_foo"),
    "bar_key": CV("base_bar"),
    "baz_key": CV("base_baz"),
    "base_foo_key": CV("base_foo"),
    "base_bar_key": CV("base_bar"),
    "base_baz_key": CV("base_baz"),
    "derived_foo_key": CV("derived_foo"),
    "derived_bar_key": CV("derived_bar"),
    "derived_baz_key": CV("derived_baz"),
    "test_foo_key": CV("test_foo"),
    "test_bar_key": CV("test_bar"),
    "test_baz_key": CV("test_baz"),
  }.toTable
  check CV(m) == cfg["combined_map_1"]
  m = {
    "derived_foo_key": CV("derived_foo"),
    "derived_bar_key": CV("derived_bar"),
    "derived_baz_key": CV("derived_baz"),
  }.toTable
  check CV(m) == cfg["combined_map_2"]
  ev = CV(bitand(cfg["number_1"].intValue, cfg["number_2"].intValue))
  check ev == cfg["number_3"]
  ev = CV(bitxor(cfg["number_1"].intValue, cfg["number_2"].intValue))
  check ev == cfg["number_4"]

  type
    TCase = object
      text: string
      msg: string

  var cases = @[
      TCase(text: "logging[4]", msg: "invalid container for numeric index: NestedConfigValue"),
      TCase(text: "logging[:4]", msg: "invalid container for slicing: NestedConfigValue"),
      TCase(text: "no_such_key", msg: "not found in configuration: no_such_key"),
  ]

  for tcase in cases:
    try:
      discard cfg[tcase.text]
      assert false, "Exception should have been raised, but wasn't"
    except ConfigError as e:
      check tcase.msg == e.msg

test "example config":
  var p = dataFilePath("derived", "example.cfg")
  var cfg = newConfig()
  cfg.includePath.add(dataFilePath("base"))
  cfg.loadFile(p)

  check cfg["snowman_escaped"] == cfg["snowman_unescaped"]
  check CV("☃") == cfg["snowman_escaped"]
  check CV("😂") == cfg["face_with_tears_of_joy"]
  check CV("😂") == cfg["unescaped_face_with_tears_of_joy"]
  var ev = CV(@[
    "Oscar Fingal O'Flahertie Wills Wilde",
    "size: 5\""
  ])
  check ev == cfg["strings[:2]"]

  #
  # Note: Newlines are usually different on Windows, but not
  # necessarily if you're using Mercurial!
  #
  when defined(windows):
    ev = CV(@[
      "Triple quoted form\r\ncan span\r\n'multiple' lines",
      "with \"either\"\r\nkind of 'quote' embedded within"
    ])
  else:
    ev = CV(@[
      "Triple quoted form\ncan span\n'multiple' lines",
      "with \"either\"\nkind of 'quote' embedded within"
    ])
  check ev == cfg["strings[2:]"]
  check CV(getEnv("HOME")) == cfg["special_value_2"]
  ev = CV(dateTime(2019, Month(3), 28, 23, 27, 4, 314159000, staticTz(5, 30, 43)))
  check ev == cfg["special_value_3"]
  check CV("bar") == cfg["special_value_4"]

  # integers

  check CV(123) == cfg["decimal_integer"]
  check CV(0x123) == cfg["hexadecimal_integer"]
  check CV(83) == cfg["octal_integer"]
  check CV(0b000100100011) == cfg["binary_integer"]

  # floats

  check CV(123.456) == cfg["common_or_garden"]
  check CV(0.123) == cfg["leading_zero_not_needed"]
  check CV(123.0) == cfg["trailing_zero_not_needed"]
  check CV(1.0e6) == cfg["scientific_large"]
  check CV(1.0e-7) == cfg["scientific_small"]
  check CV(3.14159) == cfg["expression_1"]

  # complex

  check CV(complex64(3.0, 2.0)) == cfg["expression_2"]
  check CV(complex64(1.0, 3.0)) == cfg["list_value[4]"]

  # bool

  check CV(true) == cfg["boolean_value"]
  check CV(false) == cfg["opposite_boolean_value"]
  check CV(false) == cfg["computed_boolean_2"]
  check CV(true) == cfg["computed_boolean_1"]

  # list

  check CV(@["a", "b", "c"]) == cfg["incl_list"]

  # mapping

  var m = {"bar": CV("baz"), "foo": CV("bar")}.toTable
  check m == cfg.getSubConfig("incl_mapping").asDict()
  m = {"baz": CV("bozz"), "fizz": CV("buzz")}.toTable
  check m == cfg.getSubConfig("incl_mapping_body").asDict()

test "duplicates":
  var p = dataFilePath("derived", "dupes.cfg")
  var cfg = newConfig()

  try:
    cfg.loadFile(p)
    assert false, "Exception should have been thrown, but wasn't"
  except ConfigError as e:
    check e.msg == "duplicate key foo seen at (4, 1) (previously at (1, 1))"
  cfg.noDuplicates = false
  cfg.loadFile(p)
  check CV("not again!") == cfg["foo"]

test "context":
  var p = dataFilePath("derived", "context.cfg")
  var cfg = newConfig()
  cfg.context = {"bozz": CV("bozz-bozz")}.toTable
  cfg.loadFile(p)
  check CV("bozz-bozz") == cfg["baz"]
  try:
    discard cfg["bad"]
    assert false, "Exception should have been thrown, but wasn't"
  except ConfigError as e:
    check e.msg == "unknown variable: not_there"

test "config expressions":
  var p = dataFilePath("derived", "test.cfg")
  var cfg = fromFile(p)
  var m = {"a": CV("b"), "c": CV("d")}.toTable
  check CV(m) == cfg["dicts_added"]
  m = {
    "a": CV({"b": CV("c"), "w": CV("x")}.toTable),
    "d": CV({"e": CV("f"), "y": CV("z")}.toTable)
  }.toTable
  check CV(m) == cfg["nested_dicts_added"]
  check [CV("a"), CV(1), CV("b"), CV(2)] == cfg["lists_added"].listValue
  check [CV(1), CV(2)] == cfg["list[:2]"].listValue
  m = {"a": CV("b")}.toTable
  check CV(m) == cfg["dicts_subtracted"]
  m.clear()
  check CV(m) == cfg["nested_dicts_subtracted"]
  m = {
    "a_list": CV(@[CV(1), CV(2), CV({"a": CV(3)}.toTable)]),
    "a_map": CV({"k1": CV(@[CV("b"), CV("c"), CV({"d": CV(
        "e")}.toTable)])}.toTable)
  }.toTable
  check CV(m) == cfg["dict_with_nested_stuff"]
  check CV(@[CV(1), CV(2)]) == cfg["dict_with_nested_stuff.a_list[:2]"]
  check CV(-4) == cfg["unary"]
  check CV("mno") == cfg["abcdefghijkl"]
  check CV(8) == cfg["power"]
  check CV(2.5) == cfg["computed5"]
  check CV(2) == cfg["computed6"]
  check CV(complex64(3, 1)) == cfg["c3"]
  check CV(complex64(5, 5)) == cfg["c4"]
  check CV(2) == cfg["computed8"]
  check CV(160) == cfg["computed9"]
  check CV(62) == cfg["computed10"]
  check CV("b") == cfg["dict.a"]

  # interpolation

  check CV("A-4 a test_foo true 10 1e-07 1e+20 1 b [a, c, e, g]Z") == cfg["interp"]
  check CV("{a: b}") == cfg["interp2"]

  type
    TCase = object
      text: string
      msg: string

  var cases = @[
    TCase(text: "bad_include", msg: "@ operand must be a string, but is IntegerValue"),
    TCase(text: "computed7", msg: "not found in configuration: float4"),
    TCase(text: "bad_interp", msg: "unable to convert string: ${computed7}"),
  ]

  for tcase in cases:
    try:
      discard cfg[tcase.text]
      assert false, "Exception should have been thrown but wasn't"
    except ConfigError as e:
      check tcase.msg == e.msg

test "forms":
  var p = dataFilePath("derived", "forms.cfg")
  var cfg = newConfig()
  cfg.includePath.add(dataFilePath("base"))
  cfg.loadFile(p)

  type
    TCase = object
      text: string
      ev: ConfigValue

  var cases = @[
      TCase(text: "modals.deletion.contents[0].id", ev: CV("frm-deletion")),
      TCase(text: "refs.delivery_address_field", ev: CV({
        "kind": CV("field"),
        "type": CV("textarea"),
        "name": CV("postal_address"),
        "label": CV("Postal address"),
        "label_i18n": CV("postal-address"),
        "short_name": CV("address"),
        "placeholder": CV("We need this for delivering to you"),
        "ph_i18n": CV("your-postal-address"),
        "message": CV(" "),
        "required": CV(true),
        "attrs": CV({"minlength": CV(10)}.toTable),
        "grpclass": CV("col-md-6"),
    }.toTable)),
    TCase(text: "refs.delivery_instructions_field", ev: CV({
      "kind": CV("field"),
      "type": CV("textarea"),
      "name": CV("delivery_instructions"),
      "label": CV("Delivery Instructions"),
      "short_name": CV("notes"),
      "placeholder": CV("Any special delivery instructions?"),
      "message": CV(" "),
      "label_i18n": CV("delivery-instructions"),
      "ph_i18n": CV("any-special-delivery-instructions"),
      "grpclass": CV("col-md-6"),
    }.toTable)),
    TCase(text: "refs.verify_field", ev: CV({
      "kind": CV("field"),
      "type": CV("input"),
      "name": CV("verification_code"),
      "label": CV("Verification code"),
      "label_i18n": CV("verification-code"),
      "short_name": CV("verification code"),
      "placeholder": CV("Your verification code (NOT a backup code)"),
      "ph_i18n": CV("verification-not-backup-code"),
      "attrs": CV({
        "minlength": CV(6),
        "maxlength": CV(6),
        "autofocus": CV(true)
      }.toTable),
      "append": CV({
        "label": CV("Verify"),
        "type": CV("submit"),
        "classes": CV("btn-primary")
      }.toTable),
      "message": CV(" "),
      "required": CV(true),
    }.toTable)),
    TCase(text: "refs.signup_password_field", ev: CV({
        "kind": CV("field"),
        "type": CV("password"),
        "label": CV("Password"),
        "label_i18n": CV("password"),
        "message": CV(" "),
        "name": CV("password"),
        "ph_i18n": CV("password-wanted-on-site"),
        "placeholder": CV("The password you want to use on this site"),
        "required": CV(true),
        "toggle": CV(true),
    }.toTable)),
    TCase(text: "refs.signup_password_conf_field", ev: CV({
        "kind": CV("field"),
        "type": CV("password"),
        "name": CV("password_conf"),
        "label": CV("Password confirmation"),
        "label_i18n": CV("password-confirmation"),
        "placeholder": CV("The same password, again, to guard against mistyping"),
        "ph_i18n": CV("same-password-again"),
        "message": CV(" "),
        "toggle": CV(true),
        "required": CV(true),
    }.toTable)),
    TCase(text: "fieldsets.signup_ident[0].contents[0]", ev: CV({
        "kind": CV("field"),
        "type": CV("input"),
        "name": CV("display_name"),
        "label": CV("Your name"),
        "label_i18n": CV("your-name"),
        "placeholder": CV("Your full name"),
        "ph_i18n": CV("your-full-name"),
        "message": CV(" "),
        "data_source": CV("user.display_name"),
        "required": CV(true),
        "attrs": CV({"autofocus": CV(true)}.toTable),
        "grpclass": CV("col-md-6"),
    }.toTable)),
    TCase(text: "fieldsets.signup_ident[0].contents[1]", ev: CV({
        "kind": CV("field"),
        "type": CV("input"),
        "name": CV("familiar_name"),
        "label": CV("Familiar name"),
        "label_i18n": CV("familiar-name"),
        "placeholder": CV("If not just the first word in your full name"),
        "ph_i18n": CV("if-not-first-word"),
        "data_source": CV("user.familiar_name"),
        "message": CV(" "),
        "grpclass": CV("col-md-6"),
    }.toTable)),
    TCase(text: "fieldsets.signup_ident[1].contents[0]", ev: CV({
        "kind": CV("field"),
        "type": CV("email"),
        "name": CV("email"),
        "label": CV("Email address (used to sign in)"),
        "label_i18n": CV("email-address"),
        "short_name": CV("email address"),
        "placeholder": CV("Your email address"),
        "ph_i18n": CV("your-email-address"),
        "message": CV(" "),
        "required": CV(true),
        "data_source": CV("user.email"),
        "grpclass": CV("col-md-6"),
    }.toTable)),
    TCase(text: "fieldsets.signup_ident[1].contents[1]", ev: CV({
        "kind": CV("field"),
        "type": CV("input"),
        "name": CV("mobile_phone"),
        "label": CV("Phone number"),
        "label_i18n": CV("phone-number"),
        "short_name": CV("phone number"),
        "placeholder": CV("Your phone number"),
        "ph_i18n": CV("your-phone-number"),
        "classes": CV("numeric"),
        "message": CV(" "),
        "prepend": CV({"icon": CV("phone")}.toTable),
        "attrs": CV({"maxlength": CV(10)}.toTable),
        "required": CV(true),
        "data_source": CV("customer.mobile_phone"),
        "grpclass": CV("col-md-6"),
    }.toTable)),
  ]

  for tcase in cases:
    check tcase.ev == cfg[tcase.text]

test "path across includes":
  var p = dataFilePath("base", "main.cfg")
  var cfg = fromFile(p)
  check CV("run/server.log") == cfg["logging.appenders.file.filename"]
  check CV(true) == cfg["logging.appenders.file.append"]
  check CV("run/server-errors.log") == cfg["logging.appenders.error.filename"]
  check CV(false) == cfg["logging.appenders.error.append"]
  check CV("https://freeotp.github.io/") == cfg["redirects.freeotp.url"]
  check CV(false) == cfg["redirects.freeotp.permanent"]

test "circular references":
  var p = dataFilePath("derived", "test.cfg")
  var cfg = fromFile(p)

  type
    TCase = object
      text: string
      msg: string

  var cases = @[
    TCase(text: "circ_list[1]", msg: "circular reference: circ_list[1] (46, 5)"),
    TCase(text: "circ_map.a", msg: "circular reference: circ_map.b (51, 8), circ_map.c (52, 8), circ_map.a (53, 8)"),
  ]

  for tcase in cases:
    try:
      discard cfg[tcase.text]
      assert false, "Exception should have been raised but wasn't"
    except ConfigError as e:
      check tcase.msg == e.msg

test "slices and indices":
  var p = dataFilePath("derived", "test.cfg")
  var cfg = fromFile(p)

  type
    TCase = object
      text: string
      ev: ConfigValue

  var theList = CV(@["a", "b", "c", "d", "e", "f", "g"])

  # slices

  var cases = @[
    TCase(text: "test_list[:]", ev: theList),
    TCase(text: "test_list[::]", ev: theList),
    TCase(text: "test_list[:20]", ev: theList),
    TCase(text: "test_list[-20:4]", ev: CV(@["a", "b", "c", "d"])),
    TCase(text: "test_list[-20:20]", ev: theList),
    TCase(text: "test_list[2:]", ev: CV(@["c", "d", "e", "f", "g"])),
    TCase(text: "test_list[-3:]", ev: CV(@["e", "f", "g"])),
    TCase(text: "test_list[-2:2:-1]", ev: CV(@["f", "e", "d"])),
    TCase(text: "test_list[::-1]", ev: CV(@["g", "f", "e", "d", "c", "b",
        "a"])),
    TCase(text: "test_list[2:-2:2]", ev: CV(@["c", "e"])),
    TCase(text: "test_list[::2]", ev: CV(@["a", "c", "e", "g"])),
    TCase(text: "test_list[::3]", ev: CV(@["a", "d", "g"])),
    TCase(text: "test_list[::2][::3]", ev: CV(@["a", "g"])),
  ]

  for tcase in cases:
    var v = cfg[tcase.text]
    check tcase.ev == v

  # indices

  var lv = theList.listValue
  for i, v in lv:
    check v == cfg[&"test_list[{i}]"]

  # negative indices

  var n = len(lv)
  for i in n..1:
    check lv[n - i] == cfg[&"test_list[-{i}]"]

  # invalid indices

  for i in [n, n + 1, -(n + 1), -(n + 2)]:
    try:
      discard cfg[&"test_list[{i}]"]
      assert false, "Exception should have been raised, but wasn't"
    except ConfigError as e:
      var emsg = &"index out of range: is {i}, must be between 0 and 6"
      check e.msg == emsg

test "include paths":
  var p1 = dataFilePath("derived", "test.cfg")
  var p2 = p1.absolutePath
  var plist = [p1, p2]
  for path in plist:
    var p = path.replace("\\", "/")
    var source = &"test: @'{p}'"
    var cfg = fromSource(source)

    check CV(2) == cfg["test.computed6"]

test "nested include paths":
  var base = dataFilePath("base")
  var derived = dataFilePath("derived")
  var another = dataFilePath("another")
  var p = base / "top.cfg"
  var cfg = fromFile(p)
  cfg.includePath = @[derived, another]
  check CV(42) == cfg["level1.level2.final"]

test "path recursion":
  var p = dataFilePath("derived", "recurse.cfg")
  var cfg = fromFile(p)
  try:
    echo cfg["recurse"]
  except ConfigError as e:
    check e.msg == "configuration cannot include itself: recurse.cfg"
