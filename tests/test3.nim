#
# Copyright 2016-2023 by Vinay Sajip. All Rights Reserved.
#
import complex
import os
import strutils
import tables
import times
import typetraits
import unittest

import ../src/config

proc dataFilePath(paths: varargs[string]): string =
  currentSourcePath.parentDir / "resources" / paths.join("/")

#
# Config
#

proc CV(s: string): ConfigValue =
  ConfigValue(kind: StringValue, stringValue: s)


test "main config":
  var p = dataFilePath("derived", "main.cfg")
  var cfg = newConfig()
  cfg.includePath.add(dataFilePath("base"))
  cfg.loadFile(p)

  var lcfg = cfg.getSubConfig("logging")
  var ev = CV("bar")
  check ev == lcfg.get("foo.bar", ev)
  #ev.stringValue = "bozz"
  echo "Before test"
  discard parsePath("handlers.debug.lvl")
  #check ev == lcfg.get("handlers.debug.lvl", ev)
  echo "After test"
