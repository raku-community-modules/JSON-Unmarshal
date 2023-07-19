use Test;
use JSON::Unmarshal;

plan 2;

class Foo {
    has Int $.count;
    has Bool $.check;
}

my $json = '{"count": 42, "check": true, "description": "about something", "name": "fubar" }';

{
    my $warn-msg;
    CONTROL {
        when CX::Warn {
            $warn-msg = .message;
            .resume
        }
    }
    my Foo $foo = unmarshal $json, Foo, :warn;
    my $msg = "a warning produced for unsued JSON keys with :warn";
    with $warn-msg {
        like $_, /"No attributes found " .* "'description', 'name'"/, $msg;
    }
    else {
        flunk $msg;
    }
}
throws-like 
    { my Foo $foo = unmarshal $json, Foo, :throw; },
    X::UnusedKeys,
    :unused-keys(<description name>.Set),
    "an exception is thrown for unsued JSON keys with :throw (or :die)";
