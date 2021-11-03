# config

A Nim library for working with the CFG configuration format.

## Installation

The library can be installed for use by adding a dependency on `config` to your list of dependencies in your `project.nimble` file:

```
requires "config >= 0.1.0"
```

## Usage

The CFG configuration format is a text format for configuration files which is similar to, and a superset of, the JSON format. It dates from before its first announcement in [2008](https://wiki.python.org/moin/HierConfig) and has the following aims:

* Allow a hierarchical configuration scheme with support for key-value mappings and lists.
* Support cross-references between one part of the configuration and another.
* Provide a string interpolation facility to easily build up configuration values from other configuration values.
* Provide the ability to compose configurations (using include and merge facilities).
* Provide the ability to access real application objects safely, where supported by the platform.
* Be completely declarative.

It overcomes a number of drawbacks of JSON when used as a configuration format:

* JSON is more verbose than necessary.
* JSON doesn’t allow comments.
* JSON doesn’t provide first-class support for dates and multi-line strings.
* JSON doesn’t allow trailing commas in lists and mappings.
* JSON doesn’t provide easy cross-referencing, interpolation, or composition.

A simple example
================

With the following configuration file, `test0.cfg`:
```text
a: 'Hello, '
b: 'world!'
c: {
  d: 'e'
}
'f.g': 'h'
christmas_morning: `2019-12-25 08:39:49`
home: `$HOME`
foo: `$FOO|bar`
```

You can load and query the above configuration using [inim](https://github.com/inim-repl/INim):

Loading a configuration
-----------------------

The configuration above can be loaded as shown below. In the REPL shell:
```text
nim> import config
var cfg = fromFile("test0.cfg")
```

The successful call returns a `Config` object which can be used to query the configuration.

Access elements with keys
-------------------------
Accessing elements of the configuration with a simple key is not much harder than using a map:
```text
nim> echo cfg["a"]
(kind: StringValue, stringValue: "Hello, ")
nim> echo cfg["b"]
(kind: StringValue, stringValue: "world!")
```

As Nim is strongly and statically typed, configuration values are returned in a tagged variant of type ``ConfigValue`` with the `kind` field as the discriminant.

Access elements with paths
--------------------------
As well as simple keys, elements can also be accessed using path strings:
```text
nim> echo cfg["c.d"]
(kind: StringValue, stringValue: "e")
```
Here, the desired value is obtained in a single step, by (under the hood) walking the path `c.d` – first getting the mapping at key `c`, and then the value at `d` in the resulting mapping.

Note that you can have simple keys which look like paths:
```text
nim> echo cfg["f.g"]
(kind: StringValue, stringValue: "h")
```
If a key is given that exists in the configuration, it is used as such, and if it is not present in the configuration, an attempt is made to interpret it as a path. Thus, `f.g` is present and accessed via key, whereas `c.d` is not an existing key, so is interpreted as a path.

Access to date/time objects
---------------------------
You can also get native Elixir date/time objects from a configuration, by using an ISO date/time pattern in a backtick-string:
```text
nim> echo cfg["christmas_morning"]
(kind: DateTimeValue, dateTimeValue: (nanosecond: 0, second: 49, minute: 39, hour: 8, monthdayZero: 25, monthZero: 12, year: 2019, weekday: Wednesday, yearday: 358, isDst: false, timezone: ..., utcOffset: 0))
```
Access to environment variables
-------------------------------
To access an environment variable, use a backtick-string of the form `$VARNAME`:
```text
nim> import os
nim> echo cfg["home"].stringValue == getEnv("HOME")
true
```
You can specify a default value to be used if an environment variable isn’t present using the `$VARNAME|default-value` form. Whatever string follows the pipe character (including the empty string) is returned if the VARNAME is not a variable in the environment.
```text
nim> echo cfg["foo"]
(kind: StringValue, stringValue: "bar")
```

For more information, see [the CFG documentation](https://docs.red-dove.com/cfg/index.html).
