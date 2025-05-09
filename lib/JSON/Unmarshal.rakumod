use JSON::Name:ver<0.0.6+>;
use JSON::OptIn;
use JSON::Fast;

unit module JSON::Unmarshal;

our class X::CannotUnmarshal is Exception {
    has Attribute:D $.attribute is required;
    has Any:D $.json is required;
    has Mu:U $.type is required;
    has Mu:U $.target is required;
    has Str $.why;
    method message {
        "Cannot unmarshal {$.json.raku} into type '{$.type.^name}' for attribute {$.attribute.name} of '{$.target.^name}'"
        ~ ($.why andthen ": $_" orelse "")
    }
}

our class X::UnusedKeys is Exception {
    has Set:D $.unused-keys is required;
    has Mu:U $.type is required;
    method message {
        my $sfx = $!unused-keys.elems > 1 ?? "s" !! "";
        "No attribute$sfx found in '" ~ $!type.^name ~ "' for JSON key$sfx " ~ $!unused-keys.keys.sort.map("'" ~ * ~ "'").join(", ")
    }
}

enum ErrorMode <EM_IGNORE EM_WARN EM_THROW>;
my class UnmarshalParams {
    has Bool $.opt-in;
    has ErrorMode $.error-mode;
}

role CustomUnmarshaller does JSON::OptIn::OptedInAttribute {
    method unmarshal($value, Mu:U $type) {
        ...
    }
}

role CustomUnmarshallerCode does CustomUnmarshaller {
    has &.unmarshaller is rw;

    method unmarshal($value, Mu:U $) {
        # the dot below is important otherwise it refers
        # to the accessor method
        self.unmarshaller.($value);
    }
}

role CustomUnmarshallerMethod does CustomUnmarshaller {
    has Str $.unmarshaller is rw;
    method unmarshal($value, Mu:U $type) {
        my $meth = self.unmarshaller;
        $type."$meth"($value);
    }
}

multi sub trait_mod:<is> (Attribute $attr, :&unmarshalled-by!) is export {
    $attr does CustomUnmarshallerCode;
    $attr.unmarshaller = &unmarshalled-by;
}

multi sub trait_mod:<is> (Attribute $attr, Str:D :$unmarshalled-by!) is export {
    $attr does CustomUnmarshallerMethod;
    $attr.unmarshaller = $unmarshalled-by;
}

proto sub panic(Any, Mu, |) {*}
multi sub panic($json, Mu \type, X::CannotUnmarshal:D $ex) {
    $ex.rethrow
}
multi sub panic($json, Mu \type, Exception:D $ex) {
    panic($json, type, $ex.message)
}
multi sub panic($json, Mu \type, Str $why?) {
    X::CannotUnmarshal.new(
        :$json,
        :type(type.WHAT),
        :attribute($*JSON-UNMARSHAL-ATTR),
        :$why,
        :target($*JSON-UNMARSHAL-TYPE) ).throw
}

my sub maybe-nominalize(Mu \obj) is pure is raw {
    obj.HOW.archetypes.nominalizable ?? obj.^nominalize !! obj
}

multi _unmarshal(Any:U, Mu $type) {
    $type;
}

multi _unmarshal(Any:D $json, Int) {
    if $json ~~ Int {
        return Int($json)
    }
    panic($json, Int)
}

multi _unmarshal(Any:D $json, Rat) {
   CATCH {
      default {
         panic($json, Rat, $_);
      }
   }
   Rat($json)
}

multi _unmarshal(Any:D $json, Numeric) {
    if $json ~~ Numeric {
        return Num($json)
    }
    panic($json, Numeric)
}

multi _unmarshal($json, Str) {
    if $json ~~ Stringy {
        return Str($json)
    }
    else {
        Str;
    }
}

multi _unmarshal(Any:D $json, Bool) {
   CATCH {
      default {
         panic($json, Bool, $_);
      }
   }
   Bool($json);
}

subset PosNoAccessor of Positional where { ! maybe-nominalize($_).^attributes.first({ .has_accessor || .is_built }) };

multi _unmarshal(%json, PosNoAccessor $obj ) {
    panic(%json, Positional, "type mismatch");
}

# A class-like type is the one we can instantiate and it has at least one public or `is build`-marked attribute.
subset ClassLike of Mu
    where -> Mu \type {
        .HOW.archetypes.nominal
        && .HOW.^can('attributes')
        && .^attributes.first({ $_ ~~ Attribute && (.has_accessor || .is_built) })
            given maybe-nominalize(type)
    };

