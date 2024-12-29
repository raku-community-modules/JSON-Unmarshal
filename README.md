[![Actions Status](https://github.com/raku-community-modules/JSON-Unmarshal/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/JSON-Unmarshal/actions) [![Actions Status](https://github.com/raku-community-modules/JSON-Unmarshal/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/JSON-Unmarshal/actions) [![Actions Status](https://github.com/raku-community-modules/JSON-Unmarshal/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/JSON-Unmarshal/actions)

NAME
====

JSON::Unmarshal - turn JSON into an Object (the opposite of JSON::Marshal)

SYNOPSIS
========

    use JSON::Unmarshal;

    class SomeClass {
        has Str $.string;
        has Int $.int;
    }

    my $json = '{ "string" : "string", "int" : 42 }';

    my SomeClass $object = unmarshal($json, SomeClass);

    say $object.string; # -> "string"
    say $object.int;    # -> 42

DESCRIPTION
===========

This provides a single exported subroutine to create an object from a JSON representation of an object.

It only initialises the "public" attributes (that is those with accessors created by declaring them with the '.' twigil. Attributes without acccessors are ignored.

`unmarshal` Routine
-------------------

`unmarshal` has the following signatures:

  * `unmarshal(Str:D $json, Positional $obj, *%)`

  * `unmarshal(Str:D $json, Associative $obj, *%)`

  * `unmarshal(Str:D $json, Mu $obj, *%)`

  * `unmarshal(%json, $obj, *%)`

  * `unmarshal(@json, $obj, *%)`

The signatures with associative and positional JSON objects are to be used for pre-parsed JSON data obtained from a different source. For example, this may happen when a framework deserializes it for you.

The following named arguments are supported:

  * **`Bool :$opt-in`**

    When falsy then all attributes of a class are deserialized. When *True* then only those marked with `is json` trait provided by `JSON::OptIn` module are taken into account.

  * **`Bool :$warn`**

    If set to *True* then the module will warn about some non-critical problems like unsupported named arguments or keys in JSON structure for which there no match attributes were found.

  * **`Bool :$die`** or **`Bool :$throw`**

    This is two aliases of the same attribute with meaning, similar to `:warn`, but where otherwise a waning would be issued the module will throw an exception.

Manual Unmarshalling
--------------------

It is also possible to use `is unmarshalled-by` trait to control how the value is unmarshalled:

```raku
use JSON::Unmarshal

class SomeClass {
    has Version $.version is unmarshalled-by(-> $v { Version.new($v) });
}

my $json = '{ "version" : "0.0.1" }';

my SomeClass $object = unmarshal($json, SomeClass);

say $object.version; # -> "v0.0.1"
```

The trait has two variants, one which takes a `Routine` as above, the other a `Str` representing the name of a method that will be called on the type object of the attribute type (such as "new"), both are expected to take the value from the JSON as a single argument.

COPYRIGHT AND LICENSE
=====================

Copyright 2015 - 2017 Tadeusz Sośnierz

Copyright 2022 - 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