multi _unmarshal(%json, ClassLike $obj is raw) {
    my %args;
    my $params = $*JSON-UNMARSHAL-PARAMS;
    my SetHash $used-json-keys .= new;
    my \type = $obj.HOW.archetypes.nominalizable ?? $obj.^nominalize !! $obj.WHAT;
    my %local-attrs =  type.^attributes(:local).map({ $_.name => $_.package });
    for type.^attributes -> $attr {
        my $*JSON-UNMARSHAL-ATTR = $attr;
        if %local-attrs{$attr.name}:exists && !(%local-attrs{$attr.name} === $attr.package ) {
            next;
        }
        if $params.opt-in && $attr !~~ JSON::OptIn::OptedInAttribute {
            next;
        }
        my $attr-name = $attr.name.substr(2);
        my $json-name = do if  $attr ~~ JSON::Name::NamedAttribute {
            $attr.json-name;
        }
        else {
            $attr-name;
        }
        if %json{$json-name}:exists {
            my Mu $attr-type := $attr.type;
            my $is-nominalizable = $attr-type.HOW.archetypes.nominalizable;
            $used-json-keys.set($json-name);

            %args{$attr-name} := do if $attr ~~ CustomUnmarshaller {
                $attr.unmarshal(%json{$json-name}, $attr-type)
            }
            elsif $is-nominalizable && $attr-type.HOW.archetypes.coercive && %json{$json-name} ~~ $attr-type
            {
                # No need to unmarshal, coercion will take care of it
                %json{$json-name}
            }
            else {
                _unmarshal(%json{$json-name}, $is-nominalizable ?? $attr-type.^nominalize !! $attr-type)
            }
        }
    }
    if ((my $err-mode = $params.error-mode) != EM_IGNORE)
        && (my $unused-keys = (%json.keys.Set (-) $used-json-keys))
    {
        my $ex = X::UnusedKeys.new: :$unused-keys, :type(type);
        if $err-mode == EM_WARN {
           warn($ex.message)
        }
        else {
           $ex.throw
        }
    }
    type.new(|%args)
}

multi _unmarshal($json, @x) {
    my @ret := Array[@x.of].new;
    for $json.list -> $value {
       my $type = @x.of =:= Any ?? $value.WHAT !! @x.of;
       @ret.append(_unmarshal($value, $type));
    }
    @ret
}

multi _unmarshal(%json, %x) {
   my %ret := Hash[%x.of].new;
   for %json.kv -> $key, $value {
      my $type = %x.of =:= Any ?? $value.WHAT !! %x.of;
      %ret{$key} = _unmarshal($value, $type);
   }
   %ret
}

multi _unmarshal(Any:D $json, Mu) {
    $json
}

my sub _unmarshall-context(\obj, % (Bool :$opt-in, Bool :$warn, Bool :die(:$throw), *%extra), &code) is raw {
    if %extra {
        with "Unsupported arguments: " ~ %extra.keys.sort.map("'" ~ * ~ "'").join(", ") {
            $throw ?? die $_ !! warn $_
        }
    }
    my $*JSON-UNMARSHAL-TYPE := obj.WHAT;
    my $*JSON-UNMARSHAL-PARAMS :=
        UnmarshalParams.new: :$opt-in, error-mode => ($throw ?? EM_THROW !! ($warn ?? EM_WARN !! EM_IGNORE));
    code()
}

proto unmarshal(Any:D, |) is export {*}

multi unmarshal(Str:D $json, PosNoAccessor $obj, *%c) {
    _unmarshall-context $obj, %c, {
        my Any \data = from-json($json);
        if data ~~ Positional {
            return @(_unmarshal($_, $obj.of) for @(data));
        } else {
            fail "Unmarshaling to type $obj.^name() requires the json data to be a list of objects.";
        }
    }
}

multi unmarshal(Str:D $json, Associative $obj, *%c) {
    _unmarshall-context $obj, %c, {
        my \data = from-json($json);
        if data ~~ Associative {
            return %(for data.kv -> $key, $value {
                $key => _unmarshal($value, $obj.of)
            })
        } else {
            fail "Unmarshaling to type $obj.^name() requires the json data to be an object.";
        };
    }
}

multi unmarshal(Str:D $json, Mu $obj, *%c) {
    _unmarshall-context $obj, %c, {
        _unmarshal(from-json($json), $obj.WHAT)
    }
}

multi unmarshal(%json, $obj, *%c) {
    _unmarshall-context $obj, %c, {
        _unmarshal(%json, $obj.WHAT)
    }
}

multi unmarshal(@json, $obj, *%c) {
    _unmarshall-context $obj, %c, {
        _unmarshal(@json, $obj.WHAT)
    }
}

# vim: expandtab shiftwidth=4 ft=raku
